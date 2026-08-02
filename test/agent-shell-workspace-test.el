;;; agent-shell-workspace-test.el --- Tests for agent-shell-workspace -*- lexical-binding: t; -*-

;;; Commentary:

;; End-to-end tests for the sidebar's cursor and selection handling.
;;
;; These must run in a real Emacs with a real frame, NOT with --batch.
;; Batch mode never runs redisplay and never restores a window
;; configuration, so `window-point' bugs are invisible there: the very
;; class of bug these tests exist to catch.  See test/run.sh.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'agent-shell-workspace)

(defvar agent-shell-workspace-test--buffers nil
  "Fake agent buffers created for the current test.")

(defun agent-shell-workspace-test--make-agent (name directory title)
  "Create a fake agent buffer NAME in DIRECTORY with session TITLE."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      ;; The sidebar only ever asks `derived-mode-p', so this is enough of an
      ;; agent-shell buffer without standing up an ACP process.
      (setq major-mode 'agent-shell-mode)
      (setq-local default-directory directory)
      (setq-local agent-shell--state
                  (list (cons :session (list (cons :title title))))))
    (push buffer agent-shell-workspace-test--buffers)
    buffer))

(defun agent-shell-workspace-test--teardown ()
  "Remove tabs, buffers and state left by a test."
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
      (kill-buffer buffer)))
  (setq agent-shell-workspace-test--buffers nil)
  (setq agent-shell-workspace--previous-tab nil)
  (delete-other-windows))

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
     (unwind-protect
         (progn
           (tab-bar-mode 1)
           (agent-shell-workspace-test--make-agent
            "Claude Agent @ alpha" "/tmp/alpha/" "first alpha session")
           (agent-shell-workspace-test--make-agent
            "Codex Agent @ alpha" "/tmp/alpha/" "second alpha session")
           (agent-shell-workspace-test--make-agent
            "Claude Agent @ beta" "/tmp/beta/" "a beta session")
           ,@body)
       (agent-shell-workspace-test--teardown))))

(defun agent-shell-workspace-test--sidebar-window ()
  "Return the live window showing the sidebar, or nil."
  (when-let* ((buffer (get-buffer agent-shell-workspace-sidebar-buffer-name)))
    (get-buffer-window buffer)))

(defun agent-shell-workspace-test--agent-at-window-point ()
  "Return the agent buffer under the sidebar window's own point."
  (when-let* ((window (agent-shell-workspace-test--sidebar-window)))
    (with-current-buffer (window-buffer window)
      (save-excursion
        (goto-char (window-point window))
        (agent-shell-workspace-sidebar--buffer-at-point)))))

(defun agent-shell-workspace-test--main-window ()
  "Return a window in the Agents tab that is not the sidebar."
  (let ((sidebar (agent-shell-workspace-test--sidebar-window)))
    (seq-find (lambda (window) (not (eq window sidebar))) (window-list))))

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

(ert-deftest agent-shell-workspace-test-cursor-survives-refresh ()
  "A refresh must not move the sidebar window's point."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-toggle)
    (agent-shell-workspace-test--park-on "Codex Agent @ alpha")
    (agent-shell-workspace-sidebar-refresh)
    (redisplay t)
    (should (eq (get-buffer "Codex Agent @ alpha")
                (agent-shell-workspace-test--agent-at-window-point)))))

(ert-deftest agent-shell-workspace-test-cursor-survives-tab-switch ()
  "Leaving the Agents tab and coming back must not lose the cursor."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-toggle)
    (agent-shell-workspace-test--park-on "Codex Agent @ alpha")
    (redisplay t)
    ;; Away and back, the way the toggle command does it.
    (agent-shell-workspace-toggle)
    (redisplay t)
    (agent-shell-workspace-toggle)
    (redisplay t)
    (should (agent-shell-workspace-test--sidebar-window))
    (should (eq (get-buffer "Codex Agent @ alpha")
                (agent-shell-workspace-test--agent-at-window-point)))))

