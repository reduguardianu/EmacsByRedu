(global-hl-line-mode t) ; turn it on for all modes by default
(set-face-background 'hl-line "gray15")

(setq-default indent-tabs-mode nil)
(setq-default tab-width 4)


(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(prefer-coding-system 'utf-8)


(require 'whitespace)
(setq whitespace-style '(tabs
;;                         lines-tail
                         trailing))
(global-whitespace-mode t)

(show-paren-mode t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(transient-mark-mode t)
(font-lock-mode t)
(scroll-bar-mode -1)
(setq inhibit-startup-message t)
(setq echo-keystrokes 0.1)
(global-font-lock-mode 1)
(defalias 'yes-or-no-p 'y-or-n-p)
(setq confirm-kill-emacs 'yes-or-no-p)

(ivy-mode t)
(setq ivy-re-builders-alist
      '((t . ivy--regex-fuzzy)))


(setq x-select-enable-clipboard t)
(setq interprogram-paste-function 'x-selection-value)

(put 'upcase-region 'disabled nil)
(put 'downcase-region 'disabled nil)
(put 'set-goal-column 'disabled nil)
(put 'scroll-left 'disabled nil)
(put 'erase-buffer 'disabled nil)

(defun scroll-down-one-line () (interactive) (scroll-down 1))
(defun scroll-up-one-line () (interactive) (scroll-up 1))

(defvar toggled-arrow-keys t)
(defun toggle-arrow-keys ()
  (interactive)
  (if toggled-arrow-keys
      (progn
	(global-set-key (kbd "<up>") 'scroll-down-one-line)
	(global-set-key (kbd "<down>") 'scroll-up-one-line)

	(global-set-key (kbd "<left>") (lambda (&optional n)
					 (interactive "p")
					 (if n
					     (other-window (- n))
					   (other-window -1))))

	(global-set-key (kbd "<right>") (lambda (&optional n)
					  (interactive "p")
					  (if n
					      (other-window n)
					    (other-window 1))))
	(setq toggled-arrow-keys nil))
    (progn
      (global-set-key (kbd "<left>") 'backward-char)
      (global-set-key (kbd "<right>") 'forward-char)
      (global-set-key (kbd "<up>") 'previous-line)
      (global-set-key (kbd "<down>")'next-line)
      (setq toggled-arrow-keys t))))
(toggle-arrow-keys)


;; Move current line up and down
(defun move-line (n)
  "Move the current line up or down by N lines."
  (interactive "p")
  (setq col (current-column))
  (beginning-of-line) (setq start (point))
  (end-of-line) (forward-char) (setq end (point))
  (let ((line-text (delete-and-extract-region start end)))
    (forward-line n)
    (insert line-text)
    ;; restore point to original column in moved line
    (forward-line -1)
    (forward-char col)))

(defun move-line-up (n)
  "Move the current line up by N lines."
  (interactive "p")
  (move-line (if (null n) -1 (- n))))

(defun move-line-down (n)
  "Move the current line down by N lines."
  (interactive "p")
  (move-line (if (null n) 1 n)))

(global-set-key (kbd "M-<up>") 'move-line-up)
(global-set-key (kbd "M-<down>") 'move-line-down)
(global-set-key (kbd "C-x t") 'toggle-truncate-lines)
(global-set-key (kbd "M-RET") 'ff-find-related-file)
(global-set-key (kbd "M-n") 'next-error)
(global-set-key (kbd "M-p") 'previous-error)
