#!/usr/bin/env bash
# =============================================================
#  release-notes.sh — release notes from the PR titles merged since the last release.
#
#  Usage: release-notes.sh FROM TO
#    FROM  previous release tag (empty: the 50 newest commits up to TO)
#    TO    the tag or commit being released
#
#  Every change reaches develop through a PR that is merged with a merge commit,
#  so the merge commits in FROM..TO are the PRs, and each one carries the PR title:
#    * as its subject ("feat: add gettext (#12)") when the repository's merge
#      message setting is "Pull request title (and description)", or
#    * as the first line of its body, under "Merge pull request #12 from …", with
#      the default message.
#  This groups those titles by Conventional Commit type. Skipped: the develop → main
#  release merge itself (a first-parent merge of the range), and "Merge branch …"
#  syncs. The commits inside a PR are not listed. Prints Markdown.
#  Run it inside a clone that has the full history of both refs.
#
#  The title handling is in functions so tests/test-release-notes.sh can source
#  this file (the git part only runs when the file is executed).
# =============================================================
set -euo pipefail

sections=("Breaking changes" "Features" "Bug fixes" "Dependency updates" "CI and automation" "Documentation" "Maintenance" "Other changes")
declare -A items=()

add() { items["$1"]+="- $2 (\`$3\`)"$'\n'; }

# first_line_of_body: the first non-empty line of the message body on stdin.
first_line_of_body() { sed -n '/[^[:space:]]/{p;q}'; }

# add_title SHORT SUBJECT BREAKING(true|false): file one PR title under its section.
add_title() {
  local short="$1" subject="$2" breaking="$3"
  local type="" scope="" bang="" text="${subject}"
  if [[ "${subject}" =~ ^([a-z]+)(\(([^\)]+)\))?(!)?:[[:space:]]+(.*)$ ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"
    bang="${BASH_REMATCH[4]}"
    text="${BASH_REMATCH[5]}"
    # The "deps" scope is already the section title; other scopes stay as a prefix.
    if [ -n "${scope}" ] && [ "${scope}" != "deps" ]; then text="**${scope}**: ${text}"; fi
  fi

  if [ -n "${bang}" ] || [ "${breaking}" = true ]; then
    add "Breaking changes" "${text}" "${short}"
    return
  fi

  case "${type}" in
    feat) add "Features" "${text}" "${short}" ;;
    fix) add "Bug fixes" "${text}" "${short}" ;;
    build | ci)
      if [ "${scope}" = "deps" ]; then
        add "Dependency updates" "${text}" "${short}"
      elif [ "${type}" = "ci" ]; then
        add "CI and automation" "${text}" "${short}"
      else
        add "Maintenance" "${text}" "${short}"
      fi
      ;;
    docs) add "Documentation" "${text}" "${short}" ;;
    chore | refactor | perf | style | test | revert) add "Maintenance" "${text}" "${short}" ;;
    *) add "Other changes" "${text}" "${short}" ;;
  esac
}

# render: print the sections that have entries, or the "no PRs" line.
render() {
  local printed=0 section
  for section in "${sections[@]}"; do
    [ -z "${items[${section}]:-}" ] && continue
    printf '### %s\n\n%s\n' "${section}" "${items[${section}]}"
    printed=1
  done
  if [ "${printed}" -eq 0 ]; then
    echo "No pull requests since the previous release: this image is a rebuild with updated operating-system packages and tools."
  fi
}

main() {
  local from="${1-}" to="${2:?usage: release-notes.sh FROM TO}"
  local range

  # Fail loudly on a bad ref: an unreadable range must never read as "no changes".
  git rev-parse --verify --quiet "${to}^{commit}" > /dev/null \
    || { echo "::error::release-notes.sh: '${to}' is not a commit in this clone." >&2; exit 1; }
  if [ -n "${from}" ]; then
    git rev-parse --verify --quiet "${from}^{commit}" > /dev/null \
      || { echo "::error::release-notes.sh: '${from}' is not a commit in this clone." >&2; exit 1; }
    range=("${from}..${to}")
  else
    range=("-n" "50" "${to}")
  fi

  # The release merge is a first-parent merge of the range (it sits on main); the PR
  # merges it brought in sit on develop's side and are not first-parent commits.
  local first_parent breaking_hashes
  first_parent="$(git rev-list --first-parent "${range[@]}")"
  # Merge commits whose message carries a "BREAKING CHANGE:" footer.
  breaking_hashes="$(git log --merges --format='%H' --grep='^BREAKING CHANGE:' "${range[@]}")"

  local full short subject title breaking
  while IFS= read -r full; do
    [ -z "${full}" ] && continue
    grep -qxF -- "${full}" <<< "${first_parent}" && continue

    short="$(git log -1 --format='%h' "${full}")"
    subject="$(git log -1 --format='%s' "${full}")"

    # Branch syncs are not changes.
    case "${subject}" in "Merge branch "* | "Merge remote-tracking branch "*) continue ;; esac

    # With the default merge message the PR title is the first non-empty body line.
    if [[ "${subject}" =~ ^Merge\ pull\ request\ \#[0-9]+\ from\  ]]; then
      title="$(git log -1 --format='%b' "${full}" | first_line_of_body)"
      [ -n "${title}" ] && subject="${title}"
    fi

    breaking=false
    if grep -qxF -- "${full}" <<< "${breaking_hashes}"; then breaking=true; fi
    add_title "${short}" "${subject}" "${breaking}"
  done < <(git log --merges --format='%H' "${range[@]}")

  render
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
