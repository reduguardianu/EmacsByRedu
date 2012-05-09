;; Simple ReviewBoard integration
;;
;; post-review/new-review-request lets you post review on ReviewBoard
;; from within your favourite editor, which is Emacs.
;;
;; YOU NEED TO HAVE POST-REVIEW SCRIPT INSTALLED on your system
;; See
;; http://www.reviewboard.org/docs/manual/dev/users/tools/post-review/
;; for details
;;
;; Remember to set ReviewBoard hostname, username, password and groups.
;;
;; Installation
;; ~~~~~~~~~~~~
;; 1. Install post-review (see above)
;; 2. Add this script to your load-path.
;;
;; Usage
;; ~~~~~
;; 1. Go into directory where you would normally run magit-status (git
;;    repo)
;; 2. Run post-review/new-review-request interactive function
;; 3. Browser window will pop-up. Make changes if you want and click
;;    publish
;;
;; It will fill for you:
;;  - target groups to post-review/groups
;;  - target-people to what you give when prompted
;;  - branch to current branch
;;  - summary to frist line of last commit message
;;  - description to commit message except for first line
;;
;; It will also uplaod diff since HEAD (it works best if you squash
;; changes before committing)

;; review board settings
(defvar post-review/hostname "http://reviews.csgbox.com"
  "Connect to that server when posting review request")
(defvar post-review/username "marek.ozimina"
  "Post review as this user")
(defvar post-review/password "mar123k"
  "Use this password to authenticate")
(defvar post-review/groups "GvR"
  "To what groups should the review be assigned")

;; extracting info from git
(defvar post-review/get-log-command
  "git log --summary --no-color -1 --format=medium"
  "Command used to retrieve last commit message from git")
(defvar post-review/re-skip-line ".*\n"
  "Regex that matches single line")
(defvar post-review/re-summary "\\(.*\\)\n"
  "Regex that matches summary in commit message")
(defvar post-review/re-description "\\([[:ascii:]]*\\)"
  "Regex that matches description in commit message")

(defun post-review/get-commit-split-re ()
  "Generate regex that can parse commit message"
  (concat post-review/re-skip-line ;; commit
          post-review/re-skip-line ;; author
          post-review/re-skip-line ;; date
          post-review/re-skip-line ;; blank
          post-review/re-summary
          post-review/re-skip-line ;; blank
          post-review/re-description))

(defun post-review/get-summary-and-description ()
  "Retrieves summary and description from last commit message"
  (let* ((commit-split-re (post-review/get-commit-split-re))
         (log (shell-command-to-string post-review/get-log-command)))
    (string-match commit-split-re log)
    (let ((summary (match-string 1 log))
          (description (match-string 2 log)))
      (list summary description))))

(defun post-review/new-review-request ()
  "Submits code review to ReviewBoards. It will open browser with
code review opened. You need to click publish before code review
is visible for others"
  (interactive)
  (let* ((quot "'")
         (eop " ")
         (people (read-from-minibuffer "People: "))
         (sum-desc (post-review/get-summary-and-description))
         (summary (car sum-desc))
         (description (car (cdr sum-desc)))

         (cmd (concat "post-review "
                     "--server=" quot post-review/hostname quot eop
                     "--username=" quot post-review/username quot eop
                     "--password=" quot post-review/password quot eop
                     "--target-groups=" quot post-review/groups quot eop
                     "--target-people=" quot people quot eop
                     "--branch=" quot (magit-get-current-branch) quot eop
                     "--description=\"" description "\"" eop
                     "--summary=" quot summary quot eop
                     "--publish"
                     )))
    (shell-command cmd)))
