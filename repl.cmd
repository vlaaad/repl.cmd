: <<"BATCH"
@echo off
setlocal
goto :windows
BATCH
set -eu

state_dir() {
  if [ "${REPLCTL_STATE_DIR-}" != "" ]; then
    REPLCTL_STATE=$REPLCTL_STATE_DIR
  else
    REPLCTL_STATE="${TMPDIR:-/tmp}/replctl-sketch"
  fi
}

usage() {
  cat <<'EOF'
replctl sketch

  repl.cmd start -- <repl command...>
  repl.cmd eval "(+ 1 2)"
  repl.cmd stop
  repl.cmd status

This is a protocol and control-flow sketch, not a finished implementation.
EOF
}

write_metadata() {
  cat >"$REPLCTL_STATE/metadata.txt" <<EOF
protocol-version: 1
backend-command: $1
state-dir: $REPLCTL_STATE
EOF
}

queue_eval() {
  reqid="$(date +%s)-$$"
  cat >"$REPLCTL_STATE/requests/$reqid.req" <<EOF
request-id: $reqid
op: eval
form: $1
EOF
  printf '%s\n' "queued request $reqid"
  printf '%s\n' 'sketch only: broker should pick up request, wrap the form with sentinels, and write a response file.'
}

queue_stop() {
  reqid="stop-$(date +%s)-$$"
  cat >"$REPLCTL_STATE/requests/$reqid.req" <<EOF
request-id: $reqid
op: stop
EOF
  printf '%s\n' 'queued stop request'
}

