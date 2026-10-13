#!/usr/bin/env bash
# =============================================================
#  test-check-rebuild.sh — tests check-rebuild.sh with stubbed docker, curl and
#  nothing else, so the decision logic is checked on every Lint run without
#  touching Docker Hub, GitHub or a container. Needs only bash.
# =============================================================
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-rebuild.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/bin"

# docker stub: `pull` succeeds; `run … apt-get …` prints $APT_OUTPUT;
# any other `run` (starship --version) prints $STARSHIP_INSTALLED.
cat > "${work}/bin/docker" << 'EOF'
#!/usr/bin/env bash
case "$1" in
  pull) exit 0 ;;
  run)
    if [[ "$*" == *apt-get* ]]; then
      printf '%s\n' "${APT_OUTPUT:-}"
    else
      echo "starship ${STARSHIP_INSTALLED:-1.26.0}"
      echo "branch:master"
    fi
    ;;
esac
EOF

# curl stub: the Docker Hub URL answers $HUB_STATUS (default 200); the GitHub
# API answers the newest Starship release, or fails when STARSHIP_FAIL is set.
cat > "${work}/bin/curl" << 'EOF'
#!/usr/bin/env bash
url="${*: -1}"
if [[ "${url}" == *hub.docker.com* ]]; then echo "${HUB_STATUS:-200}"; exit 0; fi
if [ -n "${STARSHIP_FAIL:-}" ]; then exit 22; fi
echo "{\"tag_name\": \"v${STARSHIP_LATEST:-1.26.0}\", \"name\": \"v${STARSHIP_LATEST:-1.26.0}\"}"
EOF
chmod +x "${work}/bin/docker" "${work}/bin/curl"

failures=0

# run NAME EXPECTED_EXIT EXPECTED_REBUILD [VAR=value ...]  (EXPECTED_REBUILD "" = no output expected)
run() {
  local name="$1" expected_exit="$2" expected_rebuild="$3"
  shift 3
  local out="${work}/output" report="${work}/report" status=0
  : > "${out}"
  : > "${report}"
  env PATH="${work}/bin:${PATH}" IMAGE=owner/image GITHUB_OUTPUT="${out}" REPORT="${report}" \
    "$@" bash "${script}" > "${work}/log" 2>&1 || status=$?
  local rebuild
  rebuild="$(sed -n 's/^rebuild=//p' "${out}")"
  if [ "${status}" -eq "${expected_exit}" ] && [ "${rebuild}" = "${expected_rebuild}" ]; then
    echo "ok   ${name}"
  else
    echo "FAIL ${name}: exit ${status} (want ${expected_exit}), rebuild '${rebuild}' (want '${expected_rebuild}')"
    sed 's/^/     /' "${work}/log" "${report}"
    failures=$((failures + 1))
  fi
}

apt_inst='Inst libssl3t64 [3.5.7-1~deb13u2] (3.5.7-1~deb13u3 Debian-Security:13/stable-security [amd64])'
apt_noise=$'Reading package lists...\nBuilding dependency tree...\nConf libssl3t64 (3.5.7-1~deb13u3 Debian-Security:13/stable-security [amd64])'

run "nothing changed: no rebuild"                 0 false
run "an apt upgrade is available"                 0 true  APT_OUTPUT="${apt_inst}"
run "apt noise without an Inst line is ignored"   0 false APT_OUTPUT="${apt_noise}"
run "Starship has a newer release"                0 true  STARSHIP_INSTALLED=1.25.0
run "Starship release feed unreachable is not drift" 0 false STARSHIP_FAIL=1
run "no published image yet: build"               0 true  HUB_STATUS=404
run "stops on an unexpected Docker Hub answer"    1 ""    HUB_STATUS=500

# The report names the packages that a rebuild upgrades.
: > "${work}/output"
env PATH="${work}/bin:${PATH}" IMAGE=owner/image GITHUB_OUTPUT="${work}/output" REPORT="${work}/report" \
  APT_OUTPUT="${apt_inst}" bash "${script}" > /dev/null 2>&1
if grep -q 'libssl3t64 3.5.7-1~deb13u2 → 3.5.7-1~deb13u3' "${work}/report"; then
  echo "ok   the report lists the upgraded package with both versions"
else
  echo "FAIL the report does not list the upgraded package"
  sed 's/^/     /' "${work}/report"
  failures=$((failures + 1))
fi

if [ "${failures}" -ne 0 ]; then
  echo "${failures} test(s) failed."
  exit 1
fi
echo "All check-rebuild tests passed."
