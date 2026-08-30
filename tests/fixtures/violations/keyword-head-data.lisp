;;; Control set: a keyword in head position is data, never an operator.
;;; The rows do not share one shape: quoting and the unquote vary alongside the
;;; head. What they share is that every head sits in a table entry, not operator
;;; position. The unquoted call at the bottom is the only violation possible here.

(defparameter *quoted-rows*
  '((:ignore-errors alpha beta)
    (:ignore-errors gamma delta)))

(defun backquoted-keyword-rows (x)
  `((:ignore-errors alpha ,x)
    (:ignore-errors gamma ,x)))

(defun backquoted-plain-rows (x)
  `((alpha beta ,x)
    (gamma delta ,x)))

;; Known positive: code reached through an unquote is still runtime code.
(defun wrap-risky (x)
  `(outer ,(ignore-errors (risky x))))
