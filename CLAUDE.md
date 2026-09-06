# CLAUDE.md

## Project Overview

Mallet is a linter for Common Lisp (SBCL only). Key constraint: **file-based analysis only** — does not load/compile systems, just analyzes source text. Do not propose implementations that require system loading.

Rule classification criteria are in `docs/rule-classification.md`.

## Design Philosophy

Rules must report only definite, unambiguous issues. No subjective style preferences.

**Rule acceptance criteria:**
- Prevents runtime errors or bugs
- Enforces CL best practices with clear rationale
- Detects likely mistakes or anti-patterns
- NOT: subjective preferences, "how I like it" rules, or rules prone to false positives

## Development Commands

```bash
./bin/mallet .                                # Lint (must pass with zero violations)
./bin/mallet --fix .                          # Auto-fix violations

# init.lisp bootstraps the bundled dependencies, the same way the build does.
sbcl --noinform --non-interactive --load init.lisp \
  --eval '(asdf:test-system "mallet")'        # Run all tests
sbcl --noinform --non-interactive --load init.lisp \
  --eval '(asdf:load-system "mallet/tests")' \
  --eval '(rove:run-suite :mallet/tests/rules/<name>)'  # Run one test suite
command make                                  # Build standalone executable
```

Two things to know before you trust a test result:

- **Leave `ASDF_OUTPUT_TRANSLATIONS` unset for the test commands.** Setting it sends compiled
  output away from the sources, and a rove predating the fix for that keys its file-to-package
  table on the compiled path, so it discovers no tests and the run reports success having executed
  none. `test-system` now fails loudly instead of reporting that green, but the tests still do not
  run, so you get no coverage either way.
- **`test-system` exits 0 even when tests fail.** Read the summary rather than the exit status, or
  check the failure count yourself if you are wiring this into anything automated.


## ASDF Gotcha

Module names must be unique. When a file and directory share a name, use `:pathname`:
```lisp
(:module "parser-impl" :pathname "parser" :components ...)
```

## Adding New Rules

Every rule needs: (1) unit tests, (2) CLI fixture tests, (3) registration.

### 1. Unit Tests
Create `tests/rules/<rule-name>-test.lisp` (see existing tests for pattern). Add to `mallet.asd`.

### 2. CLI Fixture Tests
- `tests/fixtures/violations/<rule-name>.lisp` — code that triggers violations
- `tests/fixtures/violations/<rule-name>.expected` — expected output:
  ```
  # Format: line:column rule-name severity
  10:0 rule-name warning
  ```
- Optionally: `tests/fixtures/clean/<rule-name>.lisp` — valid code

### 3. Register
- Add case to `make-rule` in `src/rules.lisp`
- Add to preset lists in `src/config.lisp` (`make-default-config` and/or `make-all-config`)
- Export rule class from `src/rules.lisp`

### CLI Option Precedence (highest to lowest)
1. `--enable RULE:option=value`
2. `--disable RULE`
3. `--preset` / `--all` / `--none` (CLI)
4. Config file `:enable` / `:disable`
5. Config file `:extends`
6. Default preset
