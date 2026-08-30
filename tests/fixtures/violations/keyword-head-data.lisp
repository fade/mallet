;;; Control set: a keyword in head position is data, never an operator.
;;; Each row holds the row shape constant and varies only what sits at the head.
;;; The unquoted call at the bottom is the only real code here, so it is the
;;; only violation this file may produce.

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
