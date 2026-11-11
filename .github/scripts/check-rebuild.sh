#!/usr/bin/env bash
# =============================================================
#  check-rebuild.sh — does the weekly run need to build a new image?
#
#  The published image only goes stale in one way that no pull request
#  announces, so that is the one thing checked:
#    * apt: as root inside the published :latest image, `apt-get -s upgrade`
#      (a simulation) lists every package Debian, GitHub CLI or PGDG have
#      updated since the image was built. Any "Inst" line means a rebuild
#      picks up a fix.
#  Everything else is pinned (base image, uv, tool versions, Starship, the
#  Dockerfile frontend) and arrives as a Dependabot pull request or as a pull
#  request the weekly drift issue asks for, which reaches main through develop
#  and publishes normally.
#
#  A missing :latest (a fresh Docker Hub repository) always needs a build.
#
#  Inputs (environment): IMAGE (Docker Hub repository); optional REPORT (file
#  that receives the Markdown report; default stdout).
#  Outputs (GITHUB_OUTPUT, when set): rebuild=true|false.
#  Exit status: 0 on a decision, 1 when a check could not be made (a run that
#  cannot tell must fail loudly instead of silently skipping a rebuild).
# =============================================================
set -euo pipefail

: "${IMAGE:?IMAGE is required}"
report="${REPORT:-/dev/stdout}"
rebuild=false
rows=()
upgrades=()

note() { rows+=("| $1 | $2 |"); }

# ── Published image present? ────────────────────────────────
status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
  "https://hub.docker.com/v2/repositories/${IMAGE}/tags/latest" || true)"
case "${status}" in
  200) ;;
  404)
    rebuild=true
    note "Published image" "no \`latest\` tag on Docker Hub yet — **build**"
    ;;
  *)
    echo "::error::Unexpected answer from Docker Hub (HTTP ${status}) while looking for ${IMAGE}:latest."
    exit 1
    ;;
esac

if [ "${status}" = "200" ]; then
  docker pull --quiet "${IMAGE}:latest" > /dev/null

  # ── apt: anything newer than what the image was built with? ──
  apt_output="$(docker run --rm --user root "${IMAGE}:latest" \
    bash -c 'apt-get update -qq > /dev/null && apt-get -s upgrade')"
  while IFS= read -r line; do
    [[ "${line}" == Inst\ * ]] || continue
    name="${line#Inst }"
    name="${name%% *}"
    old=""
    if [[ "${line}" =~ \[([^]]+)\] ]]; then old="${BASH_REMATCH[1]}"; fi
    new="${line#*(}"
    new="${new%% *}"
    upgrades+=("${name} ${old} → ${new}")
  done <<< "${apt_output}"

  if [ "${#upgrades[@]}" -gt 0 ]; then
    rebuild=true
    note "apt packages" "${#upgrades[@]} upgrade(s) available — **build**"
  else
    note "apt packages" "up to date"
  fi
fi

# ── Report and output ───────────────────────────────────────
{
  echo "## Weekly rebuild check"
  echo
  echo "| Check | Result |"
  echo "| --- | --- |"
  printf '%s\n' "${rows[@]}"
  if [ "${#upgrades[@]}" -gt 0 ]; then
    echo
    echo "Packages that a rebuild upgrades:"
    echo
    # shellcheck disable=SC2016  # the backticks are literal Markdown
    printf -- '- `%s`\n' "${upgrades[@]}"
  fi
  echo
  if [ "${rebuild}" = true ]; then
    echo "**Result: rebuild.** Test, reserve a tag, publish, scan."
  else
    echo "**Result: nothing changed, no rebuild.** The published image is current; the run ends here."
  fi
} > "${report}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "rebuild=${rebuild}" >> "${GITHUB_OUTPUT}"
fi