(ert-deftest agent-shell-workspace-test-cursor-survives-tab-close-reopen ()
  "Closing the Agents tab and reopening must restore the cursor."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-toggle)
    (agent-shell-workspace-sidebar-goto-buffer-for-test "Codex Agent @ alpha")
    (redisplay t)
    (tab-bar-close-tab)
    (redisplay t)
    (agent-shell-workspace-toggle)
    (redisplay t)
    (should (agent-shell-workspace-test--sidebar-window))
    (should (eq (get-buffer "Codex Agent @ alpha")
                (agent-shell-workspace-test--agent-at-window-point)))))

(ert-deftest agent-shell-workspace-test-selection-agrees-with-main-window ()
  "The marked selection and the agent shown in the main area must agree."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-toggle)
    (agent-shell-workspace-sidebar-goto-buffer-for-test "Codex Agent @ alpha")
    (redisplay t)
    (tab-bar-close-tab)
    (agent-shell-workspace-toggle)
    (redisplay t)
    (let ((sidebar (get-buffer agent-shell-workspace-sidebar-buffer-name)))
      (should (eq (buffer-local-value
                   'agent-shell-workspace-sidebar--selected-buffer sidebar)
                  (window-buffer (agent-shell-workspace-test--main-window)))))))

(ert-deftest agent-shell-workspace-test-killed-selection-recovers ()
  "Killing the selected agent must not wedge the selection on a dead buffer."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-toggle)
    (agent-shell-workspace-sidebar-goto-buffer-for-test "Codex Agent @ alpha")
    (kill-buffer "Codex Agent @ alpha")
    (agent-shell-workspace-sidebar-refresh)
    (redisplay t)
    (let* ((sidebar (get-buffer agent-shell-workspace-sidebar-buffer-name))
           (selected (buffer-local-value
                      'agent-shell-workspace-sidebar--selected-buffer sidebar)))
      (should (or (null selected) (buffer-live-p selected))))))

(ert-deftest agent-shell-workspace-test-sidebar-toggle-makes-no-tab ()
  "The plain sidebar toggle must not create a tab or disturb the layout."
  (agent-shell-workspace-test--with-agents
    (let ((tabs-before (length (tab-bar-tabs)))
          (buffer-before (window-buffer (selected-window))))
      (agent-shell-workspace-sidebar-toggle)
      (redisplay t)
      (should (agent-shell-workspace-test--sidebar-window))
      ;; A real side window, not a tab and not a takeover of the layout.
      (should (window-parameter (agent-shell-workspace-test--sidebar-window)
                                'window-side))
      (should (= tabs-before (length (tab-bar-tabs))))
      (should (not (agent-shell-workspace--tab-exists-p)))
      (should (eq buffer-before (window-buffer (selected-window))))
      ;; Toggling again puts it away.
      (agent-shell-workspace-sidebar-toggle)
      (redisplay t)
      (should (not (agent-shell-workspace-test--sidebar-window)))
      (should (= tabs-before (length (tab-bar-tabs)))))))

(ert-deftest agent-shell-workspace-test-collapsed-groups-stay-navigable ()
  "With every group collapsed, n/p must still move between the headers.

Collapsing the last expanded group leaves the sidebar with nothing but
headers.  Navigation that only knows about agent rows has no stops left,
so the motion keys go dead and the list cannot be reached again."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-sidebar-toggle)
    (redisplay t)
    (agent-shell-workspace-test--collapse "alpha/")
    (agent-shell-workspace-test--collapse "beta/")
    (redisplay t)
    (let ((window (agent-shell-workspace-test--sidebar-window)))
      (agent-shell-workspace-test--park-on-header "alpha/")
      (with-selected-window window
        (goto-char (window-point window))
        (agent-shell-workspace-sidebar-next)
        (set-window-point window (point)))
      (redisplay t)
      (should (equal "/tmp/beta/"
                     (agent-shell-workspace-test--project-at-window-point)))
      (with-selected-window window
        (goto-char (window-point window))
        (agent-shell-workspace-sidebar-previous)
        (set-window-point window (point)))
      (redisplay t)
      (should (equal "/tmp/alpha/"
                     (agent-shell-workspace-test--project-at-window-point))))))

(ert-deftest agent-shell-workspace-test-collapse-keeps-point-on-header ()
  "Collapsing from inside a group must leave point on that group's header.

Deliberately does not set the window's point by hand -- the point of the
test is that the command leaves it in the right place on its own, since
the rebuild that collapsing triggers erases every position the sidebar
was holding."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-sidebar-toggle)
    (redisplay t)
    ;; Collapse from an agent row, not the header, which is how it happens in
    ;; use: you are reading a session and fold the group around it.
    (agent-shell-workspace-test--park-on "Codex Agent @ alpha")
    (let ((window (agent-shell-workspace-test--sidebar-window)))
      (with-selected-window window
        (goto-char (window-point window))
        (agent-shell-workspace-sidebar-toggle-project)))
    (redisplay t)
    (should (null (agent-shell-workspace-test--agent-at-window-point)))
    (should (equal "/tmp/alpha/"
                   (agent-shell-workspace-test--project-at-window-point)))))

(ert-deftest agent-shell-workspace-test-refresh-holds-collapsed-header ()
  "The 2s auto-refresh must not drag point off a collapsed header.

With every group folded there is no agent row to fall back to, so a
rebuild that loses the header identity has nowhere sensible to land."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-sidebar-toggle)
    (redisplay t)
    (agent-shell-workspace-test--collapse "alpha/")
    (agent-shell-workspace-test--collapse "beta/")
    (agent-shell-workspace-test--park-on-header "beta/")
    (redisplay t)
    (dotimes (_ 3)
      (agent-shell-workspace-sidebar-refresh)
      (redisplay t))
    (should (equal "/tmp/beta/"
                   (agent-shell-workspace-test--project-at-window-point)))))

