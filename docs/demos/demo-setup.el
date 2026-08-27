;;; demo-setup.el --- Fake agents for the README demo -*- lexical-binding: t; -*-

;;; Commentary:

;; Stands up a frame full of fake agent-shell buffers so `sidebar.tape'
;; records the same demo every time.  Nothing here talks to a real agent:
;; each fake is a buffer in `agent-shell-mode' with a state alist and a
;; `sleep' process standing in for both the comint and ACP processes,
;; which is all the status logic inspects.  See test-helpers.el for the
;; same trick used by the suite.

;;; Code:

(require 'agent-shell-workspace)

(load-theme 'modus-vivendi t)
(setq inhibit-startup-screen t
      ring-bell-function #'ignore)
(menu-bar-mode -1)
(blink-cursor-mode -1)
(tab-bar-mode 1)

;; Rendering a row asks agent-shell for the agent's icon, which on a cache
;; miss downloads a PNG -- a demo must not depend on the network.
(defun agent-shell--config-icon (&rest _) "")

;; Status detection asks shell-maker whether the buffer is busy, which reads
;; `shell-maker--config' as a struct.  The fakes below carry a plain plist,
;; so answer for them instead of letting the accessor signal mid-render.
(defun shell-maker-busy (&rest _) nil)

(defun demo--transcript (lines)
  "Insert LINES as a plausible agent transcript in the current buffer."
  (let ((inhibit-read-only t))
    (dolist (line lines)
      (insert line "\n"))))

(defun demo--agent (name directory state transcript)
  "Create fake agent NAME in DIRECTORY with STATE alist and TRANSCRIPT."
  (let ((buffer (get-buffer-create name)))
    ;; `make-process' below inherits `default-directory' and refuses to start
    ;; from one that does not exist.
    (make-directory directory t)
    (with-current-buffer buffer
      (setq major-mode 'agent-shell-mode)
      (setq-local shell-maker--config (list :name "demo"))
      (setq-local default-directory directory)
      (demo--transcript transcript)
      (goto-char (point-max))
      ;; A keystroke the tape sends before focus reaches the sidebar must not
      ;; end up editing the transcript.
      (setq buffer-read-only t)
      (let ((process (make-process :name (concat "demo " name)
                                   :buffer buffer
                                   :command '("sleep" "600")
                                   :noquery t)))
        (setq-local agent-shell--state
                    (append state
                            (list (cons :client (list (cons :process process)))
                                  (cons :initialized t))))))
    buffer))

(defun demo--session (id title)
  "Return a :session entry with ID and TITLE."
  (cons :session (list (cons :id id) (cons :title title))))

(defun demo--tool-call (title &optional pending)
  "Return a :tool-calls entry showing TITLE, awaiting permission when PENDING."
  (cons :tool-calls
        (list (cons "call-1"
                    (append (list (cons :title title))
                            (when pending
                              (list (cons :permission-request-id "req-1")
                                    (cons :status "pending"))))))))

(demo--agent
 "Claude Agent @ agent-shell-workspace" "/tmp/agent-shell-workspace/"
 (list (demo--session "s1" "Wire the spinner into the sidebar")
       (demo--tool-call "Reading agent-shell-workspace.el"))
 '("> wire the working spinner into the sidebar rows"
   ""
   "I'll start by reading the render path and the status helpers."
   ""
   "  Reading agent-shell-workspace.el"
   "  Reading test/agent-shell-workspace-unit-test.el"
   ""
   "The row is built in `agent-shell-workspace-sidebar--render', which"
   "already knows the status, so the spinner frame can hang off the same"
   "`pcase' as the static icons."
   ""
   "  Editing agent-shell-workspace.el"))

(demo--agent
 "Codex Agent @ agent-shell-workspace" "/tmp/agent-shell-workspace/"
 (list (demo--session "s2" "Split the suite into unit and e2e phases")
       (demo--tool-call "Running test/run.sh" t))
 '("> split the suite into unit and e2e phases"
   ""
   "The window-point tests need a real frame, so they cannot share a"
   "batch runner with the pure-logic ones. Running the split suite now."
   ""
   "  Running test/run.sh"
   ""
   "  Allow this command? (y/n)"))

(demo--agent
 "Claude Agent @ dotfiles" "/tmp/dotfiles/"
 (list (demo--session "s3" "Pin the Emacs overlay to the 30.2 release"))
 '("> pin the emacs overlay to the 30.2 release"
   ""
   "Done. flake.lock now pins emacs-overlay to the 30.2 tag, and"
   "`nix flake check' passes against it."
   ""
   "  emacs 30.2 (was 30.1)"))

(demo--agent
 "Claude Agent @ infra" "/tmp/infra/"
 (list (demo--session "s4" "Add a health check to the deploy workflow"))
 '("> add a health check to the deploy workflow"
   ""
   "Added a post-deploy probe that polls /healthz for 60s and rolls"
   "back on a non-200. The workflow is green."))

;; Start on the agent whose row the demo talks about first.
(with-current-buffer (get-buffer-create agent-shell-workspace-sidebar-buffer-name)
  (setq-local agent-shell-workspace-sidebar--selected-buffer
              (get-buffer "Claude Agent @ agent-shell-workspace")))

;; Swapping or splitting a window under ttyd leaves the shorter buffer's
;; screen lines behind, which the recording would capture as garbage text.
;; A real terminal does not need this.
(dolist (command '(agent-shell-workspace-sidebar-goto
                   agent-shell-workspace-sidebar-toggle-project
                   agent-shell-workspace-tile-add
                   agent-shell-workspace-tile-remove
                   agent-shell-workspace-tile-toggle))
  (advice-add command :after (lambda (&rest _) (redraw-display))))

(agent-shell-workspace-toggle)

;; The workspace leaves focus in the main area; the demo drives the sidebar.
(when-let* ((window (get-buffer-window agent-shell-workspace-sidebar-buffer-name)))
  (select-window window))

(provide 'demo-setup)
;;; demo-setup.el ends here
