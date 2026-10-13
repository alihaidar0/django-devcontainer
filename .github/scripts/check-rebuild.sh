#!/usr/bin/env bash
# =============================================================
#  check-rebuild.sh — does the weekly run need to build a new image?
#
#  The published image only goes stale in two ways that no pull request
#  announces, so those are the two things checked:
#    * apt: as root inside the published :latest image, `apt-get -s upgrade`
#      (a simulation) lists every package Debian, GitHub CLI or PGDG have
#      updated since the image was built. Any "Inst" line means a rebuild
#      picks up a fix.
#    * Starship: it is installed from its latest release, not pinned, so the
#      installed version is compared with the newest release.
#  Everything else is pinned (base image, uv, tool versions) and arrives as a
#  Dependabot pull request, which reaches main through develop and publishes
#  normally.
#
#  A missing :latest (a fresh Docker Hub repository) always needs a build.
#
#  Inputs (environment): IMAGE (Docker Hub repository); optional REPORT (file
#  that receives the Markdown report; default stdout), GITHUB_TOKEN (raises the
#  GitHub API rate limit).
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

  # ── Starship: installed vs newest release ──
  installed="$(docker run --rm "${IMAGE}:latest" starship --version | sed -n '1s/^starship \([0-9][0-9.]*\).*/\1/p')"
  if [ -z "${installed}" ]; then
    echo "::error::Could not read the Starship version from ${IMAGE}:latest."
    exit 1
  fi
  auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}"); fi
  if latest_json="$(curl -fsS --max-time 20 "${auth[@]}" \
    "https://api.github.com/repos/starship/starship/releases/latest" 2> /dev/null)"; then
    latest="$(sed -n 's/.*"tag_name": *"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' <<< "${latest_json}" | head -1)"
  else
    latest=""
  fi
  if [ -z "${latest}" ]; then
    # An unreachable release feed is not drift; the apt check and the next run still apply.
    note "Starship" "${installed} installed; newest release could not be read (not counted)"
  elif [ "${installed}" != "${latest}" ]; then
    rebuild=true
    note "Starship" "${installed} installed, ${latest} released — **build**"
  else
    note "Starship" "${installed} is the newest release"
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
