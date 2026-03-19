: <<"BATCH"
@echo off
setlocal
goto :windows
BATCH
set -eu

OUTPUT_PATH=artifacts/test-output.txt
LAUNCHER_SHELL=sh

while [ "$#" -gt 0 ]; do
  case "$1" in
    -OutputPath)
      shift
      OUTPUT_PATH=${1-}
      ;;
    -LauncherShell)
      shift
      LAUNCHER_SHELL=${1-}
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

assert_contains() {
  haystack=$1
  needle=$2
  message=$3
  case "$haystack" in
    *"$needle"*) ;;
    *)
      printf '%s\n' "$message" >&2
      exit 1
      ;;
  esac
}

append_result() {
  printf 'PASS %s\n' "$1" >> "$OUTPUT_PATH"
  shift
  while [ "$#" -gt 0 ]; do
    printf '  %s\n' "$1" >> "$OUTPUT_PATH"
    shift
  done
}

run_repl() {
  cmdline='./repl.cmd'
  for arg in "$@"; do
    cmdline="$cmdline $arg"
  done

  case "$LAUNCHER_SHELL" in
    sh|bash|zsh)
      "$LAUNCHER_SHELL" -lc "$cmdline"
      ;;
    fish)
      fish -c "$cmdline"
      ;;
    tcsh)
      tcsh -f -c "$cmdline"
      ;;
    *)
      printf 'unknown launcher shell: %s\n' "$LAUNCHER_SHELL" >&2
      exit 1
      ;;
  esac
}

run_tests() {
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  : > "$OUTPUT_PATH"

  printf 'repl.cmd test transcript v1\n' >> "$OUTPUT_PATH"
  printf 'scope: contract scaffold\n' >> "$OUTPUT_PATH"
  printf 'note: these tests validate the polyglot interface sketch without extra runtimes\n\n' >> "$OUTPUT_PATH"

  repl_source=$(cat "$(dirname "$0")/repl.cmd")
  assert_contains "$repl_source" ': <<"BATCH"' 'missing polyglot batch shim'
  assert_contains "$repl_source" 'case "$cmd" in' 'missing POSIX command dispatch'
  assert_contains "$repl_source" 'goto :start' 'missing Windows start dispatch'
  append_result 'cli-dispatch' \
    'polyglot file exposes both POSIX and batch dispatch' \
    'single entrypoint keeps the command surface aligned across OSes'

  plan_source=$(cat "$(dirname "$0")/PLAN.md")
  assert_contains "$plan_source" 'cross-platform' 'plan must mention cross-platform support'
  assert_contains "$plan_source" 'file-based IPC' 'plan must mention file-based IPC'
  assert_contains "$plan_source" 'explicit framing markers' 'plan must mention explicit framing markers'
  append_result 'plan-constraints' \
    'PLAN.md still captures the portability and protocol constraints' \
    'tests fail if the design drifts from redirected-stdio plus file IPC'

  sketch_output=$(run_repl __sketch)
  assert_contains "$sketch_output" 'Common state layout:' 'missing common state layout output'
  assert_contains "$sketch_output" 'POSIX branch sketch:' 'missing POSIX sketch output'
  assert_contains "$sketch_output" 'Windows branch sketch:' 'missing Windows sketch output'
  append_result 'polyglot-runtime-sketch' \
    'repl.cmd __sketch can be launched from the configured shell entrypoint' \
    'the emitted sketch text is stable enough for cross-OS comparison'

  if status_output=$(run_repl status 2>&1); then
    printf '%s\n' 'repl.cmd status should fail without metadata' >&2
    exit 1
  fi
  [ "$status_output" = 'stopped' ] || {
    printf 'unexpected status output: %s\n' "$status_output" >&2
    exit 1
  }
  append_result 'polyglot-runtime-status' \
    'repl.cmd status reports stopped in a clean workspace' \
    'status output is deterministic before broker startup'

  printf 'wrote %s\n' "$OUTPUT_PATH"
}

run_tests

exit 0

:windows
set "SCRIPT_DIR=%~dp0"
set "OUTPUT_PATH=artifacts/test-output.txt"