(ert-deftest agent-shell-workspace-test-collapsed-header-is-a-stop ()
  "Moving past a collapsed group must land on its header, not skip it.

Rendered order with alpha collapsed is: alpha header, beta header, beta's
agent.  Stepping back twice from that agent has to stop on each header in
turn -- otherwise a collapsed group cannot be reached, and so cannot be
re-expanded, with the motion keys the sidebar binds."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-sidebar-toggle)
    (redisplay t)
    (agent-shell-workspace-test--collapse "alpha/")
    (redisplay t)
    (agent-shell-workspace-test--park-on "Claude Agent @ beta")
    (let ((window (agent-shell-workspace-test--sidebar-window)))
      (cl-flet ((step-back ()
                  (with-selected-window window
                    (goto-char (window-point window))
                    (agent-shell-workspace-sidebar-previous)
                    (set-window-point window (point)))
                  (redisplay t)))
        (step-back)
        (should (null (agent-shell-workspace-test--agent-at-window-point)))
        (should (equal "/tmp/beta/"
                       (agent-shell-workspace-test--project-at-window-point)))
        (step-back)
        (should (null (agent-shell-workspace-test--agent-at-window-point)))
        (should (equal "/tmp/alpha/"
                       (agent-shell-workspace-test--project-at-window-point)))))))

(defun agent-shell-workspace-sidebar-goto-buffer-for-test (name)
  "Select the agent called NAME through the real selection path."
  (agent-shell-workspace-test--park-on name)
  (let ((window (agent-shell-workspace-test--sidebar-window)))
    (with-selected-window window
      (goto-char (window-point window))
      (agent-shell-workspace-sidebar-goto))))

(provide 'agent-shell-workspace-test)
;;; agent-shell-workspace-test.el ends here
