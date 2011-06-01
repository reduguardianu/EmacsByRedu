(let ((new-paths '("/usr/local/bin/"
                   "/opt/local/bin/"
                   "/Users/lmm/bin/"
                   "/Users/lmm/otp/bin/")))
  (setq exec-path (append new-paths exec-path))
  (setenv "PATH" (concat (getenv "PATH") ":" (mapconcat 'identity new-paths ":"))))

