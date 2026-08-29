(defpackage #:mallet/tests/rules/broad-handler-swallow
  (:use #:cl
        #:rove)
  (:local-nicknames
   (#:rules #:mallet/rules)
   (#:parser #:mallet/parser)
   (#:violation #:mallet/violation)))
(in-package #:mallet/tests/rules/broad-handler-swallow)

;;; Helper

(defun check-broad-handler (code)
  (let ((forms (parser:parse-forms code #p"test.lisp"))
        (rule (make-instance 'rules:broad-handler-swallow-rule)))
    (mapcan (lambda (form)
              (rules:check-form rule form #p"test.lisp"))
            forms)))

;;; Known positive
;;;
;;; Every test set below opens with a case that must report. A silent cell only
;;; means "no violation" once something in the same run has proved the harness
;;; reached the rule at all.

(defparameter *known-positive*
  "(handler-case (write-frame ep msg) (error () nil))"
  "The plainest swallow there is. If this reports nothing, the run is broken.")

;;; Blanket clauses that destroy the condition

(deftest blanket-clause-swallow
  (testing "Known positive: blanket clause returning nil"
    (let ((violations (check-broad-handler *known-positive*)))
      (ok (= (length violations) 1))
      (ok (eq (violation:violation-rule (first violations)) :broad-handler-swallow))
      (ok (eq (violation:violation-severity (first violations)) :warning))))

  (testing "Blanket clause returning a fallback value"
    (ok (= 1 (length (check-broad-handler
                      "(handler-case (sb-ext:octets-to-string octets :external-format :utf-8)
                         (error () (map 'string #'code-char octets)))")))))

  (testing "Blanket clause with a multi-form body that never signals"
    (ok (= 1 (length (check-broad-handler
                      "(handler-case (noise-xx-advance node data)
                         (error () (setf (foo node) :failed) (setf (bar node) nil)))")))))

  (testing "Blanket clause whose body calls a local function that returns"
    (ok (= 1 (length (check-broad-handler
                      "(defun transfer (stream)
                         (flet ((fail (reason) (return-from transfer reason)))
                           (handler-case (loop for chunk = (read-chunk stream)
                                               while chunk do (consume chunk))
                             (error () (fail :transfer-incomplete)))))")))))

  (testing "Blanket clause that binds the condition but never uses it"
    (ok (= 1 (length (check-broad-handler
                      "(handler-case (risky) (error (c) (log-failure :unknown)))")))))

  (testing "CONDITION is blanket"
    (ok (= 1 (length (check-broad-handler "(handler-case (x) (condition () nil))")))))

  (testing "SERIOUS-CONDITION is blanket"
    (ok (= 1 (length (check-broad-handler
                      "(handler-case (x) (serious-condition () nil))")))))

  (testing "T is blanket"
    (ok (= 1 (length (check-broad-handler "(handler-case (x) (t () nil))")))))

  (testing "RETURN-FROM in tail position is not a signal"
    (ok (= 1 (length (check-broad-handler
                      "(defun run (x) (handler-case (go-fast x) (error () (return-from run :slow))))")))))

  (testing "THROW in tail position is not a signal"
    (ok (= 1 (length (check-broad-handler
                      "(handler-case (go-fast x) (error () (throw 'done :slow)))")))))

  (testing "One blanket clause among specific ones still reports"
    (let ((violations (check-broad-handler
                       "(handler-case (open-stream ep)
                          (tls-certificate-error (c) (reject c))
                          (error () nil))")))
      (ok (= (length violations) 1))))

  (testing "Two blanket clauses report twice"
    (ok (= 2 (length (check-broad-handler
                      "(handler-case (x) (error () nil) (condition () :fallback))"))))))

;;; ignore-errors

(deftest broad-handler-ignore-errors
  (testing "Known positive: blanket clause returning nil"
    (ok (= 1 (length (check-broad-handler *known-positive*)))))

  (testing "Plain ignore-errors reports"
    (let ((violations (check-broad-handler "(ignore-errors (ari-suggested-renewal endpoint))")))
      (ok (= (length violations) 1))
      (ok (eq (violation:violation-rule (first violations)) :broad-handler-swallow))
      (ok (search "ignore-errors" (violation:violation-message (first violations))))))

  (testing "ignore-errors nested in a function reports"
    (ok (= 1 (length (check-broad-handler
                      "(defun renew (endpoint) (ignore-errors (ari-suggested-renewal endpoint)))")))))

  (testing "ignore-errors inside defmacro is skipped"
    (ok (null (check-broad-handler
               "(defmacro safe-call (form) `(ignore-errors ,form))")))))

;;; Clauses that keep the condition available

(deftest blanket-clause-preserved-condition
  (testing "Known positive: blanket clause returning nil"
    (ok (= 1 (length (check-broad-handler *known-positive*)))))

  (testing "Binds the condition and passes it on"
    (ok (null (check-broad-handler
               "(handler-case (%run-reply-reader session)
                  (error (c) (%drain-outstanding-with-error session c)))"))))

  (testing "Binds the condition and re-signals a typed one"
    (ok (null (check-broad-handler
               "(handler-case (progn (load-config) (start-listeners))
                  (error (e) (error 'acme-boot-error :message (princ-to-string e))))"))))

  (testing "Binds nothing but the tail signals"
    (ok (null (check-broad-handler
               "(handler-case (funcall gf provider)
                  (error () (error 'probe-wire-provider-refused
                                   :seam seam :reason :absent-op)))"))))

  (testing "Tail signal reached through progn"
    (ok (null (check-broad-handler
               "(handler-case (x)
                  (error () (progn (record-attempt) (signal 'retry-exhausted))))"))))

  (testing "Tail signal reached through when"
    (ok (null (check-broad-handler
               "(handler-case (x)
                  (error () (when *strict* (cerror \"Continue\" 'probe-failed))))"))))

  (testing "Tail SIGNAL exempts"
    (ok (null (check-broad-handler "(handler-case (x) (error () (signal 'gave-up)))"))))

  (testing "Bound variable used only deep inside the body still exempts"
    (ok (null (check-broad-handler
               "(handler-case (x)
                  (error (c) (let ((m (list :because (princ-to-string c)))) (report m))))")))))

;;; Clauses too specific to reach the test

(deftest specific-clause-never-reported
  (testing "Known positive: blanket clause returning nil"
    (ok (= 1 (length (check-broad-handler *known-positive*)))))

  (testing "A single specific type is never blanket"
    (ok (null (check-broad-handler
               "(handler-case (parse-integer text) (parse-error () (values nil 0)))"))))

  (testing "Four specific clauses, none blanket"
    (ok (null (check-broad-handler
               "(handler-case (tls-handshake conn)
                  (tls-certificate-error () :bad-cert)
                  (tls-context-cancelled () :cancelled)
                  (tls-deadline-exceeded () :timeout)
                  (tls-error () :failed))"))))

  (testing "A compound (or ...) type specifier is not blanket"
    (ok (null (check-broad-handler
               "(handler-case (x) ((or error warning) () nil))"))))

  (testing ":no-error clauses are skipped"
    (ok (null (check-broad-handler
               "(handler-case (parse-integer text)
                  (parse-error () (values nil 0))
                  (:no-error (v p) (values v p)))"))))

  (testing "handler-case with no clauses at all"
    (ok (null (check-broad-handler "(handler-case (x))"))))

  (testing "A string literal naming a blanket type is not code"
    (ok (null (check-broad-handler
               "(defun doc () \"A handler-case (error () nil) swallows the condition.\")")))))

;;; Rule metadata

(deftest broad-handler-swallow-metadata
  (testing "Rule has :suspicious category"
    (let ((rule (make-instance 'rules:broad-handler-swallow-rule)))
      (ok (eq (rules:rule-category rule) :suspicious))))

  (testing "Rule has :warning severity"
    (let ((rule (make-instance 'rules:broad-handler-swallow-rule)))
      (ok (eq (rules:rule-severity rule) :warning))))

  (testing "Rule is a form rule"
    (let ((rule (make-instance 'rules:broad-handler-swallow-rule)))
      (ok (eq (rules:rule-type rule) :form)))))

;;; Registration

(deftest broad-handler-swallow-registration
  (testing ":broad-handler-swallow is in default config"
    (let* ((cfg (mallet/config:get-built-in-config :default))
           (rule-names (mapcar #'rules:rule-name (mallet/config:config-rules cfg))))
      (ok (member :broad-handler-swallow rule-names))))

  (testing ":broad-handler-swallow is in :all config"
    (let* ((cfg (mallet/config:get-built-in-config :all))
           (rule-names (mapcar #'rules:rule-name (mallet/config:config-rules cfg))))
      (ok (member :broad-handler-swallow rule-names))))

  (testing "make-rule builds the rule with :suspicious category"
    (let ((rule (rules:make-rule :broad-handler-swallow)))
      (ok (eq :suspicious (rules:rule-category rule))))))
