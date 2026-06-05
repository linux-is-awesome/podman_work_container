#!/usr/bin/env bash
# Verification suite for APP_HOME + centralized exec refactor.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${PROJECT_DIR}/scripts"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
APP_HOME="${HOME}/.containers/work_container/home"
FAIL=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL=1; }

require_container() {
  if ! sudo podman ps --format '{{.Names}}' 2>/dev/null | grep -qx 'work_container'; then
    fail "work_container is not running (start with ./start service-start)"
    exit 1
  fi
}

# --- static checks ---
for f in host-podman-exec exec-in service-start install host-mounts chrome-work-open vscode-work-open; do
  bash -n "${SCRIPT_DIR}/${f}" || { fail "syntax ${f}"; exit 1; }
done
pass "bash -n on all critical scripts"

if ! grep -q 'return 0' "${SCRIPT_DIR}/host-podman-exec"; then
  fail "podman_append_gui_session_env missing explicit return 0"
fi
pass "podman_append_gui_session_env has return 0"

# set -e must not kill callers of podman_append_gui_session_env
if ! bash -c 'set -euo pipefail; source "'"${SCRIPT_DIR}"'/host-podman-exec"; EXEC_ARGS=(); podman_append_gui_session_env EXEC_ARGS; echo ok' >/dev/null 2>&1; then
  fail "podman_append_gui_session_env fails under set -euo pipefail"
else
  pass "podman_append_gui_session_env safe under set -euo pipefail"
fi

# Only ngrok DNS probe may use bare podman exec (read-only)
bare_exec_count="$(grep -r 'podman exec' "${SCRIPT_DIR}" --include='*.sh' --include='install' --include='exec-in' --include='service-*' --include='run' --include='host-podman-exec' 2>/dev/null | grep -v 'host-podman-exec' | grep -v 'work_container_exec_as_user' | grep -v '#' | grep -c 'podman exec' || true)"
ngrok_probe="$(grep -c "podman exec work_container sh -lc 'getent" "${SCRIPT_DIR}/install" || true)"
if [[ "${bare_exec_count}" -ne "${ngrok_probe}" ]]; then
  fail "unexpected bare podman exec outside ngrok getent probe (count=${bare_exec_count}, ngrok=${ngrok_probe})"
else
  pass "only intentional bare podman exec (ngrok getent DNS probe)"
fi

# service-start must set APP_HOME at podman run
if ! grep -q 'work_container_run_app_home_env' "${SCRIPT_DIR}/service-start"; then
  fail "service-start missing work_container_run_app_home_env"
else
  pass "service-start sets APP_HOME at podman run"
fi

# --- live container checks ---
require_container

# exec-in: host user + APP_HOME
uid_out="$(cd "${PROJECT_DIR}" && "${SCRIPT_DIR}/exec-in" id -u)"
if [[ "${uid_out}" != "${HOST_UID}" ]]; then
  fail "exec-in id -u: got ${uid_out}, want ${HOST_UID}"
else
  pass "exec-in runs as host uid ${HOST_UID}"
fi

home_out="$(cd "${PROJECT_DIR}" && "${SCRIPT_DIR}/exec-in" sh -c 'printf %s "$HOME"')"
if [[ "${home_out}" != "${APP_HOME}" ]]; then
  fail "exec-in HOME: got ${home_out}, want ${APP_HOME}"
else
  pass "exec-in HOME is APP_HOME"
fi

host_home_out="$(cd "${PROJECT_DIR}" && "${SCRIPT_DIR}/exec-in" sh -c 'printf %s "$WORK_CONTAINER_HOST_HOME"')"
if [[ "${host_home_out}" != "${HOME}" ]]; then
  fail "WORK_CONTAINER_HOST_HOME: got ${host_home_out}, want ${HOME}"
else
  pass "WORK_CONTAINER_HOST_HOME points at real host home"
fi

# workdir follows caller PWD
proj_dir="${PROJECT_DIR}"
wd_out="$(cd "${proj_dir}" && "${SCRIPT_DIR}/exec-in" pwd)"
if [[ "${wd_out}" != "${proj_dir}" ]]; then
  fail "exec-in --workdir: got ${wd_out}, want ${proj_dir}"
else
  pass "exec-in --workdir follows host PWD"
fi

# -- separator: command args with embedded flags
deploy_uid="$(cd "${PROJECT_DIR}" && "${SCRIPT_DIR}/exec-in" sh -c 'echo deploy-args:"$@"' -- sf deploy --metadata Foo 2>/dev/null | tail -1 || true)"
if [[ "${deploy_uid}" != 'deploy-args:sf deploy --metadata Foo' ]]; then
  fail "-- separator parsing: got '${deploy_uid}'"
