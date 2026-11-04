;; -*- no-byte-compile: t; lexical-binding: nil -*-
(define-package "rg" "20261102.1804"
  "A search tool based on ripgrep."
  '((emacs     "28.1")
    (transient "0.9.2")
    (wgrep     "2.1.10"))
  :url "https://github.com/dajva/rg.el"
  :commit "1c689d53de9e47dfcf3bcf48e01b11f836e19b68"
  :revdesc "1c689d53de9e"
  :keywords '("matching" "tools")
  :authors '(("David Landell" . "david.landell@sunnyhill.email")
             ("Roland McGrath" . "roland@gnu.org"))
  :maintainers '(("David Landell" . "david.landell@sunnyhill.email")
                 ("Roland McGrath" . "roland@gnu.org")))
