;;; agent-shell-workspace-unit-test.el --- Batch-safe unit tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Logic tests that need no frame, no redisplay and no window
;; management, so they run under `emacs --batch' where startup is cheap
;; and nothing can wedge.  Anything that touches windows, tabs or
;; window-point belongs in agent-shell-workspace-e2e-test.el instead.

;;; Code:

(require 'agent-shell-workspace-test-helpers)

;;; Status transition tracking

(ert-deftest agent-shell-workspace-unit-track-status-lifecycle ()
  "Working to ready reads as finished until acknowledged or working again."
  (agent-shell-workspace-test--with-fixture
    (let ((buffer (agent-shell-workspace-test--make-agent
                   "Claude Agent @ track" "/tmp/track/" "t")))
      (cl-flet ((track (raw)
                  (agent-shell-workspace--track-status buffer raw)))
        (should (equal "working" (track "working")))
        (should (equal "finished" (track "ready")))
        ;; Sticky across further ready polls until acknowledged.
        (should (equal "finished" (track "ready")))
        (agent-shell-workspace--clear-finished buffer)
        (should (equal "ready" (track "ready")))
        ;; Starting to work again clears a finished flag on its own.
        (should (equal "working" (track "working")))
        (should (equal "finished" (track "ready")))
        (should (equal "working" (track "working")))
        ;; Waiting to ready is a finish too: the agent was blocked on the
        ;; user, produced its answer, and stopped.
        (should (equal "waiting" (track "waiting")))
        (should (equal "finished" (track "ready")))))))

;;; Status detection

(ert-deftest agent-shell-workspace-unit-status-killed-without-process ()
  (agent-shell-workspace-test--with-fixture
    (let ((buffer (agent-shell-workspace-test--make-agent
                   "Claude Agent @ dead" "/tmp/dead/" "t")))
      (should (equal "killed" (agent-shell-workspace--buffer-status buffer))))))

(ert-deftest agent-shell-workspace-unit-status-killed-when-acp-gone ()
  "A live comint process is not enough once the ACP client is gone."
  (agent-shell-workspace-test--with-fixture
    (let ((buffer (agent-shell-workspace-test--make-live-agent
                   "Claude Agent @ headless" "/tmp/headless/"
                   (cons :client (list (cons :process nil))))))
      (should (equal "killed" (agent-shell-workspace--buffer-status buffer))))))

(ert-deftest agent-shell-workspace-unit-status-ready ()
  (agent-shell-workspace-test--with-fixture
    (cl-letf (((symbol-function 'shell-maker-busy) (lambda (&rest _) nil)))
      (let ((buffer (agent-shell-workspace-test--make-live-agent
                     "Claude Agent @ ready" "/tmp/ready/"
                     (cons :session (list (cons :id "sess"))))))
        (should (equal "ready" (agent-shell-workspace--buffer-status buffer)))))))

(ert-deftest agent-shell-workspace-unit-status-waiting-on-permission ()
  "A pending permission request reads as waiting; nil status counts as pending."
  (agent-shell-workspace-test--with-fixture
    (pcase-dolist (`(,name ,data)
                   (list (list "Claude Agent @ wait-pending"
                               (list :permission-request-id "p" :status "pending"))
                         (list "Claude Agent @ wait-nil"
                               (list :permission-request-id "p"))))
      (let ((buffer (agent-shell-workspace-test--make-live-agent
                     name "/tmp/wait/"
                     (cons :tool-calls (list (cons 1 data))))))
        (should (equal "waiting" (agent-shell-workspace--buffer-status buffer)))))))

