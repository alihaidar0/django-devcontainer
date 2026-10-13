#!/usr/bin/env bash
# =============================================================
#  check-readme-sync.sh — keep README.md and the implementation in step.
#  README.md is also the Docker Hub page, so a stale table is public.
#
#  Fails when:
#    * an alias defined in scripts/shell_setup.sh is missing from the README
#      "Shell aliases" table, or the README documents an alias that is gone,
#    * a CLI pinned in docker/requirements-tools.txt is not named in the README,
#    * an apt package installed by docker/Dockerfile.dev is not mentioned in the
#      README (a few are matched by their command name: ping, dig, nc, …),
#    * the README is larger than 24 000 bytes (Docker Hub truncates at 25 000),
#    * the Python minor, the PostgreSQL major or the Debian codename in
#      docker/Dockerfile.dev is not what the README says,
#    * the formats django-template parses (ARG PG_MAJOR, the python and uv FROM
#      lines, the eight aliases it uses) drifted, or the README stopped
#      documenting them,
#    * a workflow in .github/workflows/ is missing from the README
#      "Repository structure" tree.
#
#  Run from anywhere inside the repository.
# =============================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

dockerfile="docker/Dockerfile.dev"
tools="docker/requirements-tools.txt"
aliases_script="scripts/shell_setup.sh"
readme="README.md"
status=0

fail() { echo "::error::$*"; status=1; }

# ── Aliases ──────────────────────────────────────────────────
script_aliases="$(grep -oE '^alias [A-Za-z0-9_]+' "${aliases_script}" | cut -d' ' -f2 | sort -u || true)"

