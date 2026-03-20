#!/usr/bin/env python3
import argparse
import difflib
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent
REPL = ROOT / "repl.cmd"
PLAN = ROOT / "PLAN.md"
EVAL_PAYLOAD = "user-form-payload"


def normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def assert_contains(haystack: str, needle: str, message: str) -> None:
    if needle not in haystack:
        raise AssertionError(message)


def launcher_command(args: list[str], launcher_shell: str | None) -> list[str]:
    if os.name == "nt":
        return ["cmd", "/c", str(REPL), *args]

    cmdline = "./repl.cmd"
    if args:
        cmdline += " " + " ".join(shlex.quote(arg) for arg in args)

    if launcher_shell in {"sh", "bash", "zsh"}:
        return [launcher_shell, "-lc", cmdline]
    if launcher_shell == "fish":
        return ["fish", "-c", cmdline]
    if launcher_shell == "tcsh":
        return ["tcsh", "-f", "-c", cmdline]
    raise AssertionError(f"unknown launcher shell: {launcher_shell}")


def run_repl(args: list[str], launcher_shell: str | None, state_dir: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["REPL_CMD_STATE_DIR"] = str(state_dir)
    command = launcher_command(args, launcher_shell)
    return subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def normalize_runtime_text(text: str, state_dir: Path) -> str:
    normalized = normalize_newlines(text)
    normalized = normalized.replace(str(state_dir), "<state-dir>")
    normalized = normalized.replace(str(state_dir).replace("\\", "/"), "<state-dir>")
    normalized = normalized.replace("\\", "/")
    normalized = re.sub(r"queued request [A-Za-z0-9_-]+", "queued request <request-id>", normalized)
    normalized = re.sub(r"request-id: [A-Za-z0-9_-]+", "request-id: <request-id>", normalized)
    normalized = re.sub(r"stop-[A-Za-z0-9_-]+", "stop-<request-id>", normalized)
    normalized = re.sub(r"[0-9]{6,}", "<id>", normalized)
    return normalized


def latest_request(state_dir: Path) -> str:
    requests_dir = state_dir / "requests"
    request_files = sorted(requests_dir.glob("*.req"))
    if not request_files:
        raise AssertionError("expected at least one request file")
    return request_files[-1].read_text(encoding="utf-8")


def append_block(lines: list[str], title: str, text: str) -> None:
    lines.append(title)
    for line in normalize_newlines(text).rstrip("\n").split("\n"):
        lines.append(f"  {line}")


def run_tests(output_path: Path, launcher_shell: str | None) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    repl_source = REPL.read_text(encoding="utf-8")
    assert_contains(repl_source, ': <<"BATCH"', "missing polyglot batch shim")
    assert_contains(repl_source, 'case "$cmd" in', "missing POSIX command dispatch")
    assert_contains(repl_source, "goto :start", "missing Windows start dispatch")
    plan_source = PLAN.read_text(encoding="utf-8")
    assert_contains(plan_source, "cross-platform", "plan must mention cross-platform support")
    assert_contains(plan_source, "file-based IPC", "plan must mention file-based IPC")
    assert_contains(plan_source, "explicit framing markers", "plan must mention explicit framing markers")
    assert_contains(plan_source, "tests may require Python", "plan must mention Python-backed tests")

    lines = [
        "repl.cmd test transcript v2",
        "scope: contract scaffold",
        "note: tests execute the polyglot entrypoint and normalize dynamic values",
        "",
        "PASS cli-dispatch",
        "  polyglot file exposes both POSIX and batch dispatch",
        "  single entrypoint keeps the command surface aligned across OSes",
        "PASS plan-constraints",
        "  PLAN.md still captures the portability and protocol constraints",
        "  tests may depend on Python while the runtime remains shell-only",
    ]

    with tempfile.TemporaryDirectory(prefix="repl-cmd-test-") as temp_dir:
        state_dir = Path(temp_dir) / "state"

        stopped = run_repl(["status"], launcher_shell, state_dir)
        stopped_text = normalize_runtime_text(stopped.stdout + stopped.stderr, state_dir)
        if stopped.returncode == 0:
            raise AssertionError("repl.cmd status should fail without metadata")
        if stopped_text.strip() != "stopped":
            raise AssertionError(f"unexpected status output: {stopped_text.strip()}")
        lines.extend(
            [
                "PASS initial-status",
                "  repl.cmd status reports stopped in a clean workspace",
                "  status output is deterministic before broker startup",
            ]
        )
        append_block(lines, "OUTPUT status-before-start", stopped_text)

        started = run_repl(["start", "--", "dummy-repl", "--flag"], launcher_shell, state_dir)
        if started.returncode != 0:
            raise AssertionError(f"repl.cmd start failed: {normalize_newlines(started.stderr).strip()}")
        started_text = normalize_runtime_text(started.stdout + started.stderr, state_dir)
        assert_contains(started_text, 'started broker placeholder in "<state-dir>"', "missing normalized start output")
        lines.extend(
            [
                "PASS start-command",
                "  repl.cmd start initializes the state directory and metadata",
                "  broker startup messaging is normalized for transcript comparison",
            ]
        )
        append_block(lines, "OUTPUT start", started_text)

        running = run_repl(["status"], launcher_shell, state_dir)
        if running.returncode != 0:
            raise AssertionError(f"repl.cmd status after start failed: {normalize_newlines(running.stderr).strip()}")
        running_text = normalize_runtime_text(running.stdout + running.stderr, state_dir)
        assert_contains(running_text, "protocol-version: 1", "missing protocol version in status output")
        assert_contains(running_text, "backend-command: dummy-repl --flag", "missing backend command in status output")
        lines.extend(
            [
                "PASS running-status",
                "  repl.cmd status exposes broker metadata after startup",
                "  metadata output stays comparable after path normalization",
            ]
        )
        append_block(lines, "OUTPUT status-after-start", running_text)

        eval_result = run_repl(["eval", EVAL_PAYLOAD], launcher_shell, state_dir)
        if eval_result.returncode != 0:
            raise AssertionError(f"repl.cmd eval failed: {normalize_newlines(eval_result.stderr).strip()}")
        eval_text = normalize_runtime_text(eval_result.stdout + eval_result.stderr, state_dir)
        request_text = normalize_runtime_text(latest_request(state_dir), state_dir)
        assert_contains(eval_text, "queued request <request-id>", "missing queued eval output")
        assert_contains(request_text, "op: eval", "missing eval request file")
        assert_contains(request_text, f"form: {EVAL_PAYLOAD}", "missing eval payload")
        lines.extend(
            [
                "PASS eval-command",
                "  repl.cmd eval enqueues a request file in the shared state dir",
                "  request output and payload are normalized before artifact comparison",
            ]
        )
        append_block(lines, "OUTPUT eval", eval_text)
        append_block(lines, "OUTPUT eval-request", request_text)

        stop_result = run_repl(["stop"], launcher_shell, state_dir)
        if stop_result.returncode != 0:
            raise AssertionError(f"repl.cmd stop failed: {normalize_newlines(stop_result.stderr).strip()}")
        stop_text = normalize_runtime_text(stop_result.stdout + stop_result.stderr, state_dir)
        stop_request_text = normalize_runtime_text(latest_request(state_dir), state_dir)
        assert_contains(stop_text, "queued stop request", "missing queued stop output")
        assert_contains(stop_request_text, "op: stop", "missing stop request file")
        lines.extend(
            [
                "PASS stop-command",
                "  repl.cmd stop enqueues a stop request in the shared state dir",
                "  stop request content remains stable after id normalization",
            ]
        )
        append_block(lines, "OUTPUT stop", stop_text)
        append_block(lines, "OUTPUT stop-request", stop_request_text)

    output = "\n".join(lines) + "\n"
    output_path.write_text(output, encoding="utf-8", newline="\n")
    print(f"wrote {output_path}")


def compare_outputs(artifacts_root: Path) -> None:
    files = sorted(artifacts_root.rglob("test-output.txt"))
    if len(files) < 2:
        raise AssertionError("need at least two test-output.txt artifacts to compare")

    reference_path = files[0]
    reference_text = normalize_newlines(reference_path.read_text(encoding="utf-8"))

    mismatches = 0
    for candidate_path in files[1:]:
        candidate_text = normalize_newlines(candidate_path.read_text(encoding="utf-8"))
        if candidate_text == reference_text:
            continue
        mismatches += 1
        print(f"artifact mismatch: {reference_path} vs {candidate_path}", file=sys.stderr)
        diff = difflib.unified_diff(
            reference_text.splitlines(),
            candidate_text.splitlines(),
            fromfile=str(reference_path),
            tofile=str(candidate_path),
            lineterm="",
        )
        for line in diff:
            print(line, file=sys.stderr)

    if mismatches:
        raise AssertionError(f"found {mismatches} artifact mismatch(es)")

    print(f"validated identical outputs across {len(files)} OS artifacts")


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--output-path", type=Path, required=True)
    run_parser.add_argument("--launcher-shell")

    compare_parser = subparsers.add_parser("compare")
    compare_parser.add_argument("--artifacts-root", type=Path, required=True)

    args = parser.parse_args()

    try:
        if args.command == "run":
            run_tests(args.output_path, args.launcher_shell)
        else:
            compare_outputs(args.artifacts_root)
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
