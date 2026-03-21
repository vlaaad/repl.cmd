: <<"BATCH"
@echo off
setlocal
goto :windows
BATCH
set -eu

usage() {
  cat <<'EOF'
repl.cmd

  repl.cmd start
  repl.cmd stop
  repl.cmd eval
  repl.cmd status
EOF
}

cmd=${1-}

case "$cmd" in
  "")
    usage
    ;;
  start|stop|eval|status)
    printf '%s\n' 'TODO'
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
echo   repl.cmd start
echo   repl.cmd stop
echo   repl.cmd eval
echo   repl.cmd status
exit /b 0

:usage_error
exit /b 1

:windows
if "%~1"=="" goto :usage
if /I "%~1"=="start" goto :todo
if /I "%~1"=="stop" goto :todo
if /I "%~1"=="eval" goto :todo
if /I "%~1"=="status" goto :todo
echo unknown command: %~1 1>&2
goto :usage_error

:todo
echo TODO
exit /b 0
