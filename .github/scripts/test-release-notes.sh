#!/usr/bin/env bash
# =============================================================
#  test-release-notes.sh — tests the title handling of release-notes.sh: which
#  section a PR title lands in, and how the title is read from a merge commit
#  written with the default message. Needs only bash; no git history is touched.
# =============================================================
set -euo pipefail

# shellcheck disable=SC1091  # path is resolved at run time; Lint runs ShellCheck without -x
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release-notes.sh"

failures=0

# expect_section NAME TITLE BREAKING EXPECTED_SECTION EXPECTED_TEXT
expect_section() {
  local name="$1" title="$2" breaking="$3" section="$4" text="$5"
  items=()
  add_title abc1234 "${title}" "${breaking}"
  local got="${items[${section}]:-}"
  if [ "${got}" = "- ${text} (\`abc1234\`)"$'\n' ]; then
    echo "ok   ${name}"
  else
    echo "FAIL ${name}: section '${section}' holds '${got}' (want '- ${text} (\`abc1234\`)')"
    failures=$((failures + 1))
  fi
}

expect_section "feat is a feature"                   "feat: add gettext (#12)"                     false "Features"           "add gettext (#12)"
expect_section "fix with a scope keeps the scope"    "fix(docker): correct the apt list (#13)"     false "Bug fixes"          "**docker**: correct the apt list (#13)"
expect_section "build(deps) is a dependency update"  "build(deps): bump python to 3.14.8 (#14)"    false "Dependency updates" "bump python to 3.14.8 (#14)"
expect_section "ci(deps) is a dependency update"     "ci(deps): bump the actions group (#15)"      false "Dependency updates" "bump the actions group (#15)"
expect_section "ci is automation"                    "ci(workflows): speed up lint (#16)"          false "CI and automation"  "**workflows**: speed up lint (#16)"
expect_section "build without deps is maintenance"   "build: tidy the Dockerfile (#17)"           false "Maintenance"        "tidy the Dockerfile (#17)"
expect_section "docs is documentation"               "docs: explain the tags (#18)"                false "Documentation"      "explain the tags (#18)"
expect_section "chore is maintenance"                "chore: rename a script (#19)"                false "Maintenance"        "rename a script (#19)"
expect_section "a bang is a breaking change"         "feat!: slim the image (#20)"                 false "Breaking changes"   "slim the image (#20)"
expect_section "a BREAKING CHANGE footer is breaking" "fix: change the user (#21)"                 true  "Breaking changes"   "change the user (#21)"
expect_section "a non-conventional title is other"   "Update the readme (#22)"                     false "Other changes"      "Update the readme (#22)"

# Default merge message: the PR title is the first non-empty line of the body.
body=$'\n\nfix(docker): correct the apt list\n\nLonger description.\n'
got="$(first_line_of_body <<< "${body}")"
if [ "${got}" = "fix(docker): correct the apt list" ]; then
  echo "ok   the PR title is read from the merge commit body"
else
  echo "FAIL the PR title was read as '${got}'"
  failures=$((failures + 1))
fi

# Nothing filed: the "no pull requests" line.
items=()
if [[ "$(render)" == "No pull requests since the previous release"* ]]; then
  echo "ok   an empty range says so"
else
  echo "FAIL an empty range printed something else"
  failures=$((failures + 1))
fi

# Sections come out in a fixed order.
items=()
add_title a1 "docs: d" false
add_title b2 "feat: f" false
add_title c3 "fix!: x" false
order="$(render | sed -n 's/^### //p' | tr '\n' ',')"
if [ "${order}" = "Breaking changes,Features,Documentation," ]; then
  echo "ok   sections are ordered breaking → features → docs"
else
  echo "FAIL section order was '${order}'"
  failures=$((failures + 1))
fi

if [ "${failures}" -ne 0 ]; then
  echo "${failures} test(s) failed."
  exit 1
fi
echo "All release-notes tests passed."
