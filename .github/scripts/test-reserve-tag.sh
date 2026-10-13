#!/usr/bin/env bash
# =============================================================
#  test-reserve-tag.sh — tests reserve-tag.sh with stubbed curl and gh, so the
#  revision logic is checked on every Lint run without touching Docker Hub or
#  GitHub. Needs only bash.
# =============================================================
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reserve-tag.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/bin"

# curl stub: prints the status for the revision named in the URL. HUB_TAKEN is a
# list of revisions that exist on Docker Hub; HUB_STATUS forces one answer.
cat > "${work}/bin/curl" << 'EOF'
#!/usr/bin/env bash
url="${*: -1}"
revision="${url##*.}"
if [ -n "${HUB_STATUS:-}" ]; then echo "${HUB_STATUS}"; exit 0; fi
for taken in ${HUB_TAKEN:-}; do
  if [ "${taken}" = "${revision}" ]; then echo 200; exit 0; fi
done
echo 404
EOF

# gh stub: GH_TAKEN revisions answer HTTP 422 (existing tag or reserved name),
# GH_FAIL answers HTTP 403, everything else is created.
cat > "${work}/bin/gh" << 'EOF'
#!/usr/bin/env bash
for argument in "$@"; do
  case "${argument}" in ref=refs/tags/*) ref="${argument#ref=refs/tags/}" ;; esac
done
revision="${ref##*.}"
if [ -n "${GH_FAIL:-}" ]; then echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1; fi
for taken in ${GH_TAKEN:-}; do
  if [ "${taken}" = "${revision}" ]; then echo "gh: Repository rule violations found (HTTP 422)" >&2; exit 1; fi
done
echo '{}'
EOF
chmod +x "${work}/bin/curl" "${work}/bin/gh"

failures=0

# run NAME EXPECTED_EXIT EXPECTED_TAG [VAR=value ...]
run() {
  local name="$1" expected_exit="$2" expected_tag="$3"
  shift 3
  local out="${work}/output" status=0
  : > "${out}"
  env PATH="${work}/bin:${PATH}" IMAGE=owner/image PYTHON_VERSION=3.14.7 GH_REPO=owner/repo \
    TARGET_SHA=abc123 GH_TOKEN=x GITHUB_OUTPUT="${out}" "$@" bash "${script}" > "${work}/log" 2>&1 || status=$?
  local tag
  tag="$(sed -n 's/^tag=//p' "${out}")"
  if [ "${status}" -eq "${expected_exit}" ] && [ "${tag}" = "${expected_tag}" ]; then
    echo "ok   ${name}"
  else
    echo "FAIL ${name}: exit ${status} (want ${expected_exit}), tag '${tag}' (want '${expected_tag}')"
    sed 's/^/     /' "${work}/log"
    failures=$((failures + 1))
  fi
}

run "first revision is free"                      0 python-3.14.7.1
run "skips revisions taken on Docker Hub"         0 python-3.14.7.3 HUB_TAKEN="1 2"
run "skips names GitHub refuses (422)"            0 python-3.14.7.3 GH_TAKEN="1 2"
run "skips a mix of both"                         0 python-3.14.7.4 HUB_TAKEN="1" GH_TAKEN="2 3"
run "stops on an unexpected Docker Hub answer"    1 ""              HUB_STATUS=500
run "stops on a network failure (000)"            1 ""              HUB_STATUS=000
run "stops on a GitHub error other than 422"      1 ""              GH_FAIL=1
run "fails when every revision is taken"          1 ""              MAX_REVISION=2 HUB_TAKEN="1 2"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} test(s) failed."
  exit 1
fi
echo "All reserve-tag tests passed."
