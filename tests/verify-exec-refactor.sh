#!/usr/bin/env bash
# Verification suite for APP_HOME + centralized exec refactor.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_SCRIPTS_DIR="${PROJECT_DIR}/scripts/host"
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
for f in host-podman-exec exec-in service-start install host-mounts resolve-paths \
  app-runners/chrome-work-open app-runners/vscode-work-open app-runners/cursor-work-open \
  wrappers/work-container-app; do
  bash -n "${HOST_SCRIPTS_DIR}/${f}" || { fail "syntax ${f}"; exit 1; }
done
pass "bash -n on all critical host scripts"

if ! grep -q 'return 0' "${HOST_SCRIPTS_DIR}/host-podman-exec"; then
  fail "podman_append_gui_session_env missing explicit return 0"
fi
pass "podman_append_gui_session_env has return 0"

# set -e must not kill callers of podman_append_gui_session_env
if ! bash -c 'set -euo pipefail; source "'"${HOST_SCRIPTS_DIR}"'/host-podman-exec"; EXEC_ARGS=(); podman_append_gui_session_env EXEC_ARGS; echo ok' >/dev/null 2>&1; then
  fail "podman_append_gui_session_env fails under set -euo pipefail"
else
  pass "podman_append_gui_session_env safe under set -euo pipefail"
fi

# Only ngrok DNS probe may use bare podman exec (read-only)
bare_exec_count="$(grep -r 'podman exec' "${HOST_SCRIPTS_DIR}" --include='*.sh' --include='install' --include='exec-in' --include='service-*' --include='run' --include='host-podman-exec' --include='wrappers/*' 2>/dev/null | grep -v 'host-podman-exec' | grep -v 'work_container_exec_as_user' | grep -v '#' | grep -c 'podman exec' || true)"
ngrok_probe="$(grep -c "podman exec work_container sh -lc 'getent" "${HOST_SCRIPTS_DIR}/wrappers/work-ngrok" || true)"
if [[ "${bare_exec_count}" -ne "${ngrok_probe}" ]]; then
  fail "unexpected bare podman exec outside ngrok getent probe (count=${bare_exec_count}, ngrok=${ngrok_probe})"
else
  pass "only intentional bare podman exec (ngrok getent DNS probe)"
fi

# service-start must set APP_HOME at podman run
if ! grep -q 'work_container_run_app_home_env' "${HOST_SCRIPTS_DIR}/service-start"; then
  fail "service-start missing work_container_run_app_home_env"
else
  pass "service-start sets APP_HOME env via work_container_run_app_home_env"
fi

require_container

# --- runtime checks ---
uid_out="$(cd "${PROJECT_DIR}" && "${HOST_SCRIPTS_DIR}/exec-in" id -u)"
if [[ "${uid_out}" != "${HOST_UID}" ]]; then
  fail "exec-in uid: got ${uid_out}, want ${HOST_UID}"
else
  pass "exec-in runs as host uid ${HOST_UID}"
fi

home_out="$(cd "${PROJECT_DIR}" && "${HOST_SCRIPTS_DIR}/exec-in" sh -c 'printf %s "$HOME"')"
if [[ "${home_out}" != "${APP_HOME}" ]]; then
  fail "container HOME: got ${home_out}, want ${APP_HOME}"
else
  pass "container HOME=${APP_HOME}"
fi

host_home_out="$(cd "${PROJECT_DIR}" && "${HOST_SCRIPTS_DIR}/exec-in" sh -c 'printf %s "$WORK_CONTAINER_HOST_HOME"')"
if [[ "${host_home_out}" != "${HOME}" ]]; then
  fail "WORK_CONTAINER_HOST_HOME: got ${host_home_out}, want ${HOME}"
else
  pass "WORK_CONTAINER_HOST_HOME=${HOME}"
fi

proj_dir="${HOME}/Projects"
wd_out="$(cd "${proj_dir}" && "${HOST_SCRIPTS_DIR}/exec-in" pwd)"
if [[ "${wd_out}" != "${proj_dir}" ]]; then
  fail "exec-in --workdir: got ${wd_out}, want ${proj_dir}"
else
  pass "exec-in --workdir follows caller PWD"
fi

deploy_uid="$(cd "${PROJECT_DIR}" && "${HOST_SCRIPTS_DIR}/exec-in" sh -c 'echo deploy-args:"$@"' -- sf deploy --metadata Foo 2>/dev/null | tail -1 || true)"

source "${HOST_SCRIPTS_DIR}/host-podman-exec"
browser="$(sudo podman exec work_container sh -c 'printf %s "$BROWSER"')"
if [[ "${browser}" != "/usr/local/bin/chrome-work-open" ]]; then
  fail "container BROWSER: got ${browser}"
else
  pass "container BROWSER=/usr/local/bin/chrome-work-open"
fi

for dest in /usr/local/bin/chrome-work-open /usr/bin/google-chrome-stable /usr/bin/code; do
  if ! sudo podman exec work_container test -e "${dest}"; then
    fail "missing mount ${dest}"
  fi
done
pass "chrome/code bind mounts present"

chrome_exec="$(sudo podman exec work_container grep -c 'exec /opt/google/chrome/chrome' /usr/local/bin/chrome-work-open 2>/dev/null || echo 0)"
if [[ "${chrome_exec}" -lt 1 ]]; then
  fail "chrome-work-open does not exec real chrome binary"
else
  pass "chrome-work-open execs /opt/google/chrome/chrome"
fi

test_file="${APP_HOME}/.sf/.verify-exec-refactor-uid"
uid_write="$(cd "${PROJECT_DIR}" && "${HOST_SCRIPTS_DIR}/exec-in" sh -c "mkdir -p '${APP_HOME}/.sf' && touch '${test_file}' && stat -c %u '${test_file}'")"
rm -f "${test_file}"
if [[ "${uid_write}" != "${HOST_UID}" ]]; then
  fail "APP_HOME write uid: got ${uid_write}, want ${HOST_UID}"
else
  pass "APP_HOME writes owned by host uid"
fi

if [[ -f /usr/local/lib/work_container/scripts/host-podman-exec ]]; then
  if diff -q "${HOST_SCRIPTS_DIR}/host-podman-exec" /usr/local/lib/work_container/scripts/host-podman-exec >/dev/null 2>&1; then
    pass "installed host-podman-exec matches project"
  else
    fail "installed host-podman-exec differs from project (re-run ./start install)"
  fi
else
  echo "SKIP: runtime bundle not installed"
fi

if [[ "${FAIL}" -ne 0 ]]; then
  echo "FAILED"
  exit 1
fi
echo "ALL PASS"
