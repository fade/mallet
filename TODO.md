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

**Mechanism, from `src/rules/forms/local-functions.lisp` and
`src/rules/base.lisp`.** The recursive checker dispatches on `(first expr)` for
any cons it reaches, and `symbol-matches-p` compares the *name* only — it
verifies the string is a parser symbol and matches, with no check of the
position the form occupies. Recursion descends into binding lists, where a
binding `(labels <value-form>)` is indistinguishable from a call form, so it is
handed to `check-labels-bindings` and its value form is read as a list of local
function definitions.

Confirmed by a control set holding the value form constant and varying only the
binding name, so the name is the only free variable:

```lisp
(let* ((c (string-downcase n)) (labels   (if (string= c "") '() (list c)))) …)  ; REPORTS
(let* ((c (string-downcase n)) (flet     (if (string= c "") '() (list c)))) …)  ; REPORTS
(let* ((c (string-downcase n)) (macrolet (if (string= c "") '() (list c)))) …)  ; silent
(let* ((c (string-downcase n)) (ordinary (if (string= c "") '() (list c)))) …)  ; silent — control
```

So `flet` shares the dispatch and the defect; **`macrolet` does not**, being
absent from this rule's dispatched heads. An earlier draft claimed `macrolet`
was affected — that was inferred rather than read, and the control refutes it.

Note the value form must contain conses that can be read as definitions. A
binding named `labels` whose value is a single call such as `(list c)` does not
report, so a minimal repro needs a value form with nested call shapes.

**Impact.** Directly contradicts the acceptance criteria — this is a rule prone
to false positives on correct code. Worse, the natural response is to rename a
perfectly good variable to satisfy the linter, degrading the source to quiet a
tool bug.

**Suggested fix.** Resolve the head positionally. A binding-list entry is never
an operator form, and the checker has the context to know it is inside one.

---

## 3. `no-ignore-errors` skips `defmacro` forms entirely

**Coverage hole. Silent, and invisible to a whole-tree count.**

`src/rules/forms/no-ignore-errors.lisp` skips the whole form:

```lisp
;; DEFMACRO: skip entirely (macro expansion code, not runtime)
((form-head-name-p head "DEFMACRO")
 nil)
```

**The rationale is half right, and that is the bug.** "Macro expansion code, not
runtime" holds for the macro's *body* — code that runs at expansion time — but
not for the *expansion template*, which becomes runtime code at every call site.
A masking handler in a template is neither reported nor suppressible; it is
simply unenforced, so the gate cannot see an existing site and equally cannot
see a new one added later.

Backquote is **not** the trigger, and the distinction matters for anyone fixing
this. A control set, all in one file:

```lisp
(defmacro m (x) (ignore-errors (list x)))            ; NOT reported — no backquote involved
(defun d (x) `(foo ,(ignore-errors (list x))))       ; reported — backquote is not the test
(define-compiler-macro cm (x) (ignore-errors ...))   ; reported — does not share the hole
(defun plain (x) (ignore-errors (list x)))           ; reported — control
```

So the skip is broader than "templates" in one direction — the macro's own body
goes unchecked too — and narrower in another: `define-compiler-macro` and
`macrolet` are unaffected, and other rules descend into `defmacro` normally.

**Suggested fix.** Distinguish the macro's body from its expansion template
rather than skipping the form. The template is runtime code and should be
checked; the body arguably should not.

**No secondary detector exists.** `stale-suppression` cannot backstop this: a
suppression written inside a macro matches nothing and surfaces loudly as stale,
but the silent case is the reverse — no suppression, no violation, no signal.

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
