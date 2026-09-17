;;; hn-meta-mode.el --- Completion for Trophy Hunter meta-model JSON -*- lexical-binding: t; -*-

;; Author: Marek Ozimina
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: languages, tools, convenience

;;; Commentary:

;; Context aware completion, navigation and checking for the hn-common
;; meta-model, i.e. the JSON files under
;;
;;     model/src/main/resources/meta/**.json
;;
;; Those files describe the content model: every file is one type, named
;; after the file, and contains "fields", "props", "parent", "isEnum".
;; The vocabulary implemented here mirrors
;; model/src/main/java/script/generator/Prop.java and MetaModelUtil.java.
;;
;; What you get (in any JSON major mode, as a minor mode that turns
;; itself on for files under .../resources/meta/):
;;
;;   * completion-at-point (works with company, corfu, or plain C-M-i):
;;       - top level keys        fields / props / parent / isEnum / ...
;;       - field keys            name / type / typeArguments / props
;;       - field prop keys       isNullable / isServerOnly / ref / min / ...
;;       - class prop keys       path / isAbstract / subTypes / ...
;;       - "type" values         primitives + all ~480 model type names
;;       - "typeArguments"       same, inside the array
;;       - "ref"/"dictValueRef"  model types that declare an "isId" field
;;       - "parent": {"name":}   model types + refDict
;;       - "subTypes" values     model types
;;       - "defaultValue"        enum constants, when the field's type is an enum
;;       - "domain"              domains already used in the model
;;       - "path" keys           name / isDirectory / isResource / isOptional
;;       - booleans              true / false after boolean props
;;     Completing a key also inserts ": <stub>" (see `hn-meta-auto-insert-value').
;;
;;   * xref: M-. on a type name jumps to its .json, M-? finds references.
;;   * eldoc: type summary / prop documentation in the echo area.
;;   * imenu: the field list of the current file.
;;   * C-c C-c: report references to types that do not exist.
;;
;; Installation (~/.emacs.d/lisp is already on your load-path):
;;
;;     (require 'hn-meta-mode)
;;
;; Commands: `hn-meta-refresh-index', `hn-meta-find-type',
;; `hn-meta-insert-field', `hn-meta-check-buffer', `hn-meta-describe-type'.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'subr-x)
(require 'xref)

(defgroup hn-meta nil
  "Editing support for the Trophy Hunter meta-model JSON files."
  :group 'tools
  :prefix "hn-meta-")

(defcustom hn-meta-root-regexp "\\`\\(.*/resources/meta\\)/"
  "Regexp matched against a file's directory to find the meta-model root.
Group 1 must be the root directory of the meta model."
  :type 'regexp)

(defcustom hn-meta-index-ttl 120
  "Seconds before the type index is rebuilt from disk."
  :type 'integer)

(defcustom hn-meta-auto-insert-value t
  "When non-nil, completing an object key also inserts \": <stub>\"."
  :type 'boolean)

(defcustom hn-meta-nullable-shorthand t
  "When non-nil, offer \"int?\"-style nullable primitives as type candidates."
  :type 'boolean)


;;; ------------------------------------------------------------------
;;; Vocabulary (mirrors script.generator.Prop / MetaModelUtil)
;;; ------------------------------------------------------------------

(defconst hn-meta-scalar-primitives
  '(("str"      . "String")
    ("int"      . "Integer")
    ("long"     . "Long")
    ("float"    . "Float")
    ("double"   . "Double")
    ("bool"     . "Boolean")
    ("boolean"  . "boolean (primitive)")
    ("byte"     . "Byte")
    ("short"    . "Short")
    ("instant"  . "java.time.Instant")
    ("duration" . "java.time.Duration")
    ("date"     . "java.util.Date"))
  "Scalar primitive type names of the meta model.")

(defconst hn-meta-container-primitives
  '(("list"    . "List<T>, needs typeArguments")
    ("set"     . "Set<T>, needs typeArguments")
    ("dict"    . "Map<K,V>, needs typeArguments")
    ("refDict" . "ContentModelDictionary<T>")
    ("T"       . "generic type parameter"))
  "Container/generic primitive type names of the meta model.")

;; (NAME DOC KIND) - KIND drives the value stub inserted after the key.
(defconst hn-meta-top-level-keys
  '(("fields"        "field list, or {\"values\": [...]} for an enum" :array)
    ("props"         "class level properties"                          :object)
    ("parent"        "superclass, e.g. {\"name\": \"EventTask\"}"      :object)
    ("isEnum"        "this file describes an enum"                     :bool)
    ("typeArguments" "generic parameters declared by this type"        :array)
    ("name"          "model name (defaults to the file name)"          :string)
    ("domain"        "content domain this model belongs to"            :string)))