:parse_args
if "%~1"=="" goto :dispatch
if /I "%~1"=="-OutputPath" (
  set "OUTPUT_PATH=%~2"
  shift
  shift
  goto :parse_args
)
if /I "%~1"=="-LauncherShell" (
  shift
  shift
  goto :parse_args
)
echo unknown argument: %~1 1>&2
exit /b 1

:dispatch
goto :run

:append_line
if "%~1"=="" (
  >> "%OUTPUT_PATH%" echo(
  exit /b 0
)
>> "%OUTPUT_PATH%" echo %~1
exit /b 0

:check_file_contains
findstr /c:"%~2" "%~1" >nul || (
  echo %~3 1>&2
  exit /b 1
)
exit /b 0

:run_repl
set "REPL_OUT=%TEMP%\repl-test-%RANDOM%%RANDOM%.txt"
cmd /c ""%~dp0repl.cmd" %*" > "%REPL_OUT%" 2>&1
set "REPL_EXIT=%ERRORLEVEL%"
exit /b 0

:run
for %%D in ("%OUTPUT_PATH%") do set "OUTPUT_DIR=%%~dpD"
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
break > "%OUTPUT_PATH%"

call :append_line "repl.cmd test transcript v1" || exit /b 1
call :append_line "scope: contract scaffold" || exit /b 1
call :append_line "note: these tests validate the polyglot interface sketch without extra runtimes" || exit /b 1
call :append_line "" || exit /b 1

call :check_file_contains "%SCRIPT_DIR%repl.cmd" ": <<\"BATCH\"" "missing polyglot batch shim" || exit /b 1
call :check_file_contains "%SCRIPT_DIR%repl.cmd" "case \"$cmd\" in" "missing POSIX command dispatch" || exit /b 1
call :check_file_contains "%SCRIPT_DIR%repl.cmd" "goto :start" "missing Windows start dispatch" || exit /b 1
call :append_line "PASS cli-dispatch" || exit /b 1
call :append_line "  polyglot file exposes both POSIX and batch dispatch" || exit /b 1
call :append_line "  single entrypoint keeps the command surface aligned across OSes" || exit /b 1

call :check_file_contains "%SCRIPT_DIR%PLAN.md" "cross-platform" "plan must mention cross-platform support" || exit /b 1
call :check_file_contains "%SCRIPT_DIR%PLAN.md" "file-based IPC" "plan must mention file-based IPC" || exit /b 1
call :check_file_contains "%SCRIPT_DIR%PLAN.md" "explicit framing markers" "plan must mention explicit framing markers" || exit /b 1
call :append_line "PASS plan-constraints" || exit /b 1
call :append_line "  PLAN.md still captures the portability and protocol constraints" || exit /b 1
call :append_line "  tests fail if the design drifts from redirected-stdio plus file IPC" || exit /b 1

call :run_repl __sketch || exit /b 1
findstr /c:"Common state layout:" "%REPL_OUT%" >nul || (echo missing common state layout output 1>&2 & exit /b 1)
findstr /c:"POSIX branch sketch:" "%REPL_OUT%" >nul || (echo missing POSIX sketch output 1>&2 & exit /b 1)
findstr /c:"Windows branch sketch:" "%REPL_OUT%" >nul || (echo missing Windows sketch output 1>&2 & exit /b 1)
del "%REPL_OUT%"
call :append_line "PASS polyglot-runtime-sketch" || exit /b 1
call :append_line "  repl.cmd __sketch can be launched from the configured shell entrypoint" || exit /b 1
call :append_line "  the emitted sketch text is stable enough for cross-OS comparison" || exit /b 1

call :run_repl status || exit /b 1
if "%REPL_EXIT%"=="0" (
  echo repl.cmd status should fail without metadata 1>&2
  exit /b 1
)
set /p STATUS_LINE=<"%REPL_OUT%"
if not "%STATUS_LINE%"=="stopped" (
  echo unexpected status output: %STATUS_LINE% 1>&2
  exit /b 1
)
del "%REPL_OUT%"
call :append_line "PASS polyglot-runtime-status" || exit /b 1
call :append_line "  repl.cmd status reports stopped in a clean workspace" || exit /b 1
call :append_line "  status output is deterministic before broker startup" || exit /b 1

echo wrote %OUTPUT_PATH%
exit /b 0
