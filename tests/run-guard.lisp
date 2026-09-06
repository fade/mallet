(defpackage #:mallet/tests/run-guard
  (:use #:cl)
  (:local-nicknames
   (#:suite #:rove/core/suite/package))
  (:export #:run-guarded)
  (:documentation "Refuse to call a test run successful when it executed nothing."))

(in-package #:mallet/tests/run-guard)

(define-condition no-tests-invoked (error)
  ((suite-count
    :initarg :suite-count
    :reader suite-count
    :type integer
    :documentation "How many suites were registered when the run started.")
   (test-count
    :initarg :test-count
    :reader test-count
    :type integer
    :documentation "How many tests were registered when the run started."))
  (:documentation "Signalled when a finished test run entered no test body at all.")
  (:report
   (lambda (condition stream)
     (if (zerop (test-count condition))
         (format stream
                 "The test run finished without entering a single test body, ~
                  because no test was registered to begin with: the registry ~
                  held ~D suite~:P and no tests at all. Whatever the summary ~
                  said, nothing was checked.~2%~
                  Look at how the tests get discovered and loaded rather ~
                  than at how they get run. Every test file the system names ~
                  has to be loaded before the run, and each one has to reach ~
                  its deftest forms, so a file missing from the component ~
                  list or a load that stopped early on an error leaves the ~
                  registry as empty as this."
                 (suite-count condition))
         (format stream
                 "The test run finished without entering a single test body, ~
                  although ~D test~:P across ~D suite~:P were registered. ~
                  Whatever the summary said, nothing was checked.~2%~
                  The cause seen so far is a pair of conditions together: ~
                  ASDF_OUTPUT_TRANSLATIONS is set, so compiled output lands ~
                  away from the sources, and the rove that got loaded ~
                  predates the fix that stopped it keying its ~
                  file-to-package table on the compiled path. Start there: ~
                  either update rove, or run the tests with ~
                  ASDF_OUTPUT_TRANSLATIONS unset. If neither applies, the ~
                  question to answer is what the runner matched the ~
                  registered suites against."
                 (test-count condition)
                 (suite-count condition))))))

(defun registered-test-symbols ()
  "Return the symbol naming every test rove currently has registered, across all suites."
  (loop for suite in (suite:all-suites)
        append (suite:suite-tests suite)))

(defun set-test-function (name function)
  "Install FUNCTION as the body rove runs for the test named NAME.

Rove files a test under the suite belonging to the current package, so NAME's
own package is made current here: re-registering an existing test must not
move it into whichever package happens to be current at the time."
  (let ((*package* (symbol-package name)))
    (suite:set-test name function)))

(defun run-guarded (system)
  "Run SYSTEM's tests and signal an error if not one test body was entered.

A runner that silently skips every test is worse than one that fails: it
reports success and hides whatever broke. The only trustworthy evidence that
tests ran is the tests themselves being entered, so that is what decides here
rather than the run's own summary. Reported test failures are left alone and
returned as usual."
  (let ((names (registered-test-symbols))
        (suite-count (length (suite:all-suites)))
        (entered 0)
        (originals '()))
    (unwind-protect
         (progn
           (dolist (name names)
             (let ((original (suite:get-test name)))
               (when (functionp original)
                 (push (cons name original) originals)
                 (set-test-function name
                                    (lambda (&rest arguments)
                                      (incf entered)
                                      (apply original arguments))))))
           (let ((result (rove:run system)))
             (when (zerop entered)
               (error 'no-tests-invoked
                      :suite-count suite-count
                      :test-count (length names)))
             result))
      (loop for (name . original) in originals
            do (set-test-function name original)))))