(defconst hn-meta-field-keys
  '(("name"          "field name"                                 :string)
    ("type"          "field type: primitive or model type"        :string)
    ("typeArguments" "type arguments for list/set/dict/refDict"   :array)
    ("props"         "field level properties"                     :object)))

(defconst hn-meta-enum-field-keys
  '(("values"     "enum constants"        :array)
    ("deprecated" "deprecated constants"  :array)))

(defconst hn-meta-field-props
  '(("isId"         "field is the model id (@Id)"                         :bool)
    ("isServerOnly" "not sent to the client (@JsonView(Private.class))"   :bool)
    ("isNullable"   "value may be null (@Nullable)"                       :bool)
    ("isNull"       "value must be null (@Null)"                          :bool)
    ("isNotEmpty"   "collection/string must not be empty (@NotEmpty)"     :bool)
    ("isPositive"   "number must be positive (@Positive)"                 :bool)
    ("isSorted"     "collection must be sorted (@Sorted)"                 :bool)
    ("isDate"       "value is a date (@Date)"                             :bool)
    ("isLockit"     "value is a localization key (@Lockit)"               :bool)
    ("isUnique"     "entries must be unique (@Unique)"                    :bool)
    ("ref"          "id reference to a model, \"A|B\" for several (@RefId)"   :string)
    ("dictValueRef" "dict values reference a model (@MapValueRefId)"      :string)
    ("min"          "minimum value or size (@Min)"                        :number)
    ("max"          "maximum value or size (@Max)"                        :number)
    ("defaultValue" "value used when the field is absent"                 :any)
    ("alias"        "JSON property name (@JsonProperty)"                  :string)
    ("deprecated"   "deprecated since (@Deprecated)"                      :string)
    ("description"  "human readable description (@Description)"           :string)))

(defconst hn-meta-class-props
  '(("path"                 "content file or directory (@Path)"            :object)
    ("isServerOnly"         "whole type is server only"                    :bool)
    ("isAbstract"           "abstract type, instantiated via subTypes"     :bool)
    ("hasCustomConstructors" "type has an all-args constructor or builder" :bool)
    ("subTypes"             "Jackson subtypes: [{\"name\":..,\"value\":..}]" :array)
    ("deprecated"           "deprecated since"                             :string)))

(defconst hn-meta-path-keys
  '(("name"       "file name (foo.json) or directory name"  :string)
    ("isDirectory" "content is a directory of files"        :bool)
    ("isResource" "loaded from resources"                   :bool)
    ("isOptional" "file does not have to exist"             :bool)))

(defconst hn-meta-subtype-keys
  '(("name"  "discriminator value"                 :string)
    ("names" "several discriminator values"        :array)
    ("value" "model type implementing this subtype" :string)))

(defun hn-meta--prop-entry (name)
  "Return the vocabulary entry for NAME, searching every table."
  (or (assoc name hn-meta-field-props)
      (assoc name hn-meta-class-props)
      (assoc name hn-meta-top-level-keys)
      (assoc name hn-meta-field-keys)
      (assoc name hn-meta-path-keys)
      (assoc name hn-meta-subtype-keys)))


;;; ------------------------------------------------------------------
;;; Candidates with annotations
;;; ------------------------------------------------------------------

