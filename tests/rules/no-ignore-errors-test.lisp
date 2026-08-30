(defpackage #:mallet/tests/rules/no-ignore-errors
  (:use #:cl
        #:rove)
  (:local-nicknames
   (#:rules #:mallet/rules)
   (#:parser #:mallet/parser)
   (#:violation #:mallet/violation)))
(in-package #:mallet/tests/rules/no-ignore-errors)

;;; Helper

(defun check-ignore-errors (code)
  (let ((forms (parser:parse-forms code #p"test.lisp"))
        (rule (make-instance 'rules:no-ignore-errors-rule)))
    (mapcan (lambda (form)
              (rules:check-form rule form #p"test.lisp"))
            forms)))

;;; Valid cases (no violations expected)

(deftest ignore-errors-usage-valid
  (testing "No ignore-errors: plain function call"
    (ok (null (check-ignore-errors "(defun foo (x) (+ x 1))"))))

  (testing "No ignore-errors: handler-case usage"
    (ok (null (check-ignore-errors
               "(handler-case (risky-op) (error (e) (log-error e)))"))))

  (testing "No ignore-errors: string containing ignore-errors"
    (ok (null (check-ignore-errors
               "(defun doc () \"Use ignore-errors to suppress.\")") )))

  (testing "No ignore-errors: funcall with unrelated function"
    (ok (null (check-ignore-errors "(funcall #'print \"hello\")"))))

  (testing "No ignore-errors: apply with unrelated function"
    (ok (null (check-ignore-errors "(apply #'+ '(1 2 3))"))))

  (testing "No ignore-errors: defmacro body skipped"
    (ok (null (check-ignore-errors
               "(defmacro safe-call (form) `(ignore-errors ,form))")))))

;;; A keyword in head position is a data value, never an operator.
;;; The rows do not share one shape: quoting, the unquote, the construct, and
;;; whether the head is a keyword at all vary between them, and the fourth is a
;;; defclass option list rather than a table row. What they share is that no
;;; head among them sits in the operator position of evaluated code. The last
;;; row is the known positive: genuine code reached through an unquote, which
;;; must still report, so a silent run cannot pass for a clean one.

(deftest ignore-errors-keyword-head-is-data
  (testing "Quoted data rows with a keyword head are silent"
    (ok (null (check-ignore-errors
               "(defparameter *rows* '((:ignore-errors a b) (:ignore-errors c d)))"))))

  (testing "Backquoted data rows with a keyword head are silent"
    (ok (null (check-ignore-errors
               "(defun rows (x) `((:ignore-errors a ,x) (:ignore-errors c ,x)))"))))

  (testing "Backquoted data rows with a non-keyword head are silent"
    (ok (null (check-ignore-errors
               "(defun rows (x) `((alpha a ,x) (beta c ,x)))"))))

  (testing "Keyword head in an option list is silent"
    (ok (null (check-ignore-errors
               "(defclass thing () () (:ignore-errors \"not an operator\"))"))))

  (testing "Known positive: code reached through an unquote still reports"
    (let ((violations (check-ignore-errors
                       "(defun wrap (x) `(outer ,(ignore-errors (risky x))))")))
      (ok (= (length violations) 1))
      (ok (eq (violation:violation-rule (first violations)) :no-ignore-errors)))))

;;; Invalid cases (violations expected)

(deftest ignore-errors-usage-direct
  (testing "Direct (ignore-errors ...) call"
    (let ((violations (check-ignore-errors "(ignore-errors (risky-op))")))
      (ok (= (length violations) 1))
      (ok (eq (violation:violation-rule (first violations)) :no-ignore-errors))
      (ok (eq (violation:violation-severity (first violations)) :warning))
      (ok (search "ignore-errors" (violation:violation-message (first violations))))))

  (testing "Direct ignore-errors nested inside defun"
    (let ((violations (check-ignore-errors
                       "(defun dangerous (op) (ignore-errors (funcall op)))")))
      (ok (= (length violations) 1))
      (ok (eq (violation:violation-rule (first violations)) :no-ignore-errors))))

  (testing "Multiple ignore-errors calls"
    (let ((violations (check-ignore-errors
                       "(progn (ignore-errors (foo)) (ignore-errors (bar)))")))
      (ok (= (length violations) 2))))

  (testing "ignore-errors with no body"
    (let ((violations (check-ignore-errors "(ignore-errors)")))
      (ok (= (length violations) 1))
      (ok (eq (violation:violation-rule (first violations)) :no-ignore-errors)))))

(deftest ignore-errors-usage-category
  (testing "Rule has :practice category"
    (let ((rule (make-instance 'rules:no-ignore-errors-rule)))
      (ok (eq (rules:rule-category rule) :practice))))

  (testing "Rule has :warning severity"
    (let ((rule (make-instance 'rules:no-ignore-errors-rule)))
      (ok (eq (rules:rule-severity rule) :warning)))))

;;; Registration tests

(deftest ignore-errors-usage-registration
  (testing ":no-ignore-errors is in default config"
    (let* ((cfg (mallet/config:get-built-in-config :default))
           (rule-names (mapcar #'rules:rule-name (mallet/config:config-rules cfg))))
      (ok (member :no-ignore-errors rule-names))))

  (testing ":no-ignore-errors is in :all config"
    (let* ((cfg (mallet/config:get-built-in-config :all))
           (rule-names (mapcar #'rules:rule-name (mallet/config:config-rules cfg))))
      (ok (member :no-ignore-errors rule-names))))

  (testing ":no-ignore-errors rule has :practice category"
    (let ((rule (rules:make-rule :no-ignore-errors)))
      (ok (eq :practice (rules:rule-category rule))))))
