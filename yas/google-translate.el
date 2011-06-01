;;; google-translate.el --- Translate text using Google Translate API

;; Copyright (C) 2010 Andrey Torba

;; Author: Andrey Torba <andrey.torba@gmail.com>
;; Version: 0.1
;; Keywords: convenience

;;; Commentary:

;; This is a library for rapid text translating
;; using Google AJAX Language API 

;; Learn all about Google AJAX Language API here:
;;    <http://code.google.com/intl/en/apis/ajaxlanguage/>

;; The latest version:
;;  git://github.com/andreo/google-translator.git
;;  http://github.com/andreo/google-translator.git

;; There are two dependencies url.el and json.el.
;; url.el is part of GNU Emacs.
;; json.el is available here:
;;   http://cvs.savannah.gnu.org/viewvc/*checkout*/emacs/lisp/json.el?root=emacs

;; Usage:

;; * (gt-detect-language "Detect the language of this text")
;;   "en"

;; * (gt-inteligent-translate "Guess what i mean")
;;   "Ð£Ð³Ð°Ð´Ð°Ð¹ÑÐµ, ÑÑÐ¾ Ñ Ð¸Ð¼ÐµÑ Ð² Ð²Ð¸Ð´Ñ"

;; * (gt-translate "Hello world!" "en" "ru")
;;   "ÐÑÐ¸Ð²ÐµÑ Ð¼Ð¸Ñ!"

;; * (gt-translate "Hello world!" "en" "uk")
;;   "ÐÑÐ¸Ð²ÑÑ ÑÐ²ÑÑ!"

;; * (gt-translate "Hello world!" "en" "de")
;;   "Hallo Welt!"

;; * (gt-translate "Hello world!" "en" "fr")
;;   "Bonjour le monde!"

;; * customize guess language table:
;;   (setq gt-guess-language-table
;;         (list 'en 'ru
;;               'ru 'en
;;               'uk 'en))

;;; Code:

(require 'url)
(require 'json)

(defgroup google-translate nil
  "This is a library for rapid text translating
using Google AJAX Language API"
  :version "0.1")

(defcustom gt-detect-language-base-url
  "http://ajax.googleapis.com/ajax/services/language/detect"
  "Google AJAX Language API base url to detect language of text."
  :type 'string
  :group 'google-translate)

(defcustom gt-translate-base-url
  "http://ajax.googleapis.com/ajax/services/language/translate"
  "Google AJAX Language API base url to translate text."
  :type 'string
  :group 'google-translate)

(defcustom gt-guess-language-table
  nil
  "Contain information about what language to translate to."
  :type 'plist
  :group 'google-translate)

(defun url-data (url)
  "Retrieve data, header and status of URL."
  (with-current-buffer
      (url-retrieve-synchronously url)

    (setq status url-http-response-status)
    ;; return the header and the data separately
    (goto-char (point-min))
    (if (search-forward-regexp "^$" nil t)
        (setq header (buffer-substring (point-min) (point))
              data   (buffer-substring (1+ (point)) (point-max)))
      ;; unexpected situation, return the whole buffer
      (setq data (buffer-string))))
  (values data header status))

(defun url-retrieve-json (url)
  "Retrieve json result of URL as a `plist'."
  (let ((data (first (url-data url)))
        (json-object-type 'plist))
    (when data (json-read-from-string data))))




(defun gt-make-detect-language-url (text)
  "Make url to detect language of TEXT."
  (concat gt-detect-language-base-url
          "?v=1.0"
          "&q=" (url-hexify-string text)))

(defun gt-detect-language (text)
  "Retrieve language of TEXT."
  (interactive "stext: ")
  (let* ((url (gt-make-detect-language-url text))
         (json (url-retrieve-json url)))
    (getf (getf json :responseData) :language)))



(defun gt-make-translate-url (text from to)
  "Make url to translate TEXT from language FROM to language TO."
  (concat gt-translate-base-url
          "?v=1.0"
          "&q=" (url-hexify-string text)
          "&langpair=" from "%7c" to))

(defmacro prompt-if-nil (value prompt-message history)
  "If VALUE is nil read it from the minibuffer.
Prompt with string PROMPT-MESSAGE.
HISTORY, if non-nil, specifies a history list (see `read-from-minibuffer')."
  `(or ,value (read-from-minibuffer ,prompt-message nil nil nil ,history)))

(defun fit-string-to-size (string max-size)
  "If STRING lenght greater than MAX-SIZE cut STRING to fit MAX-SIZE."
  (if (<= (length string) max-size)
      string
    (concat (substring string 0 (- max-size 3)) "...")))

(defvar gt-translate-text-history nil
  "History of translated texts.")
(defvar gt-translate-language-history nil
  "History of input languages.")

(defun gt-read-text-from-to (text from to)
  "Read TEXT, FROM language and TO language from minibuffer."
  (let* ((text (prompt-if-nil text
                              "translate: "
                              'gt-translate-text-history))
         (cut-text (fit-string-to-size text 15))
         (from (prompt-if-nil from
                              (format "translate '%s' from: "
                                      cut-text)
                              'gt-translate-language-history))
         (to (prompt-if-nil to
                            (format "translate '%s' from '%s' to: "
                                    cut-text
                                    from)
                            'gt-translate-language-history)))
    (list text from to)))

(defun gt-translate (text from to)
  "Translate TEXT from language FROM to language TO."
  (interactive (gt-read-text-from-to nil nil nil))

  (let* ((url (gt-make-translate-url text from to))
         (json (url-retrieve-json url))
         (result (getf (getf json :responseData) :translatedText)))
    (decode-coding-string result 'utf-8)))

(defun gt-guess-language-to (language)
  "Guess the language i want to translate to from LANGUAGE."
  (let ((language-to (getf gt-guess-language-table (intern language))))
    (when language-to (symbol-name language-to))))

(defun gt-inteligent-translate (text)
  "Translate TEXT, detecting source language and guessing language to translate."
  (interactive "stranslate: ")
  (let* ((from-language (gt-detect-language text))
         (args (gt-read-text-from-to text
                                     from-language
                                     (gt-guess-language-to from-language)))
         (text (first args))
         (from (second args))
         (to (third args))
         (translated (gt-translate text from to)))
    (format "%s: %s\n%s: %s" from text to translated)))

(defun gt-translate-current-word()
  "Translate current word."
  (interactive)
  (gt-inteligent-translate (current-word)))

(provide 'google-translate)

;;; google-translate.el ends here