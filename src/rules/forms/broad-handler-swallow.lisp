(defpackage #:mallet/rules/forms/broad-handler-swallow
  (:use #:cl)
  (:local-nicknames
   (#:a #:alexandria)
   (#:base #:mallet/rules/base)
   (#:parser #:mallet/parser)
   (#:violation #:mallet/violation))
  (:import-from #:mallet/rules/base
                #:form-head-name-p)
  (:export #:broad-handler-swallow-rule))
(in-package #:mallet/rules/forms/broad-handler-swallow)

;;; Broad-handler-swallow rule

(defclass broad-handler-swallow-rule (base:rule)
  ()
  (:default-initargs
   :name :broad-handler-swallow
   :description "A blanket handler clause must bind and use the condition, or signal one"
   :severity :warning
   :category :suspicious
   :type :form)
  (:documentation "Rule to detect handler-case clauses that catch everything and then
destroy the condition, plus every use of ignore-errors.

A clause whose type specifier is ERROR, T, CONDITION or SERIOUS-CONDITION cannot
discriminate between the failure it anticipated and one it did not. Such a clause is
only defensible when the condition survives it: either the clause binds the condition
and its body uses that binding, or the clause's normal exit is a call to ERROR, SIGNAL
or CERROR. Anything else leaves the caller with no way to learn what went wrong."))

(defparameter *blanket-typespecs*
  '("ERROR" "T" "CONDITION" "SERIOUS-CONDITION")
  "Type specifiers that name a handler clause too broad to discriminate.")

(defparameter *signalling-operators*
  '("ERROR" "SIGNAL" "CERROR")
  "Operators whose call preserves a condition for someone downstream.")

(defconstant +max-tail-depth+ 32
  "Bound on how far tail resolution walks through nested PROGN, WHEN and UNLESS.")

(defconstant +max-reference-depth+ 128
  "Bound on how deep the search for a bound-variable reference descends.")

(defun symbol-string-name (expr)
  "Return the bare symbol name EXPR denotes, or NIL when EXPR is not a symbol."
  (typecase expr
    (string (base:symbol-name-from-string expr))
    (symbol (symbol-name expr))
    (otherwise nil)))

(defun quote-form-p (expr)
  "Check if EXPR is a QUOTE form, whose contents are data rather than code."
  (and (consp expr)
       (let ((head (first expr)))
         (or (eq head 'quote)
             (form-head-name-p head "QUOTE")))))

(defun references-symbol-p (expr name)
  "Check whether EXPR mentions the symbol named NAME anywhere outside quoted data.
String literals are not symbol references, so only package-qualified symbol strings
count as a mention."
  (labels ((walk (current depth)
             (cond
               ((> depth +max-reference-depth+) nil)
               ((stringp current) (base:symbol-matches-p current name))
               ((and current (symbolp current))
                (string-equal (symbol-name current) name))
               ((consp current)
                (unless (quote-form-p current)
                  (loop for rest on current
                        while (consp rest)
                        thereis (walk (car rest) (1+ depth)))))
               (t nil))))
    (and name (walk expr 0))))

(defun resolve-tail-form (form depth)
  "Resolve the form a body reaches on its normal exit.
Sees through PROGN and through the body of WHEN and UNLESS, and nothing else. A local
function binding is deliberately not followed: a call into an FLET or LABELS binding
tells us nothing about whether that binding signals or merely returns a value."
  (if (or (> depth +max-tail-depth+)
          (not (consp form))
          (not (a:proper-list-p form)))
      form
      (let ((head (first form)))
        (cond
          ((form-head-name-p head "PROGN")
           (let ((body (rest form)))
             (if body
                 (resolve-tail-form (car (last body)) (1+ depth))
                 form)))

          ((or (form-head-name-p head "WHEN")
               (form-head-name-p head "UNLESS"))
           (let ((body (cddr form)))
             (if body
                 (resolve-tail-form (car (last body)) (1+ depth))
                 form)))

          (t form)))))

(defun signalling-form-p (form)
  "Check whether FORM is a call to ERROR, SIGNAL or CERROR."
  (and (consp form)
       (let ((head (first form)))
         (some (lambda (name) (form-head-name-p head name))
               *signalling-operators*))))

(defun no-error-clause-p (clause)
  "Check whether CLAUSE is the :NO-ERROR clause, which handles nothing."
  (and (consp clause)
       (base:symbol-matches-p (first clause) "NO-ERROR")))

(defun blanket-clause-p (clause)
  "Check whether CLAUSE catches so broadly that it cannot discriminate.
A compound type specifier such as (OR ...) names the failures it expects, so it is
never blanket."
  (and (consp clause)
       (a:proper-list-p clause)
       (not (no-error-clause-p clause))
       (let ((typespec (first clause)))
         (some (lambda (name) (form-head-name-p typespec name))
               *blanket-typespecs*))))

(defun clause-preserves-condition-p (clause)
  "Check whether CLAUSE keeps the condition available to someone downstream.
Either the clause binds the condition and its body uses that binding, or the body's
normal exit signals. A RETURN-FROM or THROW carrying a value is not a signal and does
not count."
  (let* ((varlist (second clause))
         (body (cddr clause))
         (variable (and (consp varlist) (first varlist))))
    (or (and variable
             (references-symbol-p body (symbol-string-name variable)))
        (and body
             (a:proper-list-p body)
             (signalling-form-p (resolve-tail-form (car (last body)) 0))))))

(defun swallowing-clause-p (clause)
  "Check whether CLAUSE is blanket and destroys the condition it catches."
  (and (blanket-clause-p clause)
       (not (clause-preserves-condition-p clause))))

(defmethod base:check-form ((rule broad-handler-swallow-rule) form file)
  "Check for blanket handler clauses that discard the condition."
  (check-type form parser:form)
  (check-type file pathname)

  (base:check-form-recursive rule
                             (parser:form-expr form)
                             file
                             (parser:form-line form)
                             (parser:form-column form)
                             nil
                             (parser:form-position-map form)))

(defmethod base:check-form-recursive
    ((rule broad-handler-swallow-rule) expr file line column
     &optional function-name position-map)
  "Recursively check for condition-destroying handlers."
  (declare (ignore function-name))

  (let ((violations '())
        (visited (make-hash-table :test 'eq)))

    (labels ((make-violation (actual-line actual-column message)
               (make-instance 'violation:violation
                              :rule :broad-handler-swallow
                              :file file
                              :line actual-line
                              :column actual-column
                              :severity (base:rule-severity rule)
                              :message message
                              :fix nil))

             (clause-violations (current-expr fallback-line fallback-column)
               (loop for clause in (cddr current-expr)
                     when (and (swallowing-clause-p clause)
                               (base:should-create-violation-p rule))
                       collect (multiple-value-bind (clause-line clause-column)
                                   (base:find-actual-position
                                    clause position-map fallback-line fallback-column)
                                 (make-violation
                                  clause-line clause-column
                                  "Blanket handler clause discards the condition; bind and use it, or signal a typed condition"))))

             (check-expr (current-expr fallback-line fallback-column)
               (base:with-safe-code-expr (current-expr visited)
                 (multiple-value-bind (actual-line actual-column)
                     (base:find-actual-position
                      current-expr position-map fallback-line fallback-column)
                   (let ((head (first current-expr))
                         (rest-args (rest current-expr)))
                     (cond
                       ;; DEFMACRO: skip entirely (macro expansion code, not runtime)
                       ((form-head-name-p head "DEFMACRO")
                        nil)

                       (t
                        ;; ignore-errors binds nothing and signals nothing, so it
                        ;; destroys every condition it catches by construction.
                        (when (and (form-head-name-p head "IGNORE-ERRORS")
                                   (base:should-create-violation-p rule))
                          (a:nconcf violations
                                    (list (make-violation
                                           actual-line actual-column
                                           "ignore-errors discards the condition; use a handler clause that binds and uses it, or signals a typed condition"))))

                        (when (form-head-name-p head "HANDLER-CASE")
                          (a:nconcf violations
                                    (clause-violations current-expr
                                                       actual-line actual-column)))

                        ;; Recurse into subexpressions
                        (a:nconcf violations
                                  (base:collect-violations-from-subexprs
                                   rule head file actual-line actual-column
                                   position-map))
                        (a:nconcf violations
                                  (base:collect-violations-from-subexprs
                                   rule rest-args file actual-line actual-column
                                   position-map)))))))))

      (check-expr expr line column))

    violations))
