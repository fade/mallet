;;; Test file for no-ignore-errors rule

;; Bad: direct ignore-errors
(defun run-safely (op)
  (ignore-errors (funcall op)))

;; Bad: ignore-errors in let body
(defun fetch-value (key table)
  (ignore-errors (gethash key table)))

;; Bad: ignore-errors with multiple forms
(defun load-config (path)
  (ignore-errors
    (with-open-file (stream path)
      (read stream))))

;; Good for this rule: handler-case rather than ignore-errors.
;; The blanket clause is reported by broad-handler-swallow instead.
(defun safe-parse (str)
  (handler-case (parse-integer str)
    (error () nil)))

;; Good: plain function call, no error handling
(defun add (x y)
  (+ x y))