(ert-deftest agent-shell-workspace-unit-status-working ()
  "Tool calls without a permission request, or a busy shell-maker, both
read as working."
  (agent-shell-workspace-test--with-fixture
    (let ((tool-calls (agent-shell-workspace-test--make-live-agent
                       "Claude Agent @ tools" "/tmp/tools/"
                       (cons :tool-calls
                             (list (cons 1 (list :status "in_progress")))))))
      (should (equal "working" (agent-shell-workspace--buffer-status tool-calls))))
    (cl-letf (((symbol-function 'shell-maker-busy) (lambda (&rest _) t)))
      (let ((busy (agent-shell-workspace-test--make-live-agent
                   "Claude Agent @ busy" "/tmp/busy/")))
        (should (equal "working" (agent-shell-workspace--buffer-status busy)))))))

(ert-deftest agent-shell-workspace-unit-status-initializing ()
  "Alive, but no session yet and not initialized."
  (agent-shell-workspace-test--with-fixture
    (cl-letf (((symbol-function 'shell-maker-busy) (lambda (&rest _) nil)))
      (let ((buffer (agent-shell-workspace-test--make-live-agent
                     "Claude Agent @ init" "/tmp/init/"
                     (cons :initialized nil))))
        (should (equal "initializing"
                       (agent-shell-workspace--buffer-status buffer)))))))

(ert-deftest agent-shell-workspace-unit-status-faces-and-icons ()
  ;; The working icon is animated, so pin it to its first frame here.
  (let ((agent-shell-workspace--working-frame 0))
    (pcase-dolist (`(,status ,face ,icon)
                   '(("ready" success "●")
                     ("finished" agent-shell-workspace-finished "✔")
                     ("working" warning "◐")
                     ("waiting" agent-shell-workspace-waiting "◉")
                     ("initializing" font-lock-comment-face "○")
                     ("killed" error "✕")
                     ("no-such-status" default "?")))
      (should (eq face (agent-shell-workspace--status-face status)))
      (should (equal icon (agent-shell-workspace--status-icon status))))))

(ert-deftest agent-shell-workspace-unit-working-icon-cycles ()
  "The working icon steps through the spinner frames and wraps around.
Other statuses ignore the frame counter."
  (let ((agent-shell-workspace--working-frame 0))
    (let ((frames (mapcar (lambda (frame)
                            (setq agent-shell-workspace--working-frame frame)
                            (agent-shell-workspace--status-icon "working"))
                          '(0 1 2 3 4))))
      (should (equal '("◐" "◓" "◑" "◒" "◐") frames)))
    (should (equal "●" (agent-shell-workspace--status-icon "ready")))))

;;; Names, projects and grouping

(ert-deftest agent-shell-workspace-unit-name-parsing ()
  (agent-shell-workspace-test--with-fixture
    (let ((named (agent-shell-workspace-test--make-agent
                  "Claude Agent @ alpha" "/tmp/alpha/" "t"))
          (odd (agent-shell-workspace-test--make-agent
                "just-a-buffer" "/tmp/alpha/" "t")))
      (should (equal "Claude" (agent-shell-workspace--agent-kind named)))
      (should (equal "alpha" (agent-shell-workspace--short-name named)))
      (should (equal "-" (agent-shell-workspace--agent-kind odd)))
      (should (equal "just-a-buffer" (agent-shell-workspace--short-name odd))))))

(ert-deftest agent-shell-workspace-unit-agent-type-fallback ()
  (agent-shell-workspace-test--with-fixture
    (pcase-dolist (`(,name ,expected)
                   '(("Claude Agent @ a1" "C")
                     ("OpenCode Agent @ a2" "O")
                     ("Gemini Agent @ a3" "G")
                     ("nameless" "?")))
      (should (equal expected
                     (agent-shell-workspace--agent-type-fallback
                      (agent-shell-workspace-test--make-agent
                       name "/tmp/a/" "t")))))))

(ert-deftest agent-shell-workspace-unit-row-label-falls-back-to-kind ()
  "An unrenamed buffer would just repeat the group header; show the kind."
  (agent-shell-workspace-test--with-fixture
    (let ((plain (agent-shell-workspace-test--make-agent
                  "Claude Agent @ alpha" "/tmp/alpha/" "t"))
          (renamed (agent-shell-workspace-test--make-agent
                    "Claude Agent @ my-task" "/tmp/alpha/" "t")))
      (should (equal "Claude" (agent-shell-workspace--row-label plain)))
      (should (equal "my-task" (agent-shell-workspace--row-label renamed))))))

(ert-deftest agent-shell-workspace-unit-project-key-and-label ()
  (agent-shell-workspace-test--with-fixture
    (let ((buffer (agent-shell-workspace-test--make-agent
                   "Claude Agent @ alpha" "/tmp/alpha" "t")))
      ;; Normalized to directory form however the fixture spelled it.
      (should (equal "/tmp/alpha/"
                     (agent-shell-workspace--project-key buffer)))))
  (should (equal "alpha/" (agent-shell-workspace--project-label "/tmp/alpha/")))
  (should (equal "(no project)/" (agent-shell-workspace--project-label ""))))

(ert-deftest agent-shell-workspace-unit-group-buffers-sorts-and-splits ()
  "Grouped by directory, ordered by label then key, members by row label.
Two projects sharing a basename must stay separate groups."
  (agent-shell-workspace-test--with-fixture
    (let* ((codex (agent-shell-workspace-test--make-agent
                   "Codex Agent @ proj" "/tmp/x/proj/" "t"))
           (claude (agent-shell-workspace-test--make-agent
                    "Claude Agent @ proj" "/tmp/x/proj/" "t"))
           (other-proj (agent-shell-workspace-test--make-agent
                        "OpenCode Agent @ proj" "/tmp/y/proj/" "t"))
           (aardvark (agent-shell-workspace-test--make-agent
                      "Claude Agent @ aardvark" "/tmp/z/aardvark/" "t"))
           (groups (agent-shell-workspace--group-buffers
                    (list codex claude other-proj aardvark))))
      (should (equal '("aardvark/" "proj/" "proj/") (mapcar #'cadr groups)))
      (should (equal '("/tmp/z/aardvark/" "/tmp/x/proj/" "/tmp/y/proj/")
                     (mapcar #'car groups)))
      ;; Claude sorts before Codex within the shared project.
      (should (equal (list claude codex) (cddr (nth 1 groups))))
      (should (equal (list other-proj) (cddr (nth 2 groups)))))))

(ert-deftest agent-shell-workspace-unit-session-title-trimming ()
  "The seeded title is a raw prompt: keep the first non-blank line only."
  (agent-shell-workspace-test--with-fixture
    (let ((multiline (agent-shell-workspace-test--make-agent
                      "Claude Agent @ multi" "/tmp/multi/"
                      "\n\n  fix the tests  \nsecond line"))
          (blank (agent-shell-workspace-test--make-agent
                  "Claude Agent @ blank" "/tmp/blank/" "   \n \n"))
          (absent (agent-shell-workspace-test--make-agent
                   "Claude Agent @ none" "/tmp/none/" nil)))
      (should (equal "fix the tests"
                     (agent-shell-workspace--session-title multiline)))
      (should (null (agent-shell-workspace--session-title blank)))
      (should (null (agent-shell-workspace--session-title absent))))))

;;; Config resolution

(ert-deftest agent-shell-workspace-unit-config-resolution ()
  "Maker functions realize, alists pass through, lookup matches the prefix."
  (agent-shell-workspace-test--with-fixture
    (let ((agent-shell-agent-configs
           (list (lambda () '((:buffer-name . "Fn")))
                 '((:buffer-name . "Plain")))))
      (should (equal '(((:buffer-name . "Fn")) ((:buffer-name . "Plain")))
                     (agent-shell-workspace--resolved-agent-configs)))
      (let ((buffer (agent-shell-workspace-test--make-agent
                     "Plain Agent @ x" "/tmp/x/" "t"))
            (outsider (get-buffer-create "not-an-agent")))
        (unwind-protect
            (progn
              (should (equal '((:buffer-name . "Plain"))
                             (agent-shell-workspace--buffer-config buffer)))
              (should (null (agent-shell-workspace--buffer-config outsider))))
          (kill-buffer outsider))))))

;;; Workspace membership

(ert-deftest agent-shell-workspace-unit-agent-buffer-classification ()
  (agent-shell-workspace-test--with-fixture
    (let ((agent (agent-shell-workspace-test--make-agent
                  "Claude Agent @ alpha" "/tmp/alpha/" "t"))
          (log (get-buffer-create "*agent-shell claude traffic*"))
          (sidebar (get-buffer-create "*fake sidebar*"))
          (agent-diff (get-buffer-create "*fake agent diff*"))
          (plain-diff (get-buffer-create "*fake plain diff*"))
          (plain (get-buffer-create "*fake plain*")))
      (unwind-protect
          (progn
            (with-current-buffer sidebar
              (setq major-mode 'agent-shell-workspace-sidebar-mode))
            (with-current-buffer agent-diff
              (setq major-mode 'diff-mode)
              (setq-local agent-shell-on-exit #'ignore))
            (with-current-buffer plain-diff
              (setq major-mode 'diff-mode))
            (should (agent-shell-workspace--agent-buffer-p agent))
            (should (agent-shell-workspace--agent-buffer-p log))
            (should (agent-shell-workspace--agent-buffer-p sidebar))
            (should (agent-shell-workspace--agent-buffer-p agent-diff))
            (should-not (agent-shell-workspace--agent-buffer-p plain-diff))
            (should-not (agent-shell-workspace--agent-buffer-p plain))
            (should-not (agent-shell-workspace--agent-buffer-p nil)))
        (dolist (buffer (list log sidebar agent-diff plain-diff plain))
          (kill-buffer buffer))))))

;;; Rendering helpers

(ert-deftest agent-shell-workspace-unit-color-helpers ()
  (should (equal "red" (agent-shell-workspace--extract-color "red")))
  ;; A tty frame reports "unspecified-bg", which `color-values' cannot
  ;; parse; the blend must fall back to the raw foreground rather than
  ;; take the whole render down.
  (should (equal "#ff0000"
                 (agent-shell-workspace--blend-color "#ff0000" "unspecified-bg")))
  (should (equal "#ff0000"
                 (agent-shell-workspace--blend-color "#ff0000" nil))))

(ert-deftest agent-shell-workspace-unit-name-box-truncates-and-pads ()
  (should (equal " abc… "
                 (substring-no-properties
                  (agent-shell-workspace--make-name-box "abcdefgh" "red" 4))))
  (should (equal " ab   "
                 (substring-no-properties
                  (agent-shell-workspace--make-name-box "ab" "red" 4))))
  (should (equal " full "
                 (substring-no-properties
                  (agent-shell-workspace--make-name-box "full" "red" nil)))))

;;; Thin command wrappers

(ert-deftest agent-shell-workspace-unit-new-delegates-to-agent-shell ()
  (let ((calls nil))
    (cl-letf (((symbol-function 'agent-shell)
               (lambda (&rest args) (push args calls))))
      (agent-shell-workspace-sidebar-new))
    (should (equal '((t)) calls))))

(provide 'agent-shell-workspace-unit-test)
;;; agent-shell-workspace-unit-test.el ends here
