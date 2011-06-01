;; C-c C-j (generate new clause)
;; C-c C-y (copy arguments from last clause)
;; M-h (mark function)
;; C-c M-h (mark clause)
;; C-c C-c / C-u C-c C-c (comment/uncomment region)
;; M-a/M-e (goto begining/end of a function)

(setq erlang-root-dir "/opt/erl/lib/erlang"
      exec-path (cons "/opt/bin/" exec-path))

(require 'erlang-start)
(require 'erlang-flymake)

(add-to-list 'auto-mode-alist '("\\.erl?$" . erlang-mode))
(add-to-list 'auto-mode-alist '("\\.hrl?$" . erlang-mode))

(defun erl-init-file ()
  "insert -module and -export directives"
  (interactive)
  (let ((bufname (buffer-name)))
    (string-match "\\(.*\\)\\.erl" bufname)
    (insert "-module(" (match-string 1 bufname) ").\n"))
  (insert "-export([]).\n")
  (insert "\n")
  (end-of-buffer))

(add-hook 'erlang-mode-hook (lambda () (interactive)
                              (when (eobp)
                                (erl-init-file))))

(add-hook 'erlang-mode-hook (lambda () (interactive)
                              (setq inferior-erlang-machine-options
                                    '("-sname" "emacs"))))

