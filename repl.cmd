: <<"BATCH"
@echo off
setlocal
goto :windows
BATCH
set -eu

state_dir() {
  REPL_CMD_STATE="${TMPDIR:-/tmp}/repl.cmd-state"
}

usage() {
  cat <<'EOF'
repl.cmd

  repl.cmd start -- <repl command...>
  repl.cmd eval "(+ 1 2)"
  repl.cmd stop
  repl.cmd status

This is a protocol and control-flow scaffold, not a finished implementation.
EOF
}

write_metadata() {
  cat >"$REPL_CMD_STATE/metadata.txt" <<EOF
protocol-version: 1
backend-command: $1
state-dir: $REPL_CMD_STATE
EOF
}

queue_eval() {
  reqid="$(date +%s)-$$"
  cat >"$REPL_CMD_STATE/requests/$reqid.req" <<EOF
request-id: $reqid
op: eval
form: $1
EOF
  printf '%s\n' "queued request $reqid"
  printf '%s\n' 'placeholder only: broker should pick up request, wrap the form with sentinels, and write a response file.'
}

queue_stop() {
  reqid="stop-$(date +%s)-$$"
  cat >"$REPL_CMD_STATE/requests/$reqid.req" <<EOF
request-id: $reqid
op: stop
EOF
  printf '%s\n' 'queued stop request'
}

broker() {
  state_dir
  printf 'broker placeholder running in "%s"\n\n' "$REPL_CMD_STATE"
  cat <<'EOF'
TODO broker flow:
  1. launch child repl with redirected stdin/stdout/stderr
  2. record child pid in child.pid
  3. poll requests directory one file at a time under a lock
  4. for eval, write framed form to child stdin
  5. read stdout until end sentinel, capture stderr separately
  6. write shell-friendly response file to responses
  7. on stop, terminate child process tree and clean up state
EOF
}

cmd=${1-}

case "$cmd" in
  "")
    usage
    ;;
  start)
    state_dir
    if [ "${2-}" != "--" ] || [ "$#" -lt 3 ]; then
      printf '%s\n' 'expected -- before repl command' >&2
      exit 1
    fi
    shift 2
    mkdir -p "$REPL_CMD_STATE/requests" "$REPL_CMD_STATE/responses" "$REPL_CMD_STATE/logs"
    repl_cmd=$1
    shift
    if [ "$#" -gt 0 ]; then
      repl_cmd="$repl_cmd $1 [and more]"
    fi
    write_metadata "$repl_cmd"
    sh "$0" __broker >/dev/null 2>&1 &
    printf 'started broker placeholder in "%s"\n' "$REPL_CMD_STATE"
    ;;
  eval)
    state_dir
    if [ "${2-}" = "" ]; then
      printf '%s\n' 'expected form payload' >&2
      exit 1
    fi
    mkdir -p "$REPL_CMD_STATE/requests"
    queue_eval "$2"
    ;;
  stop)
    state_dir
    mkdir -p "$REPL_CMD_STATE/requests"
    queue_stop
    ;;
  status)
    state_dir
    if [ ! -f "$REPL_CMD_STATE/metadata.txt" ]; then
      printf '%s\n' 'stopped'
      exit 1
    fi
    printf 'state-dir: %s\n' "$REPL_CMD_STATE"
    cat "$REPL_CMD_STATE/metadata.txt"
    ;;
  __broker)
    broker
    ;;
  *)
    printf 'unknown command: %s\n' "$cmd" >&2
    usage >&2
    exit 1
    ;;
esac

exit 0

:usage
echo repl.cmd
echo.
echo   repl.cmd start -- ^<repl command...^>
echo   repl.cmd eval "(+ 1 2)"
echo   repl.cmd stop
echo   repl.cmd status
echo.
echo This is a protocol and control-flow scaffold, not a finished implementation.
exit /b 0

:usage_error
exit /b 1

:state_dir
set "REPL_CMD_STATE=%TEMP%\repl.cmd-state"
exit /b 0

:broker
call :state_dir
echo broker placeholder running in "%REPL_CMD_STATE%"
echo.
echo TODO broker flow:
echo   1. launch child repl with redirected stdin/stdout/stderr
echo   2. record child pid in child.pid
echo   3. poll requests directory one file at a time under a lock
echo   4. for eval, write framed form to child stdin
echo   5. read stdout until end sentinel, capture stderr separately
echo   6. write shell-friendly response file to responses
echo   7. on stop, terminate child process tree and clean up state
exit /b 0

:windows
if "%~1"=="" goto :usage
if /I "%~1"=="start" goto :start
if /I "%~1"=="eval" goto :eval
if /I "%~1"=="stop" goto :stop
if /I "%~1"=="status" goto :status
if /I "%~1"=="__broker" goto :broker
echo unknown command: %~1 1>&2
goto :usage_error

:start
call :state_dir
if not "%~2"=="--" (
  echo expected -- before repl command 1>&2
  exit /b 1
)
if not exist "%REPL_CMD_STATE%" mkdir "%REPL_CMD_STATE%"
if not exist "%REPL_CMD_STATE%\requests" mkdir "%REPL_CMD_STATE%\requests"
if not exist "%REPL_CMD_STATE%\responses" mkdir "%REPL_CMD_STATE%\responses"
if not exist "%REPL_CMD_STATE%\logs" mkdir "%REPL_CMD_STATE%\logs"
set "REPL_CMD_CMD=%~3"
if not "%~4"=="" set "REPL_CMD_CMD=%REPL_CMD_CMD% %~4 [and more]"
>"%REPL_CMD_STATE%\metadata.txt" (
  echo protocol-version: 1
  echo backend-command: %REPL_CMD_CMD%
  echo state-dir: %REPL_CMD_STATE%
)
start "repl.cmd-broker" /b cmd /c ""%~f0" __broker >nul 2>&1"
echo started broker placeholder in "%REPL_CMD_STATE%"
exit /b 0

:eval
call :state_dir
if "%~2"=="" (
  echo expected form payload 1>&2
  exit /b 1
)
if not exist "%REPL_CMD_STATE%\requests" mkdir "%REPL_CMD_STATE%\requests"
set "REQID=%RANDOM%%RANDOM%"
>"%REPL_CMD_STATE%\requests\%REQID%.req" (
  echo request-id: %REQID%
  echo op: eval
  echo form: %~2
)
echo queued request %REQID%
echo placeholder only: broker should pick up request, wrap the form with sentinels, and write a response file.
exit /b 0

:stop
call :state_dir
if not exist "%REPL_CMD_STATE%\requests" mkdir "%REPL_CMD_STATE%\requests"
set "REQID=stop-%RANDOM%%RANDOM%"
>"%REPL_CMD_STATE%\requests\%REQID%.req" (
  echo request-id: %REQID%
  echo op: stop
)
echo queued stop request
exit /b 0

:status
call :state_dir
if not exist "%REPL_CMD_STATE%\metadata.txt" (
  echo stopped
  exit /b 1
)
echo state-dir: %REPL_CMD_STATE%
type "%REPL_CMD_STATE%\metadata.txt"
exit /b 0
