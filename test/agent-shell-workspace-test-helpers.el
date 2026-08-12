;;; agent-shell-workspace-test-helpers.el --- Shared test fixtures -*- lexical-binding: t; -*-

;;; Commentary:

;; Fake-agent fixtures shared by the unit suite (batch-safe) and the
;; e2e suite (real frame).  A fake satisfies everything the package and
;; `agent-shell-buffers' inspect: the major mode, a non-nil
;; `shell-maker--config' (agent-shell 0.69+ filters on it), a state
;; alist, and -- for status-detection tests -- a live process.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agent-shell-workspace)

(defvar agent-shell-workspace-test--buffers nil
  "Fake agent buffers created for the current test.")

(defun agent-shell-workspace-test--make-agent (name directory title &rest state)
  "Create a fake agent buffer NAME in DIRECTORY with session TITLE.
STATE entries are prepended to the buffer's state alist, so a test can
override any key the defaults provide -- `map-elt' takes the first match."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      ;; The sidebar only ever asks `derived-mode-p', so this is enough of an
      ;; agent-shell buffer without standing up an ACP process.
      (setq major-mode 'agent-shell-mode)
      ;; agent-shell 0.69+ additionally requires a non-nil
      ;; `shell-maker--config' before `agent-shell-buffers' will list a
      ;; buffer; without it every fake is filtered out and the suite
      ;; falls through to starting a real agent.
      (setq-local shell-maker--config (list :name "fake"))
      (setq-local default-directory directory)
      (setq-local agent-shell--state
                  (append state
                          (list (cons :session (list (cons :title title)))))))
    (push buffer agent-shell-workspace-test--buffers)
    buffer))

