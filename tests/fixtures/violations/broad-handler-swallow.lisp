;;; Test file for broad-handler-swallow rule

;; Bad: blanket clause hands back a fallback value and drops the condition
(defun decode-octets (octets)
  (handler-case (sb-ext:octets-to-string octets :external-format :utf-8)
    (error () (map 'string #'code-char octets))))

;; Bad: blanket clause records a flag instead of the condition
(defun advance-node (node data)
  (handler-case (noise-advance node data)
    (error ()
      (setf (node-state node) :failed)
      (setf (node-key node) nil))))

;; Bad: CONDITION catches just as much as ERROR
(defun probe-target (target)
  (handler-case (contact target)
    (condition () nil)))

;; Bad: ignore-errors keeps nothing at all
(defun suggested-renewal (endpoint)
  (ignore-errors (ari-suggested-renewal endpoint)))

;; Good: binds the condition and hands it to the drain path
(defun run-reader (session)
  (handler-case (%run-reply-reader session)
    (error (c) (%drain-outstanding-with-error session c))))

;; Good: binds nothing, but the clause signals a typed condition
(defun call-provider (gf provider seam)
  (handler-case (funcall gf provider)
    (error () (error 'probe-wire-provider-refused :seam seam :reason :absent-op))))

;; Good: every clause names the failure it expects
(defun parse-count (text)
  (handler-case (parse-integer text)
    (parse-error () (values nil 0))))