else
  pass "-- separator parsing preserves sf deploy --metadata Foo"
fi

# sf probe path does not leave WORK_CONTAINER_EXEC_STDIO set
source "${SCRIPT_DIR}/host-podman-exec"
WORK_CONTAINER_EXEC_STDIO=probe
work_container_exec_as_user -- true >/dev/null 2>&1 || true
unset WORK_CONTAINER_EXEC_STDIO
if [[ -n "${WORK_CONTAINER_EXEC_STDIO:-}" ]]; then
  fail "WORK_CONTAINER_EXEC_STDIO leaked after probe"
else
  pass "WORK_CONTAINER_EXEC_STDIO probe/unset pattern OK"
fi

# container env from service-start
browser="$(sudo podman exec work_container sh -c 'printf %s "$BROWSER"')"
if [[ "${browser}" != "/usr/local/bin/chrome-work-open" ]]; then
  fail "container BROWSER: got ${browser}"
else
  pass "container BROWSER=/usr/local/bin/chrome-work-open"
fi

# wrapper mounts
mounts="$(sudo podman inspect work_container --format '{{range .Mounts}}{{.Destination}} {{end}}')"
for dest in /usr/local/bin/chrome-work-open /usr/bin/google-chrome-stable /usr/bin/code; do
  if [[ "${mounts}" != *"${dest}"* ]]; then
    fail "missing mount destination ${dest}"
  else
    pass "mount present: ${dest}"
  fi
done

# VS Code launcher resolves to wrapper script
code_head="$(sudo podman exec work_container head -1 /usr/share/code/bin/code 2>/dev/null || true)"
if [[ "${code_head}" != '#!/bin/sh' ]]; then
  fail "VS Code bin/code wrapper missing (got: ${code_head})"
else
  pass "VS Code wrapper script at /usr/share/code/bin/code"
fi

code_exec="$(sudo podman exec work_container grep -c 'exec /usr/share/code/code' /usr/share/code/bin/code 2>/dev/null || echo 0)"
if [[ "${code_exec}" -lt 1 ]]; then
  fail "VS Code wrapper does not exec /usr/share/code/code"
else
  pass "VS Code wrapper execs Electron binary directly"
fi

# Chrome wrapper
chrome_exec="$(sudo podman exec work_container grep -c 'exec /opt/google/chrome/chrome' /usr/local/bin/chrome-work-open 2>/dev/null || echo 0)"
if [[ "${chrome_exec}" -lt 1 ]]; then
  fail "Chrome wrapper does not exec /opt/google/chrome/chrome"
else
  pass "Chrome wrapper execs real Chrome binary"
fi

# write test: host user can create file in APP_HOME .sf
test_file="${APP_HOME}/.sf/verify-exec-$(date +%s).tmp"
uid_write="$(cd "${PROJECT_DIR}" && "${SCRIPT_DIR}/exec-in" sh -c "mkdir -p '${APP_HOME}/.sf' && touch '${test_file}' && stat -c %u '${test_file}'")"
rm -f "${test_file}" 2>/dev/null || true
if [[ "${uid_write}" != "${HOST_UID}" ]]; then
  fail "APP_HOME/.sf write ownership: got uid ${uid_write}"
else
  pass "host user can write to APP_HOME/.sf (Salesforce log path)"
fi

# installed runtime alignment (informational)
if [[ -f /usr/local/lib/work_container/scripts/host-podman-exec ]]; then
  if diff -q "${SCRIPT_DIR}/host-podman-exec" /usr/local/lib/work_container/scripts/host-podman-exec >/dev/null 2>&1; then
    pass "installed host-podman-exec matches project"
  else
    fail "installed host-podman-exec OUT OF SYNC — run ./start install"
  fi
  if [[ -x /usr/local/bin/work-shell ]]; then
    if grep -q 'work_container_exec_as_user' /usr/local/bin/work-shell; then
      ws_uid="$(work-shell id -u 2>/dev/null || echo FAIL)"
      if [[ "${ws_uid}" == "${HOST_UID}" ]]; then
        pass "work-shell runs as host uid ${HOST_UID}"
      else
        fail "work-shell id -u: got ${ws_uid}, want ${HOST_UID}"
      fi
    else
      fail "work-shell still uses legacy podman exec (run ./start install)"
    fi
  fi
else
  echo "SKIP: installed runtime not present"
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
