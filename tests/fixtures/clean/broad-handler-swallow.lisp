;;; Clean file for broad-handler-swallow rule
;;; Every handler here keeps the condition reachable, or names what it expects.

;; Binds the condition and passes it on
(defun run-reader (session)
  (handler-case (%run-reply-reader session)
    (error (c) (%drain-outstanding-with-error session c))))

;; Binds the condition and re-signals a typed one
(defun boot-node (config)
  (handler-case (start-listeners config)
    (error (e) (error 'node-boot-failed :message (princ-to-string e)))))

;; Binds nothing, but the clause's normal exit signals
(defun call-provider (gf provider seam)
  (handler-case (funcall gf provider)
    (error () (error 'provider-refused :seam seam :reason :absent-op))))

;; The tail signal is reached through progn
(defun retry-once (thunk)
  (handler-case (funcall thunk)
    (error () (progn (record-attempt) (signal 'retry-exhausted)))))

;; Every clause names the failure it expects
(defun handshake (conn)
  (handler-case (tls-handshake conn)
    (tls-certificate-error () :bad-certificate)
    (tls-context-cancelled () :cancelled)
    (tls-deadline-exceeded () :timed-out)
    (tls-error () :failed)))

;; A compound type specifier names its failures, so it is not blanket
(defun read-count (text)
  (handler-case (parse-integer text)
    ((or parse-error end-of-file) () (values nil 0))))

;; :no-error handles nothing and is never reported
(defun parse-count (text)
  (handler-case (parse-integer text)
    (parse-error () (values nil 0))
    (:no-error (value position) (values value position))))
