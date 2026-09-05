(defsystem "mallet"
  :version "0.9.2"
  :description "A sensible Common Lisp linter that catches mistakes, not style"
  :author "Eitaro Fukamachi <e.arrows@gmail.com>"
  :license "MIT"
  :depends-on ("alexandria"
               "cl-interpol"
               "cl-ppcre"
               "eclector"
               (:feature :sbcl "sb-posix")
               "trivial-glob")
  :in-order-to ((test-op (test-op "mallet/tests"))
                (program-op (program-op "mallet/executable")))
  :pathname "src"
  :serial t
  :components
  (;; Shared utilities
   (:file "utils")
   (:file "utils/scope")

   ;; Error conditions
   (:file "errors")

   ;; Core data structures
   (:file "violation")
   (:file "suppression")
   (:file "parser")

   ;; Parsing implementations
   (:module "parser-impl"
    :pathname "parser"
    :components
    ((:file "text")
     (:file "tokenizer")
     (:file "reader")
     (:file "loop")))

   ;; Rule system
   (:module "rules-impl"
    :pathname "rules"
    :serial t
    :components
    ((:file "base")
     (:file "coalton-base")
     (:file "text")
     (:file "forms/package-exports")
     (:module "tokens"
      :pathname "tokens"
      :components
      ((:file "bare-float-literal")
       (:file "double-colon-access")))
     (:module "forms"
      :pathname "forms"
      :components
      ((:file "control-flow")
       (:file "variables")
       (:file "local-functions")
       (:file "package")
       (:file "naming")
       (:file "lambda-list")
       (:file "asdf")
       (:file "asdf-defsystem")
       (:file "metrics")
       (:file "no-eval")
       (:file "runtime-intern")
       (:file "runtime-unintern")
       (:file "no-ignore-errors")
       (:file "broad-handler-swallow")
       (:file "error-usage")
       (:file "docstring")
       (:file "coalton")
       (:file "coalton-to-boolean")))
     (:file "stale-suppression")
     (:file "asdf-reader-conditional")))
   (:file "rules")

   ;; Configuration
   (:file "config")

   ;; Linting engine and formatters
   (:file "engine")
   (:file "formatter")
   (:file "fixer")
   (:file "init")

   (:file "main")))

(defun mallet-build-identity ()
  "Return the commit the mallet source tree is at and whether it has been edited.

The first value is a short commit string, or :UNKNOWN when git is absent, the
tree is not a repository, or the call failed. The second is :CLEAN, :DIRTY or
:UNKNOWN, counting tracked files only. Neither value is ever NIL, because NIL in
the built image means no build identity was recorded at all."
  (let ((root (native-namestring (system-source-directory "mallet"))))
    (flet ((git (&rest arguments)
             (handler-case
                 (multiple-value-bind (output error-output code)
                     (run-program (list* "git" "-C" root arguments)
                                  :output '(:string :stripped t)
                                  :error-output nil
                                  :ignore-error-status t)
                   (declare (ignore error-output))
                   (and (eql code 0) output))
               (error (condition)
                 (format *error-output*
                         "mallet: cannot run git for build identity: ~A~%"
                         condition)
                 nil))))
      (let ((commit (git "rev-parse" "--short" "HEAD")))
        (if (and commit (plusp (length commit)))
            (let ((status (git "status" "--porcelain" "-uno")))
              (values commit
                      (cond ((null status) :unknown)
                            ((plusp (length status)) :dirty)
                            (t :clean))))
            (values :unknown :unknown))))))

