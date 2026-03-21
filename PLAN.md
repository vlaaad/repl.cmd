# REPL Control Skill Plan

## Goal
Build a cross-platform single-file `repl.cmd` helper that manages a local REPL per exact working directory without network sockets.

## UX
- `repl.cmd start`
- `repl.cmd start clj`
- `repl.cmd start lein`
- `repl.cmd start -- <custom-command...>`
- `repl.cmd eval "<form>"`
- `echo "<form>" | repl.cmd eval`
- `repl.cmd stop`
- `repl.cmd status`
- help flags: `repl.cmd -h`, `repl.cmd -?`, `repl.cmd --help`
- `eval` has a `--timeout <seconds>` option; default is 5 seconds and applies end-to-end, including waiting for a busy REPL
- commands always target the REPL associated with the exact current working directory

## Constraints
- Windows, macOS, and Linux
- no TCP
- built-in launcher support for `clj` and `lein`, plus fully custom launcher command support
- one polyglot entry script with Windows and POSIX branches
- POSIX branch may be shell-native; Windows branch may delegate runtime work to built-in `powershell.exe`
- exact help/usage output across Windows and POSIX entrypoints
- polyglot script with no extra dependencies: python is ONLY for tests
- osc-repl.clj is a good inspiration
- deliverable: single file and no extra deps beyound what can reasonably be expected on a computer.

## Architecture
Start a detached REPL process directly and manage it with a lightweight local session registry.

- `repl.cmd start` writes `.repl.cmd/repl.clj` and launches the target REPL as a detached child with redirected `stdin` / `stdout` / `stderr`
- `repl.cmd` stores session state in `<cwd>/.repl.cmd/`
- one detached REPL session exists per exact working directory
- `start` bootstraps `.repl.cmd/` and writes `.repl.cmd/.gitignore` automatically
- `.repl.cmd/repl.clj` is generated runtime support owned by `repl.cmd` and may be regenerated when missing or outdated
- built-in launchers invoke `.repl.cmd/repl.clj` directly; custom launchers are only guaranteed that the file exists
- `repl.cmd` stores session metadata locally: pid, cwd, command, started_at, transport paths, lock state, and status
- `eval` acquires exclusive session access, writes to the session input, then waits for explicit framed completion markers
- `repl.cmd` parses framing markers from the child stdout stream and quantizes output into eval-scoped chunks
- output is captured in local files so later commands can reconnect without a broker
- `stop` and cleanup operate from the stored session metadata

## Launcher Detection
- `repl.cmd start` auto-detects the launcher from files in the exact current working directory only
- `deps.edn` => `clj -M .repl.cmd/repl.clj`
- `project.clj` => `lein run -m clojure.main .repl.cmd/repl.clj`
- if both `deps.edn` and `project.clj` exist, `start` fails fast as ambiguous and suggests `start clj` or `start lein`
- if neither file exists, `start` fails fast and suggests an explicit launcher or custom command
- `repl.cmd start clj` runs `clj -M .repl.cmd/repl.clj`
- `repl.cmd start lein` runs `lein run -m clojure.main .repl.cmd/repl.clj`
- `repl.cmd start -- <custom-command...>` runs the custom command exactly as provided after ensuring `.repl.cmd/repl.clj` exists
- custom commands are responsible for invoking `.repl.cmd/repl.clj` or otherwise starting a compatible REPL that emits the expected framing

## Protocol Sketch
- state dir: `<cwd>/.repl.cmd/`
- `.repl.cmd/.gitignore` contents: `*`
- generated adapter: `.repl.cmd/repl.clj`
- internal stream framing uses OSC `133`, emitted by `.repl.cmd/repl.clj` and parsed by `repl.cmd`
- required framing markers: `133;A`, `133;B`, `133;C`, and `133;D;<code>`
- `A/B` indicate prompt boundaries and readiness for input
- `C/D` indicate eval execution boundaries and exit status
- markers are an internal protocol detail; `repl.cmd` consumes them and does not expose them as user output
- stdout carries the OSC `133` framing markers and is parsed continuously by `repl.cmd`
- stderr is captured separately and never carries framing markers
- while no eval is active, stdout and stderr are still drained to avoid blocking the child process, but their user-visible output is discarded
- public session status is `stopped`, `busy`, or `ready`
- `busy` covers both startup and active evaluation; internal state may still distinguish those cases

## Synchronization
- `start` uses a session-level lock to prevent concurrent launch races in the same working directory
- `start` succeeds only when the session reaches `ready`, meaning the REPL is accepting input
- `eval` is serialized per session; only one client may drive the REPL stdin/stdout protocol at a time
- `eval` waits for exclusive access instead of failing fast when the REPL is already busy
- `eval --timeout <seconds>` is end-to-end and covers lock wait, request write, output collection, and framed completion
- if timeout expires before the eval completes, `eval` returns a timeout result and releases its lock state cleanly
- stale locks must be recoverable via pid and liveness checks
