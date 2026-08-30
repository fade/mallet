(defpackage #:mallet/tests/rules/runtime-unintern
  (:use #:cl
        #:rove)
  (:local-nicknames
   (#:rules #:mallet/rules)
   (#:parser #:mallet/parser)
   (#:violation #:mallet/violation)))
(in-package #:mallet/tests/rules/runtime-unintern)

;;; Helper

(defun check-runtime-unintern (code)
  (let ((forms (parser:parse-forms code #p"test.lisp"))
        (rule (make-instance 'rules:runtime-unintern-rule)))
    (mapcan (lambda (form)
              (rules:check-form rule form #p"test.lisp"))
            forms)))

;;; Valid cases — no violations

(deftest runtime-unintern-valid
  (testing "Regular function call — no violation"
    (ok (null (check-runtime-unintern
               "(defun foo (x) (+ x 1))"))))

  (testing "cl:intern does not trigger this rule"
    (ok (null (check-runtime-unintern
               "(defun foo (name) (cl:intern name))"))))

  (testing "unintern in defmacro body is not flagged (compile-time)"
    (ok (null (check-runtime-unintern
               "(defmacro foo (x) (cl:unintern x))"))))

  (testing "unintern with unknown package prefix is not flagged"
    (ok (null (check-runtime-unintern
               "(defun foo (x) (my-pkg:unintern x))")))))

;;; Invalid cases — violations expected

(deftest runtime-unintern-violations
  (testing "Direct cl:unintern call emits violation"
    (let ((violations (check-runtime-unintern
                       "(defun foo (sym pkg)
  (cl:unintern sym pkg))")))
      (ok (= 1 (length violations)))
      (ok (eq :runtime-unintern (violation:violation-rule (first violations))))
      (ok (eq :warning (violation:violation-severity (first violations))))))

  (testing "Unqualified unintern call emits violation"
    (let ((violations (check-runtime-unintern
                       "(defun foo (sym pkg)
  (unintern sym pkg))")))
      (ok (= 1 (length violations)))))

  (testing "common-lisp:unintern emits violation"
    (let ((violations (check-runtime-unintern
                       "(defun foo (sym pkg)
  (common-lisp:unintern sym pkg))")))
      (ok (= 1 (length violations)))))

  (testing "funcall #'cl:unintern emits violation"
    (let ((violations (check-runtime-unintern
                       "(defun foo (sym pkg)
  (funcall #'cl:unintern sym pkg))")))
      (ok (= 1 (length violations)))))

  (testing "apply #'cl:unintern emits violation"
    (let ((violations (check-runtime-unintern
                       "(defun foo (sym pkg)
  (apply #'cl:unintern (list sym pkg)))")))
      (ok (= 1 (length violations)))))

  (testing "violation message mentions cl:unintern"
    (let* ((violations (check-runtime-unintern
                        "(defun foo (sym pkg) (cl:unintern sym pkg))"))
           (msg (violation:violation-message (first violations))))
      (ok (search "unintern" (string-downcase msg)))))

  (testing "violation location points to the call"
    (let ((violations (check-runtime-unintern
                       "(defun foo (sym)
  (cl:unintern sym))")))
      (ok (= 1 (length violations)))
      (ok (= 2 (violation:violation-line (first violations)))))))

;;; Keyword in head position is data, never an operator

(deftest runtime-unintern-keyword-head-is-data-not-an-operator
  (testing "Keyword-headed funcall rows in a backquoted table are silent"
    (ok (null (check-runtime-unintern "(defun unintern-rows (x)
  `((:funcall #'cl:unintern ,x)
    (:funcall #'cl:unintern ,x)))"))))

  (testing "Keyword-headed apply rows in a backquoted table are silent"
    (ok (null (check-runtime-unintern "(defun unintern-rows (x)
  `((:apply #'cl:unintern ,x)
    (:apply #'cl:unintern ,x)))"))))

  ;; Known positive, so a run that reports nothing at all cannot pass as clean.
  ;; The compile-time exit only suppresses the subtree it is walking, and a
  ;; nested row is reached anyway through the enclosing form's own recursion,
  ;; so a top-level row is the case that actually discriminates here.
  (testing "A top-level :defmacro row does not take the compile-time exit"
    (let ((violations (check-runtime-unintern "(:defmacro alpha (cl:unintern sym))")))
      (ok (= 1 (length violations)))
      (ok (eq :runtime-unintern (violation:violation-rule (first violations))))))

  (testing "A real defmacro body is still skipped"
    (ok (null (check-runtime-unintern "(defmacro with-unintern (x) (cl:unintern x))")))))

;;; Registration tests

(deftest runtime-unintern-registration
  (testing ":runtime-unintern is NOT in default config"
    (let* ((cfg (mallet/config:get-built-in-config :default))
           (rule-names (mapcar #'rules:rule-name (mallet/config:config-rules cfg))))
      (ok (not (member :runtime-unintern rule-names)))))

  (testing ":runtime-unintern IS in :all config"
    (let* ((cfg (mallet/config:get-built-in-config :all))
           (rule-names (mapcar #'rules:rule-name (mallet/config:config-rules cfg))))
      (ok (member :runtime-unintern rule-names))))

  (testing ":runtime-unintern rule has :suspicious category"
    (let ((rule (rules:make-rule :runtime-unintern)))
      (ok (eq :suspicious (rules:rule-category rule))))))
