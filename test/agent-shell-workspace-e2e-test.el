;;; agent-shell-workspace-e2e-test.el --- End-to-end tests -*- lexical-binding: t; -*-

;;; Commentary:

;; End-to-end tests for window, tab and cursor behaviour.
;;
;; These must run in a real Emacs with a real frame, NOT with --batch.
;; Batch mode never runs redisplay and never restores a window
;; configuration, so `window-point' bugs are invisible there: the very
;; class of bug these tests exist to catch.  See test/run.sh.
;;
;; Pure logic tests belong in agent-shell-workspace-unit-test.el, which
;; runs under --batch and fails fast.

;;; Code:

(require 'ert-x)
(require 'agent-shell-workspace-test-helpers)

;;; Cursor and selection

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
    (agent-shell-workspace-test--select-agent "Codex Agent @ alpha")
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
    (agent-shell-workspace-test--select-agent "Codex Agent @ alpha")
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
    (agent-shell-workspace-test--select-agent "Codex Agent @ alpha")
    (kill-buffer "Codex Agent @ alpha")
    (agent-shell-workspace-sidebar-refresh)
    (redisplay t)
    (let* ((sidebar (get-buffer agent-shell-workspace-sidebar-buffer-name))
           (selected (buffer-local-value
                      'agent-shell-workspace-sidebar--selected-buffer sidebar)))
      (should (or (null selected) (buffer-live-p selected))))))

;;; Plain sidebar

(ert-deftest agent-shell-workspace-test-sidebar-toggle-makes-no-tab ()
  "The plain sidebar toggle must not create a tab or disturb the layout."
  (agent-shell-workspace-test--with-agents
    (let ((tabs-before (length (tab-bar-tabs)))
          (buffer-before (window-buffer (selected-window))))
      (agent-shell-workspace-test--toggle-plain)
      (redisplay t)
      (should (agent-shell-workspace-test--sidebar-window))
      ;; A real side window, not a tab and not a takeover of the layout.
      (should (window-parameter (agent-shell-workspace-test--sidebar-window)
                                'window-side))
      (should (= tabs-before (length (tab-bar-tabs))))
      (should (not (agent-shell-workspace--tab-exists-p)))
      (should (eq buffer-before (window-buffer (selected-window))))
      ;; Toggling again puts it away.
      (agent-shell-workspace-test--toggle-plain)
      (redisplay t)
      (should (not (agent-shell-workspace-test--sidebar-window)))
      (should (= tabs-before (length (tab-bar-tabs)))))))

;;; Collapsed groups

(ert-deftest agent-shell-workspace-test-collapsed-groups-stay-navigable ()
  "With every group collapsed, n/p must still move between the headers.

Collapsing the last expanded group leaves the sidebar with nothing but
headers.  Navigation that only knows about agent rows has no stops left,
so the motion keys go dead and the list cannot be reached again."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
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
    (agent-shell-workspace-test--toggle-plain)
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
    (agent-shell-workspace-test--toggle-plain)
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
    (agent-shell-workspace-test--toggle-plain)
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

;;; One-shot picker

(ert-deftest agent-shell-workspace-test-pick-switches-origin-window ()
  "A one-shot pick must switch the origin window and put the sidebar away.

No tab may be created: the picker is for jumping to an agent from
wherever you are, not for entering the workspace."
  (agent-shell-workspace-test--with-agents
    (let ((origin (selected-window))
          (tabs-before (length (tab-bar-tabs))))
      (agent-shell-workspace-pick)
      (redisplay t)
      ;; The picker takes focus so the list can be navigated immediately.
      (should (eq (selected-window)
                  (agent-shell-workspace-test--sidebar-window)))
      (agent-shell-workspace-test--select-agent "Codex Agent @ alpha")
      (redisplay t)
      (should (not (agent-shell-workspace-test--sidebar-window)))
      (should (eq (selected-window) origin))
      (should (eq (window-buffer origin) (get-buffer "Codex Agent @ alpha")))
      (should (= tabs-before (length (tab-bar-tabs)))))))

(ert-deftest agent-shell-workspace-test-pick-quit-cancels ()
  "Quitting a pick must close the sidebar, refocus the origin untouched,
and leave no pending pick behind to redirect a later selection."
  (agent-shell-workspace-test--with-agents
    (let ((origin (selected-window))
          (before (window-buffer (selected-window))))
      (agent-shell-workspace-pick)
      (redisplay t)
      (with-selected-window (agent-shell-workspace-test--sidebar-window)
        (agent-shell-workspace-sidebar-quit))
      (redisplay t)
      (should (not (agent-shell-workspace-test--sidebar-window)))
      (should (eq (selected-window) origin))
      (should (eq (window-buffer origin) before))
      (should (null agent-shell-workspace-sidebar--pick-window)))))

(ert-deftest agent-shell-workspace-test-abandoned-pick-does-not-redirect ()
  "A pick abandoned without `q' must not hijack a later plain-sidebar RET.

