;;; run.el --- Test runner for agent-shell-workspace -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by test/run.sh inside a real (non-batch) Emacs.  Runs the ERT
;; suite, writes the report to the file named by AGENT_SHELL_WORKSPACE_TEST_OUT,
;; and exits with a status reflecting the result.

;;; Code:

(require 'ert)

(let ((here (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." here))
  (add-to-list 'load-path here))

(require 'agent-shell-workspace)
(require 'agent-shell-workspace-test)

(defun agent-shell-workspace-run-tests ()
  "Run the suite and report to the output file, then exit."
  (let* ((out (or (getenv "AGENT_SHELL_WORKSPACE_TEST_OUT")
                  "/tmp/agent-shell-workspace-test.out"))
         (stats nil)
         (report ""))
    ;; A wedged test in a non-batch Emacs waits forever with nothing on
    ;; stdout.  Report the hang instead of letting the caller time out blind.
    (run-with-timer
     60 nil
     (lambda ()
       (write-region
        (concat (with-current-buffer "*Messages*" (buffer-string))
                "\nTIMEOUT after 60s -- the last test named above is wedged\n")
        nil out)
       (kill-emacs 2)))
    ;; ERT reports through `message', which goes to *Messages* rather than
    ;; `standard-output' outside batch mode, so capture the buffer.
    (setq stats (ert-run-tests-batch t))
    (setq report (with-current-buffer "*Messages*" (buffer-string)))
    (let ((total (ert-stats-total stats))
          (passed (ert-stats-completed-expected stats))
          (unexpected (ert-stats-completed-unexpected stats)))
      (write-region
       (concat report
               (format "\nSUMMARY %d/%d passed, %d unexpected\n"
                       passed total unexpected))
       nil out)
      (kill-emacs (if (> unexpected 0) 1 0)))))

;;; run.el ends here
