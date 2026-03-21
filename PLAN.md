# REPL Control Skill Plan

## Goal
Build a cross-platform single-file `repl.cmd` helper that manages a local REPL per working directory without network sockets.

## UX
- `repl.cmd start -- <cmd...>`
- `repl.cmd eval "<form>"`
- `echo "<form>" | repl.cmd eval`
- `repl.cmd stop`
- `repl.cmd status`
- help flags: `repl.cmd -h`, `repl.cmd -?`, `repl.cmd --help`
- `eval` has a `--timeout <seconds>` option; default is 5 seconds
- commands always target the REPL associated with the exact current working directory

## Constraints
- Windows, macOS, and Linux
- no TCP
- `clj` / `lein` agnostic
- shell-only runtime implementation; tests may require Python only in CI/dev
- one polyglot script with Windows and POSIX branches
- exact help/usage output across Windows and POSIX entrypoints

## Architecture
Start a detached REPL process directly and manage it with a lightweight local session registry.

- `repl.cmd start` launches the target REPL as a detached child with redirected `stdin` / `stdout` / `stderr`
- `repl.cmd` stores session state in `<cwd>/.repl.cmd/`
- one detached REPL session exists per exact working directory
- `start` bootstraps `.repl.cmd/` and writes `.repl.cmd/.gitignore` automatically
- `repl.cmd` stores session metadata locally: pid, cwd, command, started_at, transport paths, and status
- `eval` writes to the session input, sends marker forms before and after eval, then waits for explicit end markers
- output is captured in shell-friendly files so later commands can reconnect without a broker
- `stop` and cleanup operate from the stored session metadata

## Protocol Sketch
- state dir: `<cwd>/.repl.cmd/`
- `.repl.cmd/.gitignore` contents: `*`
- request file: id, op (`eval` / `stop` / `status`), payload, timeout, timestamp
- response file: id, status, stdout, stderr, value or error summary
- prefer plain text over JSON for shell friendliness
- session status is `stopped`, `starting`, `running`, or `busy`

## Open Problems
- concurrent eval protection, crash cleanup, timeout enforcement, and stale session recovery
