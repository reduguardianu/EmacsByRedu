(require 'json)
(require 'url)

(defconst client-process-name "*gvr_editor_client*")
(defconst host "192.168.0.198")
(defconst port 2001)
(defsubst client-process () )

(defun send-message (str)
  (process-send-string (client-process) (concat str "\r\n"))
  )

(defun gvr-connect-to-admin-panel ()
  (interactive)
  (make-network-process :name client-process-name
                        :host host
                        :service port
                        :nowait nil)
  (send-message "login;dev;dev")
)


(defun gvr_load_player ()
  (interactive)
  (setq player_id (read-from-minibuffer "* Player id: "))
  (send-message "load_player;NK-NK-person.007")
  )