(defun agent-shell-workspace-test--make-live-agent (name directory &rest state)
  "Create a fake agent NAME in DIRECTORY with a live process.
The one process stands in for both the comint process and the ACP
client process, which is all the status logic checks for liveness.
STATE overrides the defaults as in `agent-shell-workspace-test--make-agent'."
  (let* ((buffer (apply #'agent-shell-workspace-test--make-agent
                        name directory "live session" state))
         (process (make-process :name (concat "fake " name)
                                :buffer buffer
                                :command '("sleep" "60")
                                :noquery t)))
    (with-current-buffer buffer
      (setq-local agent-shell--state
                  (append state
                          (list (cons :client (list (cons :process process)))
                                (cons :initialized t))
                          agent-shell--state)))
    buffer))

(defun agent-shell-workspace-test--teardown ()
  "Remove tabs, buffers, processes and global state left by a test."
  ;; Bounded: if closing ever stops making progress this must fail the run,
  ;; not spin forever.
  (let ((guard 8))
    (ignore-errors
      (while (and (agent-shell-workspace--tab-exists-p) (> guard 0))
        (setq guard (1- guard))
        (tab-bar-switch-to-tab agent-shell-workspace--tab-name)
        (tab-bar-close-tab))))
  ;; Close before killing.  A side window survives `delete-other-windows' by
  ;; design, so a test that opened the plain sidebar would otherwise leave the
  ;; window behind displaying a killed buffer, and the next test would find a
  ;; sidebar it never opened.
  (ignore-errors (agent-shell-workspace-sidebar-close))
  (when-let* ((sidebar (get-buffer agent-shell-workspace-sidebar-buffer-name)))
    (kill-buffer sidebar))
  (dolist (buffer agent-shell-workspace-test--buffers)
    (when (buffer-live-p buffer)
      (when-let* ((process (get-buffer-process buffer)))
        (delete-process process))
      (kill-buffer buffer)))
  (setq agent-shell-workspace-test--buffers nil)
  (setq agent-shell-workspace--previous-tab nil)
  (setq agent-shell-workspace-sidebar--pick-window nil)
  (clrhash agent-shell-workspace--previous-status)
  (clrhash agent-shell-workspace--finished-buffers)
  ;; Isolation state is global.  A test that toggled the workspace must not
  ;; leak its advice or display rules into the next test, and activation can
  ;; stack the advice (it is added by both the toggle and the tab hook), so
  ;; removing it once is not necessarily enough.
  (ignore-errors (agent-shell-workspace--deactivate-isolation))
  (while (advice-member-p #'agent-shell-workspace--switch-buffer-advice
                          'switch-to-buffer)
    (advice-remove 'switch-to-buffer
                   #'agent-shell-workspace--switch-buffer-advice))
  (remove-hook 'tab-bar-tab-post-select-functions
               #'agent-shell-workspace--on-tab-selected)
  (delete-other-windows))

(defmacro agent-shell-workspace-test--with-fixture (&rest body)
  "Run BODY, then tear down whatever fakes and global state it created."
  (declare (indent 0))
  `(unwind-protect
       (progn ,@body)
     (agent-shell-workspace-test--teardown)))

(defmacro agent-shell-workspace-test--with-agents (&rest body)
  "Run BODY with three fake agents across two projects.

Stubs `agent-shell--config-icon'.  Rendering a row asks agent-shell for
the agent's icon, which on a cache miss downloads a PNG -- and the cache
is keyed by theme, so a light-background test frame misses whatever the
user has cached.  Left alone that turns the suite into a network test
that blocks forever offline.  The sidebar already falls back to a plain
character when no icon is available."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'agent-shell--config-icon) (lambda (&rest _) "")))
     (agent-shell-workspace-test--with-fixture
       (tab-bar-mode 1)
       (agent-shell-workspace-test--make-agent
        "Claude Agent @ alpha" "/tmp/alpha/" "first alpha session")
       (agent-shell-workspace-test--make-agent
        "Codex Agent @ alpha" "/tmp/alpha/" "second alpha session")
       (agent-shell-workspace-test--make-agent
        "Claude Agent @ beta" "/tmp/beta/" "a beta session")
       ,@body)))

;;; Window and sidebar inspection

(defun agent-shell-workspace-test--sidebar-window ()
  "Return the live window showing the sidebar, or nil."
  (when-let* ((buffer (get-buffer agent-shell-workspace-sidebar-buffer-name)))
    (get-buffer-window buffer)))

(defun agent-shell-workspace-test--main-window ()
  "Return a window in the current tab that is not the sidebar."
  (let ((sidebar (agent-shell-workspace-test--sidebar-window)))
    (seq-find (lambda (window) (not (eq window sidebar))) (window-list))))

(defun agent-shell-workspace-test--main-windows ()
  "Return every non-side window, the ones tiling arranges."
  (seq-filter (lambda (window) (not (window-parameter window 'window-side)))
              (window-list)))

(defun agent-shell-workspace-test--agent-at-window-point ()
  "Return the agent buffer under the sidebar window's own point."
  (when-let* ((window (agent-shell-workspace-test--sidebar-window)))
    (with-current-buffer (window-buffer window)
      (save-excursion
        (goto-char (window-point window))
        (agent-shell-workspace-sidebar--buffer-at-point)))))

(defun agent-shell-workspace-test--project-at-window-point ()
  "Return the project key under the sidebar window's own point."
  (when-let* ((window (agent-shell-workspace-test--sidebar-window)))
    (with-current-buffer (window-buffer window)
      (save-excursion
        (goto-char (window-point window))
        (agent-shell-workspace-sidebar--project-at-point)))))

(defun agent-shell-workspace-test--park-on-header (label)
  "Move the sidebar window's point onto the group header shown as LABEL.
Matches on the rendered header text, so it finds the row whether the
group is expanded or collapsed."
  (let ((window (agent-shell-workspace-test--sidebar-window)))
    (with-current-buffer (window-buffer window)
      (goto-char (point-min))
      (let ((found nil))
        (while (and (not found) (not (eobp)))
          (if (and (not (agent-shell-workspace-sidebar--buffer-at-point))
                   (agent-shell-workspace-sidebar--project-at-point)
                   (string-match-p (regexp-quote label)
                                   (buffer-substring-no-properties
                                    (line-beginning-position)
                                    (line-end-position))))
              (setq found t)
            (forward-line 1)))
        (should found))
      (set-window-point window (point)))))

(defun agent-shell-workspace-test--collapse (label)
  "Collapse the group shown as LABEL through the real TAB command."
  (agent-shell-workspace-test--park-on-header label)
  (let ((window (agent-shell-workspace-test--sidebar-window)))
    (with-selected-window window
      (goto-char (window-point window))
      (agent-shell-workspace-sidebar-toggle-project)
      (set-window-point window (point)))))

(defun agent-shell-workspace-test--park-on (name)
  "Move the sidebar window's point onto the agent buffer called NAME."
  (let ((window (agent-shell-workspace-test--sidebar-window))
        (target (get-buffer name)))
    (with-current-buffer (window-buffer window)
      (goto-char (point-min))
      (let ((found nil))
        (while (and (not found) (not (eobp)))
          (if (eq target (agent-shell-workspace-sidebar--buffer-at-point))
              (setq found t)
            (forward-line 1)))
        (should found))
      (set-window-point window (point)))))

(defun agent-shell-workspace-test--run-on (name command)
  "Run COMMAND with the sidebar selected and point on the agent NAME."
  (agent-shell-workspace-test--park-on name)
  (let ((window (agent-shell-workspace-test--sidebar-window)))
    (with-selected-window window
      (goto-char (window-point window))
      (funcall command))))

(defun agent-shell-workspace-test--select-agent (name)
  "Select the agent called NAME through the real selection path."
  (agent-shell-workspace-test--run-on
   name #'agent-shell-workspace-sidebar-goto))

(provide 'agent-shell-workspace-test-helpers)
;;; agent-shell-workspace-test-helpers.el ends here
