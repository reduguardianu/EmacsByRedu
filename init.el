(package-initialize)

(server-mode t)
(add-to-list 'auto-mode-alist '("\\.org\\'" . org-mode))
(add-to-list 'auto-mode-alist '("\\.show\\'" . org-mode))
(add-to-list 'auto-mode-alist '("\\.proto\\'" . protobuf-mode))

(setenv "ESHELL" "/usr/bin/zsh")

(setq my-emacs-dir "~/.emacs.d/")
(add-to-list 'load-path (concat my-emacs-dir "gnome-shell-mode/" "local/" "gnome-shell-mode"))
(add-to-list 'load-path (concat my-emacs-dir "gnome-shell-mode/" "local/" "company-gnome-shell"))
(add-to-list 'load-path (concat my-emacs-dir "lisp"))

(load "look-and-feel.el")
(load  "utils.el")

;;
;; ace jump mode major function
;;
(add-to-list 'load-path (concat my-emacs-dir "ace-jump-mode/"))
(autoload
  'ace-jump-mode
  "ace-jump-mode"
  "Emacs quick move minor mode"
  t)
;; you can select the key you prefer to
(define-key global-map (kbd "C-c SPC") 'ace-jump-mode)

(require 'package)
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)
(global-set-key (kbd "s-SPC") 'omnisharp-auto-complete)
(load-theme 'ample t)
(set-mouse-color "white")

(add-hook 'python-mode-hook 'jedi:setup)
(setq jedi:complete-on-dot t)

(projectile-mode +1)
(define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)

(require 'dashboard)
(setq dashboard-projects-backend 'projectile)
(setq dashboard-startup-banner 'logo)
(dashboard-setup-startup-hook)
(setq dashboard-center-content t)
(setq dashboard-items '((recents   . 5)
                        (projects  . 5)
                        (agenda    . 5)))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(company lsp-java helpful swiper dashboard all-the-icons nerd-icons page-break-lines projectile yasnippet ivy projectile qml-mode docker-compose-mode dockerfile-mode json-mode s "s" groovy-mode python-mode jedi flycheck-plantuml xclip typescript-mode lua-mode ein xml+ whitespace-cleanup-mode realgud protobuf-mode php-mode php+-mode magit color-theme ample-zen-theme ample-theme ac-anaconda)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
(require 'lsp-java)
(add-hook 'java-mode-hook #'lsp)
