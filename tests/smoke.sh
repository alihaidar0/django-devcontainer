#!/usr/bin/env bash
# =============================================================
#  tests/smoke.sh — runtime contract check for the dev image
#
#  Runs INSIDE the built image (CI runs it on amd64 and arm64
#  before anything is pushed):
#
#    docker run --rm -v "$PWD/tests:/tests:ro" django-devcontainer:test bash /tests/smoke.sh
#
#  Verifies what django-template relies on: the non-root user,
#  every advertised tool, the shell config, and that a project
#  .venv takes precedence over the image's global tools.
# =============================================================

set -euo pipefail

failures=0
pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1"; failures=$((failures + 1)); }

# expect "<description>" <test command...> — pass/fail on the exit status
expect() {
    local desc=$1; shift
    if "$@"; then pass "$desc"; else fail "$desc"; fi
}

# tool "<description>" <command...> — like expect, but prints the first output line
tool() {
    local desc=$1 out; shift
    if out=$("$@" 2>&1); then pass "$desc — ${out%%$'\n'*}"; else fail "$desc — ${out%%$'\n'*}"; fi
}

# Value of an expression in an interactive shell, the way a VS Code terminal starts one.
ishell() { bash -ic "$1" 2>/dev/null; }

echo "── User ─────────────────────────────────────────"
expect "runs as dev"                  test "$(id -un)" = dev
expect "UID:GID 1000:1000"            test "$(id -u):$(id -g)" = 1000:1000
expect "passwordless sudo"            sudo -n true
expect "/workspace writable"          test -w /workspace
expect "\$HOME/.ssh is mode 700"      test "$(stat -c %a "$HOME/.ssh")" = 700
expect "\$HOME/.cache/uv owned by dev"      test -O "$HOME/.cache/uv"
expect "\$HOME/.cache/pre-commit owned by dev" test -O "$HOME/.cache/pre-commit"
expect "\$HOME/.shell_history owned by dev" test -O "$HOME/.shell_history"
expect "everything in \$HOME owned by dev"  test -z "$(find "$HOME" ! -user dev -print -quit)"

echo "── Tools ────────────────────────────────────────"
tool "python 3.14"      bash -c 'python --version | grep -E "^Python 3\.14\."'
tool "uv"               uv --version
tool "uvx"              uvx --version
tool "pre-commit"       pre-commit --version
tool "watchfiles"       watchfiles --version
tool "psql 18"          bash -c 'psql --version | grep -E " 18\."'
tool "pg_dump 18"       bash -c 'pg_dump --version | grep -E " 18\."'
tool "pg_config (libpq headers, for psycopg[c])" pg_config --version
tool "redis-cli"        redis-cli --version
tool "git"              git --version
tool "gh"               gh --version
tool "jq"               jq --version
tool "ssh"              ssh -V
tool "gcc"              gcc --version
tool "make"             make --version
# Django i18n: makemessages / compilemessages need the GNU gettext tools.
tool "xgettext"         xgettext --version
tool "msgfmt"           msgfmt --version
# Django's zoneinfo support needs system tz data.
tool "tzdata"           python -c 'import zoneinfo; print(zoneinfo.ZoneInfo("Europe/Paris"))'
# starship exits 0 even when it can't write its cache — fail on the warning too.
# shellcheck disable=SC2016  # $out expands inside the inner bash
tool "starship"        bash -c 'out=$(starship --version 2>&1) && [[ $out != *"denied"* ]] && echo "$out"'

echo "── Pinned tool versions ─────────────────────────"
# Every name==version in the constraints file must be what's installed.
pins=/opt/uv-tools/requirements-tools.txt
expect "pins file present in image" test -r "$pins"
while IFS='=' read -r name _ version; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    dist="${name//-/_}-${version}.dist-info"   # wheel dist-info names use underscores
    expect "$name $version installed" \
        test -n "$(find /opt/uv-tools -path "*/site-packages/${dist}" -print -quit)"
done < <(sed 's/[[:space:]]//g' "$pins")

echo "── Shell config ─────────────────────────────────"
# shellcheck disable=SC2016  # the $VARs must expand inside the interactive shell
{
expect "Django aliases loaded"              test "$(ishell 'alias pmr')" = "alias pmr='python manage.py runserver 0.0.0.0:8000'"
expect "uv aliases loaded"                  test "$(ishell 'alias uvs')" = "alias uvs='uv sync'"
# The aliases django-template uses (its weekly contract check reads the same list).
for name in pm pmr pms pmm pmmk pmcs pmt pmsu; do
    expect "alias $name defined"            test -n "$(ishell "alias $name")"
done
expect "HISTFILE in \$HOME/.shell_history"  test "$(ishell 'echo $HISTFILE')" = "$HOME/.shell_history/.bash_history"
expect "HISTSIZE 50000 (not overridden)"    test "$(ishell 'echo $HISTSIZE')" = 50000
expect "PYTHONPATH=/workspace, no trailing colon" test "$(ishell 'echo $PYTHONPATH')" = /workspace
}

echo "── Project venv precedence ──────────────────────"
expect "/workspace/.venv/bin first on PATH" test "${PATH%%:*}" = /workspace/.venv/bin
# Login shells (VS Code's environment probe) re-run /etc/profile, which resets PATH.
# shellcheck disable=SC2016  # ${PATH} must expand inside the login shell
expect "/workspace/.venv/bin first in login shells too" \
    test "$(bash -lc 'echo "${PATH%%:*}"' 2>/dev/null)" = /workspace/.venv/bin
project=$(mktemp -d)
trap 'rm -rf "$project"' EXIT
uv venv --quiet "$project/.venv"
expect "a project .venv/bin wins over global tools" \
    test "$(PATH="$project/.venv/bin:$PATH" command -v python)" = "$project/.venv/bin/python"
expect "global tools isolated from system python" \
    bash -c '! python -c "import pre_commit" 2>/dev/null && ! python -c "import watchfiles" 2>/dev/null'

echo "── Left out on purpose ──────────────────────────"
# uv is the installer; pip (and the urllib3/msgpack copies vendored inside it) is removed.
expect "no system pip (uv is the installer)" bash -c '! python -m pip --version >/dev/null 2>&1 && ! command -v pip >/dev/null'
# shellcheck disable=SC2016  # $(command -v python) must expand inside the inner bash
expect "uv pip still works without pip"      bash -c 'uv pip list --python "$(command -v python)" >/dev/null'
# No aliases for tools the image does not contain (celery is project-level, there is no docker CLI).
# shellcheck disable=SC2016  # the alias names are looked up inside the interactive shell
expect "no celery or docker aliases" test -z "$(ishell 'alias cw cb cf dps')"
expect "no git-lfs (not needed by every project)" bash -c '! command -v git-lfs >/dev/null'
# Project tooling is pinned per project in uv.lock, never baked in.
for tool in ruff mypy celery flower ipython pgcli http pytest; do
    expect "no global $tool (project-level)" bash -c "! command -v $tool >/dev/null"
done

echo "─────────────────────────────────────────────────"
if (( failures > 0 )); then
    echo "❌ $failures check(s) failed"
    exit 1
fi
echo "✅ All smoke checks passed"