(defun hn-meta--cand (str annot &optional doc kind)
  "Propertize STR with ANNOT, DOC and KIND for the completion UI."
  (propertize (copy-sequence str)
              'hn-meta-annot annot 'hn-meta-doc doc 'hn-meta-kind kind))

(defun hn-meta--table-cands (table)
  "Turn a (NAME DOC KIND) TABLE into completion candidates."
  (mapcar (lambda (e)
            (hn-meta--cand (nth 0 e) (nth 1 e) (nth 1 e) (nth 2 e)))
          table))

(defun hn-meta--annotation (cand)
  (when-let* ((a (get-text-property 0 'hn-meta-annot cand)))
    (concat "  " a)))

(defun hn-meta--docsig (cand)
  (get-text-property 0 'hn-meta-doc cand))


;;; ------------------------------------------------------------------
;;; The type index
;;; ------------------------------------------------------------------

(defvar hn-meta--index (make-hash-table :test 'equal)
  "Maps a meta root directory to (TIMESTAMP . INDEX-PLIST).")

(defun hn-meta-root (&optional file)
  "Return the meta-model root directory for FILE, or nil."
  (let* ((file (or file buffer-file-name default-directory))
         (dir (file-name-as-directory
               (expand-file-name (if (file-directory-p file)
                                     file
                                   (file-name-directory file))))))
    (when (string-match hn-meta-root-regexp dir)
      (file-name-as-directory (match-string 1 dir)))))

(defun hn-meta--parse-file (file)
  "Parse FILE as JSON into alists with symbol keys; nil when malformed."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (if (fboundp 'json-parse-buffer)
            (json-parse-buffer :object-type 'alist :array-type 'list
                               :null-object nil :false-object nil)
          (let ((json-object-type 'alist)
                (json-array-type 'list)
                (json-key-type 'symbol))
            (json-read))))
    (error nil)))

(defun hn-meta--meta-files (root)
  (seq-remove (lambda (f)
                (string-match-p "\\(/#\\|~\\'\\|\\.orig\\'\\|/\\.#\\)" f))
              (directory-files-recursively root "\\.json\\'")))

(defun hn-meta--scan (root)
  "Scan ROOT and return the index plist."
  (let ((types (make-hash-table :test 'equal))
        (domains nil))
    (dolist (file (hn-meta--meta-files root))
      (let* ((name (file-name-base file))
             (obj (hn-meta--parse-file file))
             (fields (alist-get 'fields obj))
             (props (alist-get 'props obj))
             (enum (and (alist-get 'isEnum obj) t))
             (domain (alist-get 'domain obj))
             (values (and enum (alist-get 'values fields)))
             (flist (when (and (not enum) (listp fields) (consp (car-safe fields)))
                      (mapcar (lambda (f)
                                (cons (alist-get 'name f) (alist-get 'type f)))
                              fields)))
             (ids (when (listp fields)
                    (delq nil (mapcar (lambda (f)
                                        (when (and (consp f)
                                                   (alist-get 'isId (alist-get 'props f)))
                                          (alist-get 'name f)))
                                      fields)))))
        (when (stringp domain) (cl-pushnew domain domains :test #'equal))
        (puthash name
                 (list :name name
                       :file file
                       :dir (directory-file-name
                             (file-relative-name (file-name-directory file) root))
                       :enum enum
                       :values (and (listp values) values)
                       :fields flist
                       :ids ids
                       :abstract (and (alist-get 'isAbstract props) t)
                       :parent (alist-get 'name (alist-get 'parent obj))
                       :path (alist-get 'name (alist-get 'path props)))
                 types)))
    (let (type-cands id-cands names)
      (maphash
       (lambda (name e)
         (push name names)
         (let ((annot (cond
                       ((plist-get e :enum)
                        (format "enum (%d) %s" (length (plist-get e :values))
                                (plist-get e :dir)))
                       ((plist-get e :abstract)
                        (format "abstract %s" (plist-get e :dir)))
                       (t (format "%d fields %s"
                                  (length (plist-get e :fields))
                                  (plist-get e :dir))))))
           (push (hn-meta--cand name annot (hn-meta--type-doc e)) type-cands)
           (when (plist-get e :ids)
             (push (hn-meta--cand name (format "id: %s" (car (plist-get e :ids)))
                                  (hn-meta--type-doc e))
                   id-cands))))
       types)
      (list :types types
            :domains (sort domains #'string<)
            :names (sort names #'string<)
            :type-cands (sort type-cands #'string<)
            :id-cands (sort id-cands #'string<)))))

(defun hn-meta-index (&optional force)
  "Return the index for the current buffer's meta root, rebuilding if stale."
  (when-let* ((root (hn-meta-root)))
    (let ((entry (gethash root hn-meta--index)))
      (when (or force (null entry)
                (> (float-time (time-since (car entry))) hn-meta-index-ttl))
        (setq entry (cons (current-time) (hn-meta--scan root)))
        (puthash root entry hn-meta--index))
      (cdr entry))))

(defun hn-meta-refresh-index ()
  "Rebuild the meta-model type index from disk."
  (interactive)
  (let ((idx (hn-meta-index t)))
    (message "hn-meta: indexed %d types in %s"
             (hash-table-count (plist-get idx :types)) (hn-meta-root))))

(defun hn-meta--invalidate ()
  (when-let* ((root (hn-meta-root)))
    (remhash root hn-meta--index)))

(defun hn-meta-type (name)
  "Return the index entry for type NAME."
  (when-let* ((idx (hn-meta-index)))
    (gethash name (plist-get idx :types))))

(defun hn-meta--type-doc (e)
  (cond
   ((plist-get e :enum)
    (format "enum %s: %s" (plist-get e :name)
            (string-join (plist-get e :values) ", ")))
   (t (format "%s%s: %d fields%s"
              (if (plist-get e :abstract) "abstract " "")
              (plist-get e :name)
              (length (plist-get e :fields))
              (if (plist-get e :parent)
                  (format ", extends %s" (plist-get e :parent)) "")))))

(defun hn-meta--primitive-cands (&optional containers-only)
  (append
   (mapcar (lambda (c) (hn-meta--cand (car c) (cdr c) (cdr c)))
           hn-meta-container-primitives)
   (unless containers-only
     (append
      (mapcar (lambda (c) (hn-meta--cand (car c) (cdr c) (cdr c)))
              hn-meta-scalar-primitives)
      (when hn-meta-nullable-shorthand
        (mapcar (lambda (c)
                  (hn-meta--cand (concat (car c) "?")
                                 (concat "nullable " (cdr c))))
                hn-meta-scalar-primitives))))))

(defun hn-meta--type-cands ()
  (append (hn-meta--primitive-cands)
          (plist-get (hn-meta-index) :type-cands)
          (hn-meta--local-type-args)))

(defun hn-meta--local-type-args ()
  "Generic parameters declared at the top level of this buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^[ \t]*\"typeArguments\"[ \t]*:[ \t]*\\[\\([^]]*\\)\\]" 3000 t)
      (mapcar (lambda (s) (hn-meta--cand s "generic parameter"))
              (split-string (match-string-no-properties 1) "[ \t\n\",]+" t)))))


;;; ------------------------------------------------------------------
;;; JSON context detection
;;; ------------------------------------------------------------------

(defun hn-meta--string-before (pos)
  "Contents of the string literal that ends at POS."
  (save-excursion
    (goto-char pos)
    (when (eq (char-before) ?\")
      (let ((end (1- (point)))
            (start (ignore-errors (scan-sexps (point) -1))))
        (when (and start (< start end))
          (buffer-substring-no-properties (1+ start) end))))))

(defun hn-meta--key-before (pos)
  "Return the object key whose value starts at POS, or nil."
  (save-excursion
    (goto-char pos)
    (skip-chars-backward " \t\n\r")
    (when (eq (char-before) ?:)
      (backward-char)
      (skip-chars-backward " \t\n\r")
      (hn-meta--string-before (point)))))

(defun hn-meta--enclosing ()
  "Open containers around point as a list of (POS CHAR KEY), outermost first."
  (mapcar (lambda (p) (list p (char-after p) (hn-meta--key-before p)))
          (nth 9 (syntax-ppss))))

(defsubst hn-meta--entry-char (e) (nth 1 e))
(defsubst hn-meta--entry-key (e) (nth 2 e))

(defun hn-meta--container-key (path n)
  "Key of the container N levels up from the innermost one in PATH."
  (hn-meta--entry-key (nth (- (length path) 1 n) path)))

(defun hn-meta--context ()
  "Describe the completion context at point.
Returns a plist with :what (`key', `value' or `bare'), :start, :end,
:key (the key whose value we are in) and :path."
  (let* ((ppss (syntax-ppss))
         (path (mapcar (lambda (p) (list p (char-after p) (hn-meta--key-before p)))
                       (nth 9 ppss)))
         (inner (car (last path)))
         (in-array (eq (hn-meta--entry-char inner) ?\[)))
    (cond
     ;; inside a string literal
     ((nth 3 ppss)
      (let* ((sstart (nth 8 ppss))
             (key-pos (and (not in-array)
                           (save-excursion
                             (goto-char sstart)
                             (skip-chars-backward " \t\n\r")
                             (not (eq (char-before) ?:))))))
        (list :what (if key-pos 'key 'value)
              :start (1+ sstart)
              :end (point)
              :key (if in-array
                       (hn-meta--entry-key inner)
                     (hn-meta--key-before sstart))
              :path path)))
     ;; a bare token: true / false / null
     ((looking-back "[[:alpha:]]*" (line-beginning-position))
      (let ((start (save-excursion (skip-chars-backward "[:alpha:]") (point))))
        (list :what 'bare
              :start start
              :end (point)
              :key (if in-array
                       (hn-meta--entry-key inner)
                     (hn-meta--key-before start))
              :path path))))))

(defun hn-meta--field-object-p (path)
  "Non-nil when the innermost container of PATH is an element of \"fields\"."
  (let ((inner (car (last path))))
    (and (eq (hn-meta--entry-char inner) ?{)
         (null (hn-meta--entry-key inner))
         (equal (hn-meta--container-key path 1) "fields"))))

(defun hn-meta--subtype-object-p (path)
  (let ((inner (car (last path))))
    (and (eq (hn-meta--entry-char inner) ?{)
         (null (hn-meta--entry-key inner))
         (equal (hn-meta--container-key path 1) "subTypes"))))


;;; ------------------------------------------------------------------
;;; Candidate selection
;;; ------------------------------------------------------------------

(defun hn-meta--key-candidates (path)
  "Object keys valid at the innermost container of PATH."
  (let* ((inner (car (last path)))
         (ikey (hn-meta--entry-key inner))
         (keys (mapcar #'hn-meta--entry-key path)))
    (hn-meta--table-cands
     (cond
      ((= (length path) 1) hn-meta-top-level-keys)
      ((equal ikey "props")
       (if (member "fields" keys) hn-meta-field-props hn-meta-class-props))
      ((equal ikey "path") hn-meta-path-keys)
      ((equal ikey "parent")
       '(("name" "parent model type" :string)
         ("typeArguments" "type arguments passed to the parent" :array)))
      ((equal ikey "fields") hn-meta-enum-field-keys) ; enum: "fields": {"values": ...}
      ((hn-meta--field-object-p path) hn-meta-field-keys)
      ((hn-meta--subtype-object-p path) hn-meta-subtype-keys)
      (t nil)))))

(defun hn-meta--sibling-value (objpos key)
  "Value of the string property KEY inside the object opening at OBJPOS."
  (save-excursion
    (let ((limit (or (ignore-errors (scan-lists objpos 1 0))
                     (min (point-max) (+ objpos 4000)))))
      (goto-char objpos)
      (when (re-search-forward
             (format "\"%s\"[ \t\n]*:[ \t\n]*\"\\([^\"]*\\)\"" (regexp-quote key))
             limit t)
        (match-string-no-properties 1)))))

(defun hn-meta--enum-default-candidates (path)
  "Enum constants when completing \"defaultValue\" of an enum typed field."
  (let* ((field (nth (- (length path) 2) path)) ; the field object holding "props"
         (type (and field (hn-meta--sibling-value (car field) "type")))
         (entry (and type (hn-meta-type type))))
    (when (plist-get entry :enum)
      (mapcar (lambda (v) (hn-meta--cand v (format "%s constant" type)))
              (plist-get entry :values)))))

(defun hn-meta--path-name-candidates ()
  "Suggest content file/directory names derived from the buffer file name."
  (when buffer-file-name
    (let* ((case-fold-search nil)
           (base (file-name-base buffer-file-name))
           (snake (downcase (replace-regexp-in-string
                             "\\([a-z0-9]\\)\\([A-Z]\\)" "\\1_\\2" base))))
      (list (hn-meta--cand (concat snake ".json") "single content file")
            (hn-meta--cand snake "content directory (use isDirectory)")))))

(defun hn-meta--value-candidates (key path)
  "Candidates for a string value under KEY within PATH."
  (let ((inner-key (hn-meta--entry-key (car (last path)))))
    (cond
     ((member key '("type")) (hn-meta--type-cands))
     ((member key '("typeArguments")) (hn-meta--type-cands))
     ((member key '("ref" "dictValueRef"))
      (or (plist-get (hn-meta-index) :id-cands)
          (plist-get (hn-meta-index) :type-cands)))
     ((equal key "defaultValue") (hn-meta--enum-default-candidates path))
     ((equal key "domain")
      (mapcar (lambda (d) (hn-meta--cand d "domain"))
              (plist-get (hn-meta-index) :domains)))
     ((equal key "name")
      (cond
       ((equal inner-key "parent")
        (cons (hn-meta--cand "refDict" "ContentModelDictionary")
              (plist-get (hn-meta-index) :type-cands)))
       ((equal inner-key "path") (hn-meta--path-name-candidates))
       ((= (length path) 1)
        (when buffer-file-name
          (list (hn-meta--cand (file-name-base buffer-file-name) "file name"))))
       (t nil)))
     ((and (equal key "value") (hn-meta--subtype-object-p path))
      (plist-get (hn-meta-index) :type-cands))
     (t nil))))

(defun hn-meta--bare-candidates (key)
  "Candidates for a non-string value under KEY."
  (let ((entry (hn-meta--prop-entry key)))
    (cond
     ((eq (nth 2 entry) :bool)
      (list (hn-meta--cand "true" (nth 1 entry))
            (hn-meta--cand "false" (nth 1 entry))))
     ((null key) nil)
     (t (list (hn-meta--cand "true" "") (hn-meta--cand "false" "")
              (hn-meta--cand "null" ""))))))


;;; ------------------------------------------------------------------
;;; completion-at-point
;;; ------------------------------------------------------------------

(defun hn-meta--exit-function (cand status)
  "After completing key CAND, insert \": <stub>\" when it is missing."
  (when (and hn-meta-auto-insert-value (eq status 'finished))
    (let ((kind (get-text-property 0 'hn-meta-kind cand)))
      (when (and kind (eq (char-after) ?\"))
        (save-restriction
          (widen)
          (let ((after (save-excursion
                         (forward-char 1)
                         (skip-chars-forward " \t")
                         (char-after))))
            (unless (eq after ?:)
              (forward-char 1)
              (pcase kind
                (:bool (insert ": true"))
                (:object (insert ": {}") (backward-char 1))
                ((or :array :type-array) (insert ": []") (backward-char 1))
                (:string (insert ": \"\"") (backward-char 1))
                (:number (insert ": "))
                (_ (insert ": "))))))))))

(defun hn-meta--completion-start (ctx)
  "Start of the token to replace, honouring the \"A|B\" syntax of refs."
  (let ((start (plist-get ctx :start))
        (end (plist-get ctx :end)))
    (if (member (plist-get ctx :key) '("ref" "dictValueRef"))
        (let ((bar (save-excursion
                     (goto-char end)
                     (search-backward "|" start t))))
          (if bar (1+ bar) start))
      start)))

(defun hn-meta-completion-at-point ()
  "`completion-at-point-functions' entry for the meta model."
  (when-let* ((ctx (hn-meta--context))
              (path (plist-get ctx :path)))
    (let* ((what (plist-get ctx :what))
           (key (plist-get ctx :key))
           (cands (pcase what
                    ('key (hn-meta--key-candidates path))
                    ('value (hn-meta--value-candidates key path))
                    ('bare (hn-meta--bare-candidates key)))))
      (when cands
        (list (hn-meta--completion-start ctx)
              (plist-get ctx :end)
              (completion-table-dynamic (lambda (_) cands))
              :exclusive 'no
              :annotation-function #'hn-meta--annotation
              :company-docsig #'hn-meta--docsig
              :company-kind (lambda (_) (if (eq what 'key) 'property 'value))
              :exit-function (when (eq what 'key) #'hn-meta--exit-function))))))


;;; ------------------------------------------------------------------
;;; Navigation (xref) and documentation (eldoc)
;;; ------------------------------------------------------------------

(defun hn-meta-type-at-point ()
  "Model type name at point, if any."
  (let* ((ppss (syntax-ppss))
         (name (when (nth 3 ppss)
                 (save-excursion
                   (goto-char (nth 8 ppss))
                   (when-let* ((end (ignore-errors (scan-sexps (point) 1))))
                     (buffer-substring-no-properties (1+ (point)) (1- end)))))))
    (when (and name (hn-meta-type (string-remove-suffix "?" name)))
      (string-remove-suffix "?" name))))

(defun hn-meta--xref-backend ()
  (and (bound-and-true-p hn-meta-mode) 'hn-meta))

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql hn-meta)))
  (hn-meta-type-at-point))

(cl-defmethod xref-backend-identifier-completion-table ((_backend (eql hn-meta)))
  (plist-get (hn-meta-index) :names))

(cl-defmethod xref-backend-definitions ((_backend (eql hn-meta)) id)
  (when-let* ((e (hn-meta-type id)))
    (list (xref-make (hn-meta--type-doc e)
                     (xref-make-file-location (plist-get e :file) 1 0)))))

(cl-defmethod xref-backend-references ((_backend (eql hn-meta)) id)
  (if (fboundp 'xref-matches-in-files)
      (xref-matches-in-files (format "\"%s\"" id)
                             (hn-meta--meta-files (hn-meta-root)))
    (user-error "xref-matches-in-files is not available")))

(cl-defmethod xref-backend-apropos ((_backend (eql hn-meta)) _pattern) nil)

(defun hn-meta-find-type (name)
  "Open the meta file defining model type NAME."
  (interactive
   (list (completing-read "Model type: " (plist-get (hn-meta-index) :names)
                          nil t (hn-meta-type-at-point))))
  (if-let* ((e (hn-meta-type name)))
      (find-file (plist-get e :file))
    (user-error "No such model type: %s" name)))

(defun hn-meta-describe-type (name)
  "Show the fields of model type NAME in a help buffer."
  (interactive
   (list (completing-read "Describe type: " (plist-get (hn-meta-index) :names)
                          nil t (hn-meta-type-at-point))))
  (let ((e (or (hn-meta-type name) (user-error "No such model type: %s" name))))
    (with-help-window "*hn-meta type*"
      (princ (format "%s\n%s\n\n" name (make-string (length name) ?=)))
      (princ (format "File:   %s\n" (plist-get e :file)))
      (when (plist-get e :parent)
        (princ (format "Parent: %s\n" (plist-get e :parent))))
      (when (plist-get e :path)
        (princ (format "Path:   %s\n" (plist-get e :path))))
      (princ "\n")
      (if (plist-get e :enum)
          (dolist (v (plist-get e :values)) (princ (format "  %s\n" v)))
        (dolist (f (plist-get e :fields))
          (princ (format "  %-40s %s\n" (car f) (or (cdr f) ""))))))))

(defun hn-meta-eldoc-function (callback &rest _)
  "Eldoc for the meta model: describe the type or prop at point."
  (let* ((ppss (syntax-ppss))
         (word (when (nth 3 ppss)
                 (save-excursion
                   (goto-char (nth 8 ppss))
                   (when-let* ((end (ignore-errors (scan-sexps (point) 1))))
                     (buffer-substring-no-properties (1+ (point)) (1- end))))))
         (entry (and word (hn-meta-type (string-remove-suffix "?" word))))
         (prop (and word (hn-meta--prop-entry word)))
         (prim (and word (or (assoc word hn-meta-scalar-primitives)
                             (assoc word hn-meta-container-primitives)))))
    (cond
     (entry (funcall callback (hn-meta--type-doc entry)))
     (prop (funcall callback (format "%s - %s" (car prop) (nth 1 prop))))
     (prim (funcall callback (format "%s - %s" (car prim) (cdr prim))))
     (t nil))))


;;; ------------------------------------------------------------------
;;; Checking and editing helpers
;;; ------------------------------------------------------------------

(defconst hn-meta--type-keys '("type" "typeArguments" "ref" "dictValueRef")
  "Keys whose string values must name a type.")

(defun hn-meta--known-type-p (name)
  (let ((base (string-remove-suffix "?" name)))
    (or (assoc base hn-meta-scalar-primitives)
        (assoc base hn-meta-container-primitives)
        (hn-meta-type base)
        (seq-find (lambda (c) (equal c base)) (mapcar #'identity (hn-meta--local-type-args))))))

(defun hn-meta-check-buffer ()
  "Report references to model types that do not exist."
  (interactive)
  (unless (hn-meta-root) (user-error "Not a meta-model file"))
  (hn-meta-index t)
  (let ((problems nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "\"" nil t)
        (let ((ppss (syntax-ppss)))
          (if (not (nth 3 ppss))
              nil
            (let* ((sstart (nth 8 ppss))
                   (send (or (ignore-errors (scan-sexps sstart 1)) (point-max)))
                   (text (buffer-substring-no-properties (1+ sstart) (1- send))))
              (goto-char (1- send))
              (save-excursion
                (goto-char (1+ sstart))
                (let* ((ctx (hn-meta--context))
                       (key (plist-get ctx :key))
                       (path (plist-get ctx :path)))
                  (when (and (eq (plist-get ctx :what) 'value)
                             (or (member key hn-meta--type-keys)
                                 (and (equal key "name")
                                      (equal (hn-meta--entry-key (car (last path))) "parent"))
                                 (and (equal key "value")
                                      (hn-meta--subtype-object-p path)))
                             (not (equal text "refDict")))
                    (dolist (part (if (member key '("ref" "dictValueRef"))
                                      (split-string text "|" t)
                                    (list text)))
                      (unless (hn-meta--known-type-p part)
                        (push (list (line-number-at-pos (1+ sstart))
                                    (save-excursion
                                      (goto-char (1+ sstart))
                                      (1+ (current-column)))
                                    part key)
                              problems))))))
              (goto-char send))))))
    (setq problems (nreverse problems))
    (if (null problems)
        (message "hn-meta: no unknown type references")
      (let ((file (or buffer-file-name (buffer-name))))
        (with-current-buffer (get-buffer-create "*hn-meta-check*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (format "Unknown model types in %s\n\n" file))
            (dolist (p problems)
              (insert (format "%s:%d:%d: unknown type %S (under %S)\n"
                              file (nth 0 p) (nth 1 p) (nth 2 p) (nth 3 p))))
            (compilation-mode))
          (display-buffer (current-buffer)))))))

(defun hn-meta-insert-field (name type)
  "Insert a field entry for NAME of TYPE at point."
  (interactive
   (list (read-string "Field name: ")
         (completing-read "Type: "
                          (append (mapcar #'car hn-meta-scalar-primitives)
                                  (mapcar #'car hn-meta-container-primitives)
                                  (plist-get (hn-meta-index) :names))
                          nil nil)))
  (let ((start (point)))
    (unless (bolp) (insert "\n"))
    (insert (format "{\n\"name\": \"%s\",\n\"type\": \"%s\"\n},\n" name type))
    (indent-region start (point))
    (when (member type '("list" "set" "dict" "refDict"))
      (goto-char start)
      (search-forward (format "\"type\": \"%s\"" type))
      (insert ",\n\"typeArguments\": [\"\"]")
      (indent-region start (point))
      (search-backward "\"\"")
      (forward-char 1))))

(defun hn-meta--imenu-index ()
  "Imenu index of the fields declared in this buffer."
  (let (index)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*\"name\"[ \t]*:[ \t]*\"\\([^\"]+\\)\"" nil t)
        (push (cons (match-string-no-properties 1)
                    (copy-marker (match-beginning 1)))
              index)))
    (nreverse index)))


;;; ------------------------------------------------------------------
;;; The minor mode
;;; ------------------------------------------------------------------

(defvar hn-meta-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-t") #'hn-meta-find-type)
    (define-key map (kbd "C-c C-d") #'hn-meta-describe-type)
    (define-key map (kbd "C-c C-f") #'hn-meta-insert-field)
    (define-key map (kbd "C-c C-c") #'hn-meta-check-buffer)
    (define-key map (kbd "C-c C-r") #'hn-meta-refresh-index)
    map)
  "Keymap for `hn-meta-mode'.")

;;;###autoload
(define-minor-mode hn-meta-mode
  "Completion and navigation for Trophy Hunter meta-model JSON files."
  :lighter " HN-Meta"
  :keymap hn-meta-mode-map
  (if hn-meta-mode
      (progn
        (add-hook 'completion-at-point-functions #'hn-meta-completion-at-point nil t)
        (add-hook 'xref-backend-functions #'hn-meta--xref-backend nil t)
        (add-hook 'after-save-hook #'hn-meta--invalidate nil t)
        (if (boundp 'eldoc-documentation-functions)
            (add-hook 'eldoc-documentation-functions #'hn-meta-eldoc-function nil t)
          (setq-local eldoc-documentation-function #'hn-meta-eldoc-function))
        (setq-local imenu-create-index-function #'hn-meta--imenu-index)
        (eldoc-mode 1))
    (remove-hook 'completion-at-point-functions #'hn-meta-completion-at-point t)
    (remove-hook 'xref-backend-functions #'hn-meta--xref-backend t)
    (remove-hook 'after-save-hook #'hn-meta--invalidate t)
    (when (boundp 'eldoc-documentation-functions)
      (remove-hook 'eldoc-documentation-functions #'hn-meta-eldoc-function t))))

;;;###autoload
(defun hn-meta-mode-maybe-enable ()
  "Turn on `hn-meta-mode' for JSON files inside the meta model."
  (when (and buffer-file-name
             (string-match-p "\\.json\\'" buffer-file-name)
             (hn-meta-root buffer-file-name))
    (hn-meta-mode 1)))

;;;###autoload
(dolist (hook '(json-mode-hook js-json-mode-hook json-ts-mode-hook))
  (add-hook hook #'hn-meta-mode-maybe-enable))

(provide 'hn-meta-mode)
;;; hn-meta-mode.el ends here
