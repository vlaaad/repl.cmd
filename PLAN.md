# REPL Control Skill Plan

## Goal
Build a cross-platform `repl.cmd` helper that manages a local REPL without network sockets.

## UX
- `repl.cmd start -- <cmd...>`
- `repl.cmd eval "<form>"`
- `repl.cmd stop`
- optional `repl.cmd status`

## Constraints
- Windows, macOS, and Linux
- no TCP
- `clj` / `lein` agnostic
- shell-only runtime implementation; tests may require Python in CI/dev
- one polyglot script with Windows and POSIX branches

## Architecture
Use a persistent broker process plus file-based IPC.

- `repl.cmd` launches the broker and writes request files
- broker starts the target REPL with redirected `stdin` / `stdout` / `stderr`
- broker sends wrapped forms to the REPL and waits for explicit end markers
- broker writes shell-friendly response files
- broker handles shutdown and cleanup

## Why This Approach
- redirected stdio is portable; console injection is fragile and Windows-specific
- file IPC is simpler and more portable than cross-platform named pipes
- explicit framing markers are more reliable than parsing REPL prompts

## Protocol Sketch
- temp state dir with broker pid, child pid, lock, requests, responses, logs, metadata
- request file: id, op (`eval` / `stop` / `status`), payload, timestamp
- response file: id, status, stdout, stderr, value or error summary
- prefer plain text over JSON for shell friendliness

## Open Problems
- shell escaping for arbitrary forms
- preserving REPL session state and namespace
- separating printed output from return value
- avoiding stderr deadlocks and long-output blocking
- startup readiness without prompt scraping
- process-tree termination on Windows and POSIX
- locking, concurrent eval protection, and crash cleanup

## Delivery Phases
1. Minimal flow: launcher, broker, piped REPL, single eval, stop
2. Robustness: framing, timeouts, cleanup, process-tree kill
3. Polish: status, logs, better formatting, eval from file/stdin
