# REPL Control Skill Plan

## Goal

Create a cross-platform helper/skill for controlling a local REPL without network sockets.

The desired UX is a single command for each operation:

- start a REPL in the background
- stop the REPL
- send a form and get the response

The solution should be:

- cross-platform: Windows, macOS, Linux
- non-networked IPC
- `clj`/`lein` agnostic
- usable from shell as a single command per action
- ideally packaged as a single polyglot script, even if ugly

## Context

We already proved that a hidden interactive `clojure.main` process can be driven on Windows by injecting console input, but that approach is fragile:

- tied to console behavior
- hard to frame request/response reliably
- awkward for multiline forms and long output
- not portable

Named pipes are not a good portability target:

- POSIX FIFOs on macOS/Linux are not the same as Windows named pipes
- implementation details diverge too much for a simple single-script solution

Redirected stdio is the portable primitive that exists everywhere.

## Recommended Architecture

Use a broker process plus file-based IPC.

### Components

- `replctl` single-file launcher/script
- background broker process
- managed child REPL process
- state directory in temp storage

### Broker responsibilities

- launch target REPL command with redirected `stdin` / `stdout` / `stderr`
- keep those pipes open across requests
- read request files
- send wrapped forms to REPL stdin
- read stdout until explicit sentinels are seen
- write structured response files
- stop child process and clean up state

### CLI responsibilities

- `start -- <cmd ...>`: create state dir and launch broker in background
- `eval <form>`: create request file, wait for response file, print result
- `stop`: request shutdown and, if needed, force termination
- optionally `status`

## Why File IPC

File IPC is the best fit for the stated constraints:

- cross-platform
- no TCP/network use
- no Unix/Windows named-pipe split in the public interface
- easy to drive from repeated shell invocations
- works with a single persistent broker

This is not the most elegant IPC, but it is the simplest portable option for a single-file tool.

## REPL Framing Strategy

Do not parse REPL prompts as the protocol.

Each request should send wrapped Clojure code that emits explicit markers, for example:

1. begin marker
2. captured printed output
3. serialized result or serialized exception
4. end marker

The broker should read until the end marker and ignore prompt-oriented noise outside the framed payload.

## Important Design Constraints

### Cross-platform launcher

Use a single polyglot script shape with platform-specific branches:

- Windows batch / `.cmd` entry logic
- POSIX shell entry logic
- shared protocol and state layout across platforms

This keeps the user-facing tool to one file even if the implementation has separate Windows and POSIX code paths.

### Dependency assumptions

Do not rely on Python or other extra runtimes.

The implementation target is standard shell tools only:

- POSIX shell tools on macOS/Linux
- built-in Windows batch / PowerShell / process-control commands on Windows

This makes the design harder, but it is the required constraint.

### REPL backend agnostic behavior

The tool should not care whether the command is:

- `clojure`
- `clj`
- `lein repl`
- another REPL-capable command

It only manages the subprocess and its stdio.

## Open Problems To Solve

- robust escaping of arbitrary forms passed via shell
- preserving REPL session state, including current namespace
- separating printed stdout from return value
- handling stderr without deadlocks
- handling long output without blocking
- detecting startup readiness without depending on exact prompt text
- killing process trees correctly on Windows and on POSIX
- preventing concurrent `eval` calls from corrupting the protocol
- choosing state dir naming and lock strategy
- cleanup after crashes

## Proposed Protocol

### State directory contents

- pid file for broker
- pid file for child REPL
- lock file
- request directory
- response directory
- stdout/stderr logs
- metadata file with command, timestamps, and protocol version

### Request format

Each request file should include at least:

- request id
- operation type (`eval`, `stop`, maybe `status`)
- form payload
- timestamp

Prefer a line-oriented plain-text format over JSON so both POSIX shell and Windows shell code can read and write it without extra tooling.

### Response format

Each response file should include at least:

- request id
- status (`ok`, `error`, `timeout`)
- captured stdout
- captured stderr if relevant
- serialized value or exception summary

The format should stay shell-friendly and avoid requiring parsers beyond standard line and file operations.

## Suggested Command Shape

```bash
replctl start -- clojure
replctl start -- lein repl
replctl eval "(+ 1 2)"
replctl stop
replctl status
```

Optional future additions:

```bash
replctl eval-file path/to/form.clj
replctl logs
replctl restart -- clojure
```

## Implementation Phases

### Phase 1: minimal working flow

- polyglot launcher
- shell-native command parser on each platform
- broker background mode
- start REPL child with piped stdio
- one-at-a-time `eval`
- stop command

### Phase 2: robustness

- request/response JSON protocol
- sentinels around eval payload
- timeouts
- process tree termination
- crash recovery and stale state cleanup

### Phase 3: polish

- better output formatting
- `status` and `logs`
- better shell escaping guidance
- support for eval from file/stdin

## Notes For The Skill Author

The skill should guide implementation toward:

- redirected stdio, not console injection
- file-based IPC, not TCP
- explicit framing markers, not prompt scraping
- single persistent broker, not one REPL per eval
- portable process-tree shutdown
- small, inspectable state files in temp

The skill should assume a shell-only implementation with no extra dependencies. That means the solution will likely need separate Windows and POSIX branches inside one polyglot script, plus a deliberately simple file protocol and careful use of built-in process-management commands.