The pick window is cleared on every non-pick open, so reopening the
sidebar through the toggle behaves normally: RET shows the agent in the
main area and keeps the sidebar up."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-pick)
    (redisplay t)
    ;; Abandon by closing through the toggle, then reopen it plainly.
    (agent-shell-workspace-test--toggle-plain)
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (should (null agent-shell-workspace-sidebar--pick-window))
    (agent-shell-workspace-test--select-agent "Claude Agent @ beta")
    (redisplay t)
    (should (agent-shell-workspace-test--sidebar-window))))

(ert-deftest agent-shell-workspace-test-sidebar-toggle-is-one-shot-by-default ()
  "The default toggle opens as a pick: cursor in the sidebar, selection
switches the origin window and puts the sidebar away.  No tab either way."
  (agent-shell-workspace-test--with-agents
    (let ((origin (selected-window))
          (tabs-before (length (tab-bar-tabs))))
      (agent-shell-workspace-sidebar-toggle)
      (redisplay t)
      (should (eq (selected-window)
                  (agent-shell-workspace-test--sidebar-window)))
      (agent-shell-workspace-test--select-agent "Codex Agent @ alpha")
      (redisplay t)
      (should (not (agent-shell-workspace-test--sidebar-window)))
      (should (eq (selected-window) origin))
      (should (eq (window-buffer origin) (get-buffer "Codex Agent @ alpha")))
      (should (= tabs-before (length (tab-bar-tabs)))))))

(ert-deftest agent-shell-workspace-test-one-shot-toggle-away-refocuses ()
  "Toggling the sidebar away without picking must return the cursor to
the window the pick came from, leaving its buffer untouched."
  (agent-shell-workspace-test--with-agents
    (let ((origin (selected-window))
          (before (window-buffer (selected-window))))
      (agent-shell-workspace-sidebar-toggle)
      (redisplay t)
      (agent-shell-workspace-sidebar-toggle)
      (redisplay t)
      (should (not (agent-shell-workspace-test--sidebar-window)))
      (should (eq (selected-window) origin))
      (should (eq (window-buffer origin) before))
      (should (null agent-shell-workspace-sidebar--pick-window)))))

;;; Working spinner

(ert-deftest agent-shell-workspace-test-working-spinner-advances ()
  "A spin tick redraws a working agent's row with the next frame."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--make-live-agent
     "Claude Agent @ busy" "/tmp/busy/"
     (cons :tool-calls (list (cons 1 (list :status "in_progress")))))
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (let ((sidebar (get-buffer agent-shell-workspace-sidebar-buffer-name)))
      (cl-flet ((rendered ()
                  (with-current-buffer sidebar
                    (buffer-substring-no-properties (point-min) (point-max)))))
        (should (buffer-local-value
                 'agent-shell-workspace-sidebar--animating sidebar))
        (should (string-match-p "◐" (rendered)))
        (agent-shell-workspace-sidebar--spin)
        (redisplay t)
        (should (string-match-p "◓" (rendered)))
        (should-not (string-match-p "◐" (rendered)))))))

