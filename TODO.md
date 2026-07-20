# TODO — known defects

Defects found while adopting mallet across a multi-repo Common Lisp
constellation. Each was confirmed independently by more than one repository, and
each is measured against mallet's own acceptance criteria in `CLAUDE.md`: rules
must report only definite, unambiguous issues and must not be prone to false
positives.

Repros are minimal and run on the default configuration unless noted. Rule
sources are cited by file, not line, so the references survive the fixes.

---

## 1. `error-without-custom-condition` misses any message containing a colon

**False negative. The rule is blinded by ordinary message hygiene.**

`src/rules/forms/error-usage.lisp` tests the first argument with, in effect,
`(and (stringp arg) (not (find #\: arg)))`. The colon test is there to
distinguish a genuine string literal from a parser-produced symbol string —
the parser represents symbols as strings carrying a package prefix, such as
`"CL:error"` or `"CURRENT:foo"`. But it is applied to real message strings too,
so any message written as `"subsystem: what went wrong"` is misclassified as a
symbol reference and silently skipped.

```lisp
(defun a () (error "plain message no colon"))   ; reported
(defun b () (error "formatted ~S here" 1))      ; reported — format args are not the test
(defun c () (error "prefix: message"))          ; SILENT
(defun d () (error "prefix: formatted ~S" 1))   ; SILENT
```

**Impact.** The more consistently a codebase prefixes its error messages, the
less the rule sees, so a well-kept tree reads as clean while being maximally
indebted. Measured across five repositories, every reported count was a small
fraction of the real surface — in one, 13 reported against 77 sites, with 65
invisible. Every repository's number was explained by this one mechanism.

A second consequence is worse than the miss itself: a count this unreliable
invites a promotion gate ("raise to `:warning` once the count reaches zero")
that can never be satisfied honestly, and it tempts a reader who understands the
mechanism to strip message prefixes to move the number — trading real diagnostic
quality for a linter artifact.

**Suggested fix.** Distinguish a literal from a parser-produced symbol using the
parser's own representation rather than by scanning the string for a colon. The
parser already knows which it produced; the information does not need to be
recovered heuristically. Compatible with file-based analysis.

---

## 2. A binding named `labels` is misparsed as a `LABELS` form

**False positive. Reports real code as defective.**

A `let*` binding whose name collides with a special-operator name is treated as
that operator, and the surrounding forms are then analysed as local function
definitions.

```lisp
(let* ((canonical (string-downcase name))
       (labels (if (string= canonical "") '() (split canonical))))
  labels)
```

`unused-local-functions` reports `split` and `string=` as unused local
functions. Neither is a local function; there is no `labels` form here.

The misparse is not specific to any particular operators: whatever appears in
the binding's value form gets reported. Two independent repros of this case
flagged different pairs — `split`/`string=` and `list`/`string=` — according to
what each happened to call there.

**Impact.** Directly contradicts the acceptance criteria — this is a rule prone
to false positives on correct code. Worse, the natural response is to rename a
perfectly good variable to satisfy the linter, degrading the source to quiet a
tool bug. `flet` and `macrolet` should be checked for the same collision.

**Suggested fix.** Resolve the head symbol positionally — a binding name in a
binding list is never an operator — rather than by name alone.

---

## 3. `no-ignore-errors` does not descend into backquoted macro templates

**Coverage hole. Silent, and invisible to a whole-tree count.**

A masking handler written inside a `defmacro` expansion template is neither
reported nor suppressible. It is simply unenforced, so the gate cannot see an
existing site and equally cannot see a new one added there later.

```lisp
(defmacro with-thing ((var) &body body)
  `(let ((,var (acquire)))
     (unwind-protect (progn ,@body)
       (ignore-errors (release ,var)))))   ; never reported
```

**Impact.** Test scaffolding is where this concentrates — setup and teardown
wrapped in a `with-…` macro is both where masking accumulates and where it is
least often reviewed. One repository measured 466 masks against 394 reported:
seventy-two invisible across twenty-six files, all in test support.

**Detecting it requires a per-file comparison.** A whole-tree total hides the gap
behind offsetting differences and reads as clean; one repository's aggregate was
48 against 50, a delta small enough to look like rounding while localising two
real blind sites. Compare `(ignore-errors` counts against reported counts per
file, not in aggregate.

Note also that planting a probe violation in ordinary top-level code proves only
that the *file* is linted. It says nothing about template coverage; a probe
inside a backquote is needed to claim that.

**Suggested fix.** Descend into backquote templates when collecting forms.
Unquoted fragments (`,x`, `,@xs`) are opaque and should stay so, but the literal
skeleton is ordinary code and is where these handlers live.

---

## Note on all three

None of these should be worked around in the analysed source. Renaming a
variable, stripping a message prefix, or restructuring a macro to make its
cleanup visible all degrade real code to satisfy a tool defect — and each leaves
the tree worse while making a number look better. The fixes belong here.
