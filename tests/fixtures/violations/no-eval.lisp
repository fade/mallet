;;; Test file for no-eval rule

;; Bad: direct eval
(defun run-code (expr)
  (eval expr))

;; Bad: eval via funcall
(defun run-fn (expr)
  (funcall #'eval expr))

;; Bad: eval via apply
(defun run-apply (forms)
  (apply #'eval forms))

;; Good: no eval
(defun add (x y)
  (+ x y))

;; Good: keyword-headed rows in a backquoted table are data, not calls
(defun eval-rows (x)
  `((:eval alpha ,x)
    (:eval gamma ,x)))
