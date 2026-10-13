#!/usr/bin/env bash
# =============================================================
#  reserve-tag.sh — pick the next image revision and reserve its git tag.
#
#  Every published image gets a permanent name python-X.Y.Z.R (Python X.Y.Z,
#  image revision R). R is the first number that is free in BOTH places that
#  must agree:
#    * Docker Hub: no image with that tag exists (checked anonymously, the
#      repository is public), and
#    * GitHub: the git tag can be created. GitHub refuses it when the tag already
#      exists, or when the name was used by an immutable release: such a name stays
#      reserved for good, even after the release and its tag were deleted.
#
#  The tag is created here, before anything is pushed to Docker Hub, so the image
#  and the release that follows can never disagree about a name. A failed run can
#  leave an unused tag behind, which only costs one number.
#
#  Inputs (environment): IMAGE (Docker Hub repository), PYTHON_VERSION (X.Y.Z),
#  GH_REPO, TARGET_SHA, GH_TOKEN (for gh); optional MAX_REVISION (default 99).
#  Outputs (GITHUB_OUTPUT, when set): tag, number.
# =============================================================
set -euo pipefail

: "${IMAGE:?IMAGE is required}"
: "${PYTHON_VERSION:?PYTHON_VERSION is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${TARGET_SHA:?TARGET_SHA is required}"
max_revision="${MAX_REVISION:-99}"

for revision in $(seq 1 "${max_revision}"); do
  tag="python-${PYTHON_VERSION}.${revision}"

  # Only a clean "not found" means free; anything unexpected must stop the run
  # instead of being mistaken for a free name.
  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    "https://hub.docker.com/v2/repositories/${IMAGE}/tags/${tag}" || true)"
  case "${status}" in
    200)
      echo "${tag} already exists on Docker Hub."
      continue
      ;;
    404) ;;
    *)
      echo "::error::Unexpected answer from Docker Hub (HTTP ${status}) while checking ${tag}."
      exit 1
      ;;
  esac

  if output="$(gh api "repos/${GH_REPO}/git/refs" \
    -f "ref=refs/tags/${tag}" -f "sha=${TARGET_SHA}" 2>&1)"; then
    echo "Reserved ${tag}."
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      {
        echo "tag=${tag}"
        echo "number=${revision}"
      } >> "${GITHUB_OUTPUT}"
    fi
    exit 0
  fi

  # 422 means GitHub refused this name: the tag exists, or the name is reserved by
  # an immutable release. Any other failure (permissions, outage) is a real error.
  if grep -q 'HTTP 422' <<< "${output}"; then
    echo "::notice::${tag} is not available on GitHub (existing tag or a name used by an immutable release); trying the next revision."
    continue
  fi
  echo "::error::Could not reserve ${tag}: ${output}"
  exit 1
done

echo "::error::No free revision for Python ${PYTHON_VERSION} (1-${max_revision} are taken)."
exit 1
