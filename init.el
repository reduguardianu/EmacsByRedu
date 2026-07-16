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


  (setq lombok-library-path (concat my-emacs-dir "java-lsp/" "lombok.jar"))

  (unless (file-exists-p lombok-library-path)
    (url-copy-file "https://projectlombok.org/downloads/lombok.jar" lombok-library-path))

  (setq lsp-java-vmargs '("-XX:+UseParallelGC" "-XX:GCTimeRatio=4" "-XX:AdaptiveSizePolicyWeight=90" "-Dsun.zip.disableMemoryMapping=true" "-Xmx4G" "-Xms100m"))

  (push (concat "-javaagent:"
                  (expand-file-name lombok-library-path))
          lsp-java-vmargs)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(all-the-icons ample-theme company dashboard docker-compose-mode
                   dockerfile-mode helpful jedi json-mode logview
                   lsp-java lsp-pyright lua-mode magit nerd-icons
                   page-break-lines projectile protobuf-mode
                   pyenv-mode pyvenv qml-mode rg sqlformat swiper
                   toc-org transient transient-posframe
                   typescript-mode yasnippet))
 '(safe-local-variable-directories '("/home/marek/Projects/TrophyHunter/backend/schnapps/")))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
(require 'lsp-java)
(add-hook 'java-mode-hook #'lsp)

(use-package lsp-pyright
  :ensure t
  :hook (python-mode . (lambda ()
                          (require 'lsp-pyright)
                          (lsp-deferred))))

;; Ensure ruff and pyright can run together
(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-enabled-clients 'pyright)
  (add-to-list 'lsp-enabled-clients 'ruff))

(use-package pyvenv
  :ensure t
  :config
  (pyvenv-mode 1))

(setq visible-bell t)

(add-hook 'js-mode-hook
  (lambda ()
    (setq js-indent-level 2)))
(setq package-install-upgrade-built-in t)