(ert-deftest agent-shell-workspace-test-spinner-idles-without-working-agent ()
  "With no working agent the spin tick must not advance or re-render."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (let ((sidebar (get-buffer agent-shell-workspace-sidebar-buffer-name))
          (frame-before agent-shell-workspace--working-frame))
      (should-not (buffer-local-value
                   'agent-shell-workspace-sidebar--animating sidebar))
      (agent-shell-workspace-sidebar--spin)
      (should (= frame-before agent-shell-workspace--working-frame)))))

;;; Summary lines

(ert-deftest agent-shell-workspace-test-working-agent-shows-activity ()
  "A working agent's summary line is its latest tool-call title, not the
session title."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--make-live-agent
     "Claude Agent @ busy" "/tmp/busy/"
     (cons :tool-calls
           (list (cons 1 (list :status "in_progress"
                               :title "Reading foo.el")))))
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (let ((rendered (with-current-buffer agent-shell-workspace-sidebar-buffer-name
                      (buffer-substring-no-properties (point-min) (point-max)))))
      (should (string-match-p "Reading foo.el" rendered))
      (should-not (string-match-p "live session" rendered)))))

(ert-deftest agent-shell-workspace-test-long-summary-wraps-to-two-lines ()
  "A long summary wraps onto a second indented line instead of truncating
straight away; the wrapped lines still resolve to their agent."
  (agent-shell-workspace-test--with-fixture
    (cl-letf (((symbol-function 'agent-shell--config-icon) (lambda (&rest _) "")))
      (tab-bar-mode 1)
      (let ((agent (agent-shell-workspace-test--make-agent
                    "Claude Agent @ wordy" "/tmp/wordy/"
                    "refactor the sidebar renderer and update the tests")))
        (agent-shell-workspace-test--toggle-plain)
        (redisplay t)
        (with-current-buffer agent-shell-workspace-sidebar-buffer-name
          (let ((entry-lines 0))
            (save-excursion
              (goto-char (point-min))
              (while (not (eobp))
                (when (eq agent (agent-shell-workspace-sidebar--buffer-at-point))
                  (setq entry-lines (1+ entry-lines)))
                (forward-line 1)))
            ;; The agent's row plus two wrapped summary lines.
            (should (= 3 entry-lines))
            (should (string-match-p "refactor the"
                                    (buffer-substring-no-properties
                                     (point-min) (point-max))))))))))

;;; Tiling

(ert-deftest agent-shell-workspace-test-tiling-grid ()
  "Adding agents tiles them into a grid; removing shrinks it back down.

One mark alone is not a tile; two are.  Removing down to a single agent
un-tiles entirely, as does the explicit `t' un-tile command."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (let ((a (get-buffer "Claude Agent @ alpha"))
          (b (get-buffer "Codex Agent @ alpha"))
          (c (get-buffer "Claude Agent @ beta"))
          (sidebar (get-buffer agent-shell-workspace-sidebar-buffer-name)))
      (cl-flet ((shown () (mapcar #'window-buffer
                                  (agent-shell-workspace-test--main-windows))))
        (agent-shell-workspace-test--run-on
         "Claude Agent @ alpha" #'agent-shell-workspace-tile-add)
        (redisplay t)
        (should (= 1 (length (shown))))
        (agent-shell-workspace-test--run-on
         "Codex Agent @ alpha" #'agent-shell-workspace-tile-add)
        (redisplay t)
        (should (seq-set-equal-p (list a b) (shown)))
        (agent-shell-workspace-test--run-on
         "Claude Agent @ beta" #'agent-shell-workspace-tile-add)
        (redisplay t)
        (should (seq-set-equal-p (list a b c) (shown)))
        (agent-shell-workspace-test--run-on
         "Codex Agent @ alpha" #'agent-shell-workspace-tile-remove)
        (redisplay t)
        (should (seq-set-equal-p (list a c) (shown)))
        ;; Down to one: fully un-tiled.
        (agent-shell-workspace-test--run-on
         "Claude Agent @ beta" #'agent-shell-workspace-tile-remove)
        (redisplay t)
        (should (= 1 (length (shown))))
        (should (null (buffer-local-value
                       'agent-shell-workspace--tiled-buffers sidebar)))
        ;; Tile again and leave through the explicit un-tile command.
        (agent-shell-workspace-test--run-on
         "Claude Agent @ alpha" #'agent-shell-workspace-tile-add)
        (agent-shell-workspace-test--run-on
         "Codex Agent @ alpha" #'agent-shell-workspace-tile-add)
        (redisplay t)
        (should (seq-set-equal-p (list a b) (shown)))
        (agent-shell-workspace-test--run-on
         "Claude Agent @ alpha" #'agent-shell-workspace-tile-toggle)
        (redisplay t)
        (should (= 1 (length (shown))))
        (should (null (buffer-local-value
                       'agent-shell-workspace--tiled-buffers sidebar)))))))

;;; Quick switch

(ert-deftest agent-shell-workspace-test-quick-switch-peeks-without-focus ()
  "With quick-switch on, resting point on an agent shows it in the main
area without taking focus from the sidebar."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    ;; Give the main area a known agent first, then come back.
    (agent-shell-workspace-test--select-agent "Claude Agent @ beta")
    (redisplay t)
    (let ((window (agent-shell-workspace-test--sidebar-window)))
      (select-window window)
      (agent-shell-workspace-sidebar-toggle-quick-switch)
      (agent-shell-workspace-test--park-on "Codex Agent @ alpha")
      ;; Any command triggers the peek; the hook does the rest.  The pty
      ;; that test/run.sh allocates can leave a stray event queued, and
      ;; `ert-simulate-command' asserts the queue is empty.
      (setq unread-command-events nil)
      (with-selected-window window
        (ert-simulate-command '(ignore)))
      (redisplay t)
      (should (eq (selected-window) window))
      (should (eq (get-buffer "Codex Agent @ alpha")
                  (window-buffer (agent-shell-workspace-test--main-window)))))))

(ert-deftest agent-shell-workspace-test-click-selects-agent ()
  "A mouse click on a row selects that agent, same as RET."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (agent-shell-workspace-test--park-on "Claude Agent @ beta")
    (let* ((window (agent-shell-workspace-test--sidebar-window))
           (posn (posn-at-point (window-point window) window)))
      (agent-shell-workspace-sidebar-click (list 'mouse-1 posn))
      (redisplay t)
      (should (eq (get-buffer "Claude Agent @ beta")
                  (window-buffer (agent-shell-workspace-test--main-window)))))))

;;; Agent management

(ert-deftest agent-shell-workspace-test-kill-sends-eof ()
  "Killing an agent with a live process sends it EOF in its own buffer."
  (agent-shell-workspace-test--with-agents
    (let ((live (agent-shell-workspace-test--make-live-agent
                 "Claude Agent @ live" "/tmp/live/"))
          (calls nil))
      ;; The real `shell-maker-busy' wants a genuine shell-maker-config
      ;; struct, which the fakes do not carry, and rendering a live fake
      ;; reaches it through the status check.
      (cl-letf (((symbol-function 'shell-maker-busy) (lambda (&rest _) nil))
                ((symbol-function 'comint-send-eof)
                 (lambda () (push (current-buffer) calls)))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (agent-shell-workspace-test--toggle-plain)
        (redisplay t)
        (agent-shell-workspace-test--run-on
         "Claude Agent @ live" #'agent-shell-workspace-sidebar-kill))
      (should (equal (list live) calls)))))

(ert-deftest agent-shell-workspace-test-rename-preserves-prefix ()
  "Renaming only changes the post-@ portion of the buffer name."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "renamed")))
      (agent-shell-workspace-test--run-on
       "Codex Agent @ alpha" #'agent-shell-workspace-sidebar-rename))
    (should (get-buffer "Codex Agent @ renamed"))
    (should (null (get-buffer "Codex Agent @ alpha")))))

(ert-deftest agent-shell-workspace-test-delete-killed-buffers ()
  "The plain fixtures have no process, so every one of them reads as
killed and `d' sweeps them all away."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (with-selected-window (agent-shell-workspace-test--sidebar-window)
        (agent-shell-workspace-sidebar-delete-killed)))
    (redisplay t)
    (should (null (seq-filter #'buffer-live-p
                              agent-shell-workspace-test--buffers)))))

(ert-deftest agent-shell-workspace-test-management-commands-delegate ()
  "Set-mode, cycle-mode and interrupt run inside the agent at point, and
restart falls back to a fresh `agent-shell' when the config is unknown."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-test--toggle-plain)
    (redisplay t)
    (let ((target (get-buffer "Codex Agent @ alpha"))
          (calls nil))
      (cl-letf (((symbol-function 'agent-shell-set-session-mode)
                 (lambda (&rest _) (push (cons 'set (current-buffer)) calls)))
                ((symbol-function 'agent-shell-cycle-session-mode)
                 (lambda (&rest _) (push (cons 'cycle (current-buffer)) calls)))
                ((symbol-function 'agent-shell-interrupt)
                 (lambda (&rest _) (push (cons 'interrupt (current-buffer)) calls)))
                ((symbol-function 'agent-shell)
                 (lambda (&rest args) (push (cons 'new args) calls)))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (agent-shell-workspace-test--run-on
         "Codex Agent @ alpha" #'agent-shell-workspace-sidebar-set-mode)
        (agent-shell-workspace-test--run-on
         "Codex Agent @ alpha" #'agent-shell-workspace-sidebar-cycle-mode)
        (agent-shell-workspace-test--run-on
         "Codex Agent @ alpha" #'agent-shell-workspace-sidebar-interrupt)
        (should (equal (list (cons 'set target)
                             (cons 'cycle target)
                             (cons 'interrupt target))
                       (reverse calls)))
        (let ((agent-shell-agent-configs '()))
          (agent-shell-workspace-test--run-on
           "Codex Agent @ alpha" #'agent-shell-workspace-sidebar-restart))
        (should (equal (cons 'new '(t)) (car calls)))
        (should-not (buffer-live-p target))))))

;;; Workspace tab and isolation

(ert-deftest agent-shell-workspace-test-toggle-returns-to-previous-tab ()
  (agent-shell-workspace-test--with-agents
    (let ((home (alist-get 'name (tab-bar--current-tab))))
      (agent-shell-workspace-toggle)
      (redisplay t)
      (should (agent-shell-workspace--in-agents-tab-p))
      (agent-shell-workspace-toggle)
      (redisplay t)
      (should-not (agent-shell-workspace--in-agents-tab-p))
      (should (equal home (alist-get 'name (tab-bar--current-tab)))))))

(ert-deftest agent-shell-workspace-test-isolation-redirects-non-agents ()
  "Displaying a non-agent buffer from the Agents tab lands in the
previous tab, through both the advice path and the display-buffer path."
  (agent-shell-workspace-test--with-agents
    (agent-shell-workspace-toggle)
    (redisplay t)
    (should (agent-shell-workspace--in-agents-tab-p))
    (switch-to-buffer "*scratch*")
    (redisplay t)
    (should-not (agent-shell-workspace--in-agents-tab-p))
    (should (eq (window-buffer) (get-buffer "*scratch*")))
    ;; Same again through display-buffer, from inside the tab.
    (agent-shell-workspace-toggle)
    (redisplay t)
    (should (agent-shell-workspace--in-agents-tab-p))
    (display-buffer "*scratch*")
    (redisplay t)
    (should-not (agent-shell-workspace--in-agents-tab-p))))

;;; Rendering on a real frame

(ert-deftest agent-shell-workspace-test-blend-color-mixes-on-real-frame ()
  "Blending needs `color-values', which only resolves on a real frame;
the batch suite can only cover the fallback path."
  (should (equal "#4c0000"
                 (agent-shell-workspace--blend-color "#ff0000" "#000000" 3))))

(provide 'agent-shell-workspace-e2e-test)
;;; agent-shell-workspace-e2e-test.el ends here