# Inline-code words in the table rows (lines starting "| **") of the
# "## Shell aliases" section. Code that is not a bare word (`-A config`) is skipped.
# shellcheck disable=SC2016  # the backticks are literal Markdown, not command substitution
readme_aliases="$(
  awk '
    /^## Shell aliases/ { in_section = 1; next }
    /^## /              { in_section = 0 }
    in_section && /^\| \*\*/ { print }
  ' "${readme}" | grep -oE '`[A-Za-z0-9_]+`' | tr -d '`' | sort -u
)"

if [ -z "${script_aliases}" ] || [ -z "${readme_aliases}" ]; then
  fail "Could not read the alias lists (${aliases_script} / ${readme} 'Shell aliases' table)."
fi

while IFS= read -r name; do
  [ -z "${name}" ] && continue
  grep -qxF -- "${name}" <<< "${readme_aliases}" \
    || fail "Alias '${name}' is defined in ${aliases_script} but missing from the README alias table."
done <<< "${script_aliases}"

while IFS= read -r name; do
  [ -z "${name}" ] && continue
  grep -qxF -- "${name}" <<< "${script_aliases}" \
    || fail "Alias '${name}' is documented in the README but not defined in ${aliases_script}."
done <<< "${readme_aliases}"

# ── Pinned CLIs ──────────────────────────────────────────────
tool_names="$(grep -oE '^[A-Za-z0-9_.-]+==' "${tools}" | sed 's/==$//' || true)"
if [ -z "${tool_names}" ]; then
  fail "Could not read any 'name==version' pin from ${tools}."
fi
while IFS= read -r name; do
  [ -z "${name}" ] && continue
  grep -qiF -- "${name}" "${readme}" \
    || fail "${tools} pins '${name}' but the README never mentions it."
done <<< "${tool_names}"

# ── Size ─────────────────────────────────────────────────────
# The README is also the Docker Hub page, and Docker Hub truncates it at 25 000
# bytes. Keep a margin, so one more paragraph cannot silently cut the page.
readme_bytes="$(wc -c < "${readme}" | tr -d ' ')"
if [ "${readme_bytes}" -gt 24000 ]; then
  fail "README is ${readme_bytes} bytes; keep it under 24000 (Docker Hub truncates at 25000). Move detail to docs/ or CONTRIBUTING."
fi

# ── apt packages ─────────────────────────────────────────────
# Every package in the Dockerfile's apt install list must be documented. The README
# uses the command name for a few (ping, dig, nc, redis-cli, psql, libpq), listed here.
declare -A apt_readme_name=(
  [libpq-dev]="libpq" [iputils-ping]="ping" [bind9-dnsutils]="dig" [netcat-openbsd]="nc"
  [redis-tools]="redis-cli" [openssh-client]="openssh-client" [ca-certificates]=""
)
pg_for_apt="$(grep -oE '^ARG PG_MAJOR=[0-9]+' "${dockerfile}" | head -1 | cut -d= -f2 || true)"
apt_packages="$(
  awk '/apt-get install -y --no-install-recommends \\$/ { on = 1; next }
       /apt-get clean/ { on = 0 }
       on' "${dockerfile}" \
    | sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]*\\$//' \
    | tr -s ' ' '\n' | tr -d '"' | sed "s/\${PG_MAJOR}/${pg_for_apt}/" | grep -E '^[a-z0-9][a-z0-9+.-]*$' || true
)"
apt_packages="$(printf '%s\ncurl\n' "${apt_packages}")"
if [ "$(grep -c . <<< "${apt_packages}")" -lt 15 ]; then
  fail "Could not read the apt package list from ${dockerfile} (found: $(tr '\n' ' ' <<< "${apt_packages}"))."
fi
while IFS= read -r package; do
  [ -z "${package}" ] && continue
  name="${apt_readme_name[${package}]-${package}}"
  [ -z "${name}" ] && continue
  case "${package}" in postgresql-client-*) name="PostgreSQL **${package##*-}**" ;; esac
  grep -qiF -- "${name}" "${readme}" \
    || fail "apt package '${package}' is installed by ${dockerfile} but the README never mentions '${name}'."
done <<< "${apt_packages}"

# ── Python, PostgreSQL, Debian ───────────────────────────────
python_minor="$(grep -oE '^FROM python:[0-9]+\.[0-9]+' "${dockerfile}" | head -1 | sed 's/^FROM python://' || true)"
if [ -z "${python_minor}" ]; then
  fail "Could not read the Python version from the FROM line in ${dockerfile}."
else
  grep -qF -- "python:${python_minor}-slim" "${readme}" \
    || fail "README does not name the base image python:${python_minor}-slim-… (Dockerfile pins ${python_minor})."
  grep -qF -- "Python ${python_minor}" "${readme}" \
    || fail "README does not describe 'Python ${python_minor}' (Dockerfile pins ${python_minor})."
  # The moving tag of the current Python line (published as python-X.Y).
  grep -qF -- "\`python-${python_minor}\`" "${readme}" \
    || fail "README does not document the tag 'python-${python_minor}' (Tags section)."
fi

pg_major="$(grep -oE '^ARG PG_MAJOR=[0-9]+' "${dockerfile}" | head -1 | cut -d= -f2 || true)"
if [ -z "${pg_major}" ]; then
  fail "Could not read ARG PG_MAJOR from ${dockerfile}."
else
  grep -qF -- "PostgreSQL **${pg_major}**" "${readme}" \
    || fail "README does not say 'PostgreSQL **${pg_major}**' (Dockerfile installs postgresql-client-${pg_major})."
fi

debian="$(grep -oE '^FROM python:[^ @]+-slim-[a-z]+' "${dockerfile}" | head -1 | sed 's/.*-slim-//' || true)"
if [ -z "${debian}" ]; then
  fail "Could not read the Debian codename from the FROM line in ${dockerfile}."
else
  grep -qF -- "slim-${debian}" "${readme}" \
    || fail "README does not name the Debian base 'slim-${debian}'."
fi

# ── Contract parsed by django-template ───────────────────────
# Its weekly check reads these four formats from main; they are documented in
# the README ("Parsed by django-template") and must not drift silently.
grep -qE '^ARG PG_MAJOR=[0-9]+$' "${dockerfile}" \
  || fail "Contract: ${dockerfile} needs one line 'ARG PG_MAJOR=NN' (django-template parses it)."
first_python="$(grep -E '^FROM python:' "${dockerfile}" | head -1 || true)"
[[ "${first_python}" =~ ^FROM\ python:[0-9]+\.[0-9]+\.[0-9]+ ]] \
  || fail "Contract: the first 'FROM python:' line in ${dockerfile} must read FROM python:X.Y.Z… (got '${first_python}')."
grep -qE '^FROM ghcr\.io/astral-sh/uv:[0-9]+\.[0-9]+\.[0-9]+@sha256:' "${dockerfile}" \
  || fail "Contract: ${dockerfile} needs 'FROM ghcr.io/astral-sh/uv:X.Y.Z@sha256:…' (django-template parses it)."
for contract_alias in pm pmr pms pmm pmmk pmcs pmt pmsu; do
  grep -qE "^alias ${contract_alias}=" "${aliases_script}" \
    || fail "Contract: ${aliases_script} must define 'alias ${contract_alias}=' on its own line (django-template uses it)."
done
for contract_text in 'Parsed by django-template' 'ARG PG_MAJOR=NN' 'FROM ghcr.io/astral-sh/uv:X.Y.Z@' 'check-image-contract.sh'; do
  grep -qF -- "${contract_text}" "${readme}" \
    || fail "README must document the contract: '${contract_text}' is missing from 'Parsed by django-template'."
done

# ── Workflows listed in the structure tree ───────────────────
for workflow in .github/workflows/*.yml; do
  base="$(basename "${workflow}")"
  grep -qF -- "${base}" "${readme}" \
    || fail "${workflow} is not listed in the README 'Repository structure' tree."
done

if [ "${status}" -eq 0 ]; then
  echo "README and implementation are in sync."
fi
exit "${status}"
