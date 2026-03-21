#!/usr/bin/env python3
import argparse
import difflib
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
REPL = ROOT / "repl.cmd"


def run_repl(args: list[str], shell: str | None) -> subprocess.CompletedProcess[str]:
    if os.name == "nt":
        command = ["cmd", "/c", str(REPL), *args]
    else:
        cmdline = "./repl.cmd"
        if args:
            cmdline += " " + " ".join(shlex.quote(arg) for arg in args)

        if shell in {"sh", "bash", "zsh"}:
            command = [shell, "-lc", cmdline]
        elif shell == "fish":
            command = [shell, "-c", cmdline]
        elif shell == "tcsh":
            command = [shell, "-f", "-c", cmdline]
        else:
            raise AssertionError(f"unknown launcher shell: {shell}")

    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)


def append_block(lines: list[str], title: str, text: str) -> None:
    lines.append(title)
    normalized = text.replace("\r\n", "\n")
    if normalized == "":
        lines.append("  <empty>")
        return
    for line in normalized.rstrip("\n").split("\n"):
        lines.append(f"  {line}")


def run_tests(output_path: Path, launcher_shell: str | None) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    result = run_repl([], launcher_shell)
    stdout = result.stdout
    stderr = result.stderr

    if result.returncode != 0:
        raise AssertionError(
            f"repl.cmd without args should succeed: {stderr.strip() or stdout.strip()}"
        )

    lines = [
        "repl.cmd test transcript v3",
        "scope: no-args scaffold",
        "note: compare exact output across OSes after CRLF normalization only",
        "",
        "PASS no-args",
        "  repl.cmd without args is the current behavior scaffold",
        f"  exit-code: {result.returncode}",
    ]
    append_block(lines, "STDOUT", stdout)
    append_block(lines, "STDERR", stderr)

    output = "\n".join(lines) + "\n"
    output_path.write_text(output, encoding="utf-8", newline="\n")
    print(f"wrote {output_path}")


def compare_outputs(artifacts_root: Path) -> None:
    files = sorted(artifacts_root.rglob("test-output.txt"))
    if len(files) < 2:
        raise AssertionError("need at least two test-output.txt artifacts to compare")

    reference_path = files[0]
    reference_text = reference_path.read_text(encoding="utf-8")

    mismatches = 0
    for candidate_path in files[1:]:
        candidate_text = candidate_path.read_text(encoding="utf-8")
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