broker() {
  state_dir
  printf 'broker sketch running in "%s"\n\n' "$REPLCTL_STATE"
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

sketch() {
  cat <<'EOF'
Common state layout:
  metadata.txt
  broker.pid
  child.pid
  lock
  requests/*.req
  responses/*.resp
  logs/stdout.log
  logs/stderr.log

Wrapped eval shape:
  <begin:<request-id>>
  user form output
  <value:<edn-or-pr-str>>
  <end:<request-id>>

POSIX branch sketch:
  state_dir="${TMPDIR:-/tmp}/replctl-sketch"
  mkdir -p "$state_dir/requests" "$state_dir/responses" "$state_dir/logs"
  sh "$0" __broker >/dev/null 2>&1 &
  printf 'request-id: %s\nop: eval\nform: %s\n' "$id" "$form" > "$state_dir/requests/$id.req"
  while :; do scan request files; done

Windows branch sketch:
  set "REPLCTL_STATE=%TEMP%\replctl-sketch"
  if not exist "%REPLCTL_STATE%\requests" mkdir "%REPLCTL_STATE%\requests"
  start "replctl-broker" /b cmd /c ""%~f0" __broker"
  >"%REPLCTL_STATE%\requests\%REQID%.req" echo request-id: %REQID%
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
    mkdir -p "$REPLCTL_STATE/requests" "$REPLCTL_STATE/responses" "$REPLCTL_STATE/logs"
    repl_cmd=$1
    shift
    if [ "$#" -gt 0 ]; then
      repl_cmd="$repl_cmd $1 [and more]"
    fi
    write_metadata "$repl_cmd"
    sh "$0" __broker >/dev/null 2>&1 &
    printf 'started broker sketch in "%s"\n' "$REPLCTL_STATE"
    ;;
  eval)
    state_dir
    if [ "${2-}" = "" ]; then
      printf '%s\n' 'expected form payload' >&2
      exit 1
    fi
    mkdir -p "$REPLCTL_STATE/requests"
    queue_eval "$2"
    ;;
  stop)
    state_dir
    mkdir -p "$REPLCTL_STATE/requests"
    queue_stop
    ;;
  status)
    state_dir
    if [ ! -f "$REPLCTL_STATE/metadata.txt" ]; then
      printf '%s\n' 'stopped'
      exit 1
    fi
    printf 'state-dir: %s\n' "$REPLCTL_STATE"
    cat "$REPLCTL_STATE/metadata.txt"
    ;;
  __broker)
    broker
    ;;
  __sketch)
    sketch
    ;;
  *)
    printf 'unknown command: %s\n' "$cmd" >&2
    usage >&2
    exit 1
    ;;
esac

exit 0

:usage
echo replctl sketch
echo.
echo   repl.cmd start -- ^<repl command...^>
echo   repl.cmd eval "(+ 1 2)"
echo   repl.cmd stop
echo   repl.cmd status
echo.
echo This is a protocol and control-flow sketch, not a finished implementation.
exit /b 0

:usage_error
exit /b 1

:state_dir
if defined REPLCTL_STATE_DIR (
  set "REPLCTL_STATE=%REPLCTL_STATE_DIR%"
) else (
  set "REPLCTL_STATE=%TEMP%\replctl-sketch"
)
exit /b 0

:broker
call :state_dir
echo broker sketch running in "%REPLCTL_STATE%"
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

:sketch
echo Common state layout:
echo   metadata.txt
echo   broker.pid
echo   child.pid
echo   lock
echo   requests/*.req
echo   responses/*.resp
echo   logs/stdout.log
echo   logs/stderr.log
echo.
echo Wrapped eval shape:
echo   ^<begin:^<request-id^>^>
echo   user form output
echo   ^<value:^<edn-or-pr-str^>^>
echo   ^<end:^<request-id^>^>
echo.
echo POSIX branch sketch:
echo   state_dir="${TMPDIR:-/tmp}/replctl-sketch"
echo   mkdir -p "$state_dir/requests" "$state_dir/responses" "$state_dir/logs"
echo   sh "$0" __broker ^>/dev/null 2^>^&1 ^&
echo   printf 'request-id: %%s\nop: eval\nform: %%s\n' "$id" "$form" ^> "$state_dir/requests/$id.req"
echo   while :; do scan request files; done
echo.
echo Windows branch sketch:
echo   set "REPLCTL_STATE=%%TEMP%%\replctl-sketch"
echo   if not exist "%%REPLCTL_STATE%%\requests" mkdir "%%REPLCTL_STATE%%\requests"
echo   start "replctl-broker" /b cmd /c ""%%~f0" __broker"
echo   ^>"%%REPLCTL_STATE%%\requests\%%REQID%%.req" echo request-id: %%REQID%%
exit /b 0

:windows
if "%~1"=="" goto :usage
if /I "%~1"=="start" goto :start
if /I "%~1"=="eval" goto :eval
if /I "%~1"=="stop" goto :stop
if /I "%~1"=="status" goto :status
if /I "%~1"=="__broker" goto :broker
if /I "%~1"=="__sketch" goto :sketch

echo unknown command: %~1 1>&2
goto :usage_error

:start
call :state_dir
if not "%~2"=="--" (
  echo expected -- before repl command 1>&2
  exit /b 1
)
if not exist "%REPLCTL_STATE%" mkdir "%REPLCTL_STATE%"
if not exist "%REPLCTL_STATE%\requests" mkdir "%REPLCTL_STATE%\requests"
if not exist "%REPLCTL_STATE%\responses" mkdir "%REPLCTL_STATE%\responses"
if not exist "%REPLCTL_STATE%\logs" mkdir "%REPLCTL_STATE%\logs"
set "REPLCTL_CMD=%~3"
if not "%~4"=="" set "REPLCTL_CMD=%REPLCTL_CMD% %~4 [and more]"
>"%REPLCTL_STATE%\metadata.txt" (
  echo protocol-version: 1
  echo backend-command: %REPLCTL_CMD%
  echo state-dir: %REPLCTL_STATE%
)
start "replctl-broker" /b cmd /c ""%~f0" __broker"
echo started broker sketch in "%REPLCTL_STATE%"
exit /b 0

:eval
call :state_dir
if "%~2"=="" (
  echo expected form payload 1>&2
  exit /b 1
)
if not exist "%REPLCTL_STATE%\requests" mkdir "%REPLCTL_STATE%\requests"
set "REQID=%RANDOM%%RANDOM%"
>"%REPLCTL_STATE%\requests\%REQID%.req" (
  echo request-id: %REQID%
  echo op: eval
  echo form: %~2
)
echo queued request %REQID%
echo sketch only: broker should pick up request, wrap the form with sentinels, and write a response file.
exit /b 0

:stop
call :state_dir
if not exist "%REPLCTL_STATE%\requests" mkdir "%REPLCTL_STATE%\requests"
set "REQID=stop-%RANDOM%%RANDOM%"
>"%REPLCTL_STATE%\requests\%REQID%.req" (
  echo request-id: %REQID%
  echo op: stop
)
echo queued stop request
exit /b 0

:status
call :state_dir
if not exist "%REPLCTL_STATE%\metadata.txt" (
  echo stopped
  exit /b 1
)
echo state-dir: %REPLCTL_STATE%
type "%REPLCTL_STATE%\metadata.txt"
exit /b 0