(defsystem "mallet/executable"
  :description "Executable build target for Mallet. Depends on flexi-streams so that cl-unicode's build-time subsystem is resolvable in bundled (no-Quicklisp) environments."
  :depends-on ("mallet"
               "flexi-streams")
  :build-operation "program-op"
  :build-pathname "mallet"
  :entry-point "mallet:main"
  ;; ASDF's program-op on SBCL calls uiop:dump-image without compression.
  ;; Override perform so the released binary uses zstd core compression
  ;; (~5x smaller). The :before method on program-op still runs and sets
  ;; *image-entry-point* from :entry-point above.
  :perform (program-op (op c)
            ;; Stamp the commit into the image being dumped. This runs in the
            ;; building image, so the value is read now; written into a source
            ;; file with a #. it would freeze when that file was compiled and
            ;; then go stale without ever saying so.
            (handler-case
                (multiple-value-bind (commit dirty) (mallet-build-identity)
                  (setf (symbol-value (find-symbol "*BUILD-COMMIT*" "MALLET"))
                        commit)
                  (setf (symbol-value (find-symbol "*BUILD-DIRTY*" "MALLET"))
                        dirty))
              (error (condition)
                (format *error-output*
                        "mallet: build identity not recorded: ~A~%"
                        condition)))
            (uiop:dump-image (asdf:output-file op c)
                             :executable t
                             #+sb-core-compression :compression
                             #+sb-core-compression t)))

(defsystem "mallet/tests"
  :depends-on ("mallet"
               "yason"
               "cl-ppcre"
               "rove")
  :pathname "tests"
  :serial t
  :components
  ((:file "errors-test")
   (:file "utils-test")
   (:file "config-test")
   (:file "config-directives-test")
   (:file "config-ignore-test")
   (:file "cli-parsing-test")
   (:file "fixer-test")
   (:file "fixer-robustness-test")
   (:file "fixer-dedup-test")
   (:file "formatter-test")
   (:file "suppression")
   (:file "suppression-declarations")
   (:file "suppression-integration")
   (:file "comment-directives")
   (:file "engine-comment-suppression")
   (:file "engine-cross-file-integration-test")
   (:file "engine-unreadable-file-test")
   (:file "init-test")
   (:file "engine-coalton-lisp-test")
   (:file "engine-coalton-lisp-dispatch-test")
   (:file "engine-coalton-lisp-fixture-test")
   (:file "preset-integration-test")
   (:file "list-rules-test")
   (:file "format-stream-separation-test")
   (:file "public-api-docstrings-test")
   (:file "redundant-stub-guard-test")
   (:file "docstring-test-utils")
   (:file "test-quality-regression-test")

   (:module "parser"
    :pathname "parser"
    :components
    ((:file "tokenizer-test")
     (:file "reader-test")
     (:file "loop-test")
     (:file "unknown-reader-macros")
     (:file "read-eval-security")
     (:file "deep-nesting-test")))

   (:module "rules"
    :pathname "rules"
    :components
    ((:file "line-length-test")
     (:file "if-without-else-test")
     (:file "progn-in-conditional-test")
     (:file "redundant-progn-test")
     (:file "missing-otherwise-test")
     (:file "wrong-otherwise-test")
     (:file "unused-variables-test")
     (:file "needless-let-star-test")
     (:file "unused-local-nicknames-test")
     (:file "interned-package-symbol-test")
     (:file "unused-imported-symbols-test")
     (:file "text-formatting-test")
     (:file "closing-paren-on-own-line-test")
     (:file "naming")
     (:file "lambda-list")
     (:file "asdf")
     (:file "asdf-defsystem-test")
     (:file "asdf-reader-conditional-test")
     (:file "special-forms-test")
     (:file "with-macros-test")
     (:file "metrics-test")
     (:file "bare-float-literal-test")
     (:file "no-eval-test")
     (:file "runtime-intern-test")
     (:file "runtime-unintern-test")
     (:file "no-ignore-errors-test")
     (:file "broad-handler-swallow-test")
     (:file "no-package-use-test")
     (:file "double-colon-access-test")
     (:file "test-framework-detection-test")
     (:file "error-without-custom-condition-test")
     (:file "docstring-utilities-test")
     (:file "missing-docstring-test")
     (:file "missing-package-docstring-test")
     (:file "missing-variable-docstring-test")
     (:file "missing-struct-docstring-test")
     (:file "one-package-per-file-test")
     (:file "rule-type-system-test")
     (:file "stale-suppression-test")
     (:file "package-exports-test")
     (:file "coalton-base-test")
     (:file "coalton-rule-base-test")
     (:file "coalton-missing-declare-test")
     (:file "coalton-missing-to-boolean-test")
     (:file "coalton-cyclomatic-complexity-test"))))

  :perform (test-op (o c) (symbol-call :rove '#:run c)))
