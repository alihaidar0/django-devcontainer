#!/usr/bin/env bash
# =============================================================
#  shell_setup.sh
#  Runs once at image build time (Dockerfile.dev RUN step, as root).
#  Installs the Starship prompt and writes a user-agnostic shell
#  config that every user of the image (dev, root) picks up:
#
#    /etc/starship.toml       prompt config (STARSHIP_CONFIG)
#    /etc/bash.devcontainer   aliases, history, prompt init
#
#  The config is sourced from /etc/skel/.bashrc (copied into every
#  new user's home) and /root/.bashrc — at the END, so it wins over
#  the Debian defaults (e.g. HISTSIZE) set earlier in .bashrc.
# =============================================================

set -euo pipefail

# ── Starship prompt ──────────────────────────────────────────
# The newest release, downloaded as a tarball and checked against the SHA-256
# that the same release publishes — no remote install script is run. The tag is
# resolved once, so the tarball and its checksum always belong together. (This
# catches a corrupted or tampered download; it cannot catch a release that was
# itself compromised, which is why the weekly rebuild check compares the
# installed version with the newest release.)
case "$(dpkg --print-architecture)" in
  amd64) starship_target=x86_64-unknown-linux-musl ;;
  arm64) starship_target=aarch64-unknown-linux-musl ;;
  *) echo "Unsupported architecture for Starship: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac
starship_tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/starship/starship/releases/latest)"
starship_tag="${starship_tag##*/}"
starship_url="https://github.com/starship/starship/releases/download/${starship_tag}/starship-${starship_target}.tar.gz"
starship_dir="$(mktemp -d)"
curl -fsSL -o "${starship_dir}/starship.tar.gz" "${starship_url}"
starship_sha="$(curl -fsSL "${starship_url}.sha256")"
echo "${starship_sha}  ${starship_dir}/starship.tar.gz" | sha256sum --check --status
tar -xzf "${starship_dir}/starship.tar.gz" -C /usr/local/bin starship
chmod 0755 /usr/local/bin/starship
rm -rf "${starship_dir}"

cat > /etc/starship.toml << 'STARSHIP'
format = """
[╭─](bold green)$directory$git_branch$git_status$python
[╰─❯](bold green) """

[directory]
style = "bold cyan"
truncation_length = 4
truncate_to_repo = true

[git_branch]
symbol = " "
style = "bold purple"

[git_status]
style = "bold red"

[python]
symbol = " "
style = "bold yellow"
format = "[$symbol$version]($style) "
STARSHIP

# ── Shared shell config ──────────────────────────────────────
cat > /etc/bash.devcontainer << 'BASHRC'
# Shared interactive shell config for django-devcontainer.
# Sourced at the end of ~/.bashrc. Do not edit in a running
# container — change scripts/shell_setup.sh and rebuild the image.

# ── History (persist by mounting a volume at ~/.shell_history) ──
export HISTFILE="$HOME/.shell_history/.bash_history"
export HISTSIZE=50000
export HISTFILESIZE=50000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# ── Environment ──────────────────────────────────────────────
export PYTHONPATH="/workspace${PYTHONPATH:+:$PYTHONPATH}"
export TERM=xterm-256color
export CLICOLOR=1

# ── Django aliases ───────────────────────────────────────────
alias pm="python manage.py"
alias pmr="python manage.py runserver 0.0.0.0:8000"
alias pms="python manage.py shell"
alias pmm="python manage.py migrate"
alias pmmk="python manage.py makemigrations"
alias pmcs="python manage.py collectstatic --noinput"
alias pmt="python manage.py test"
alias pmsu="python manage.py createsuperuser"

# ── uv aliases ───────────────────────────────────────────────
alias uvs="uv sync"
alias uva="uv add"
alias uvr="uv remove"
alias uvl="uv pip list"
alias uvf="uv pip freeze"

# ── Git aliases ──────────────────────────────────────────────
alias gs="git status"
alias ga="git add"
alias gc="git commit -m"
alias gp="git push"
alias gl="git log --oneline --graph --decorate"
alias gco="git checkout"
alias gb="git branch"

# ── Utility aliases ──────────────────────────────────────────
alias ll="ls -alFh --color=auto"
alias la="ls -A --color=auto"
alias cls="clear"

# ── Prompt ───────────────────────────────────────────────────
eval "$(starship init bash)"
BASHRC

# ── Login shells ─────────────────────────────────────────────
# Debian's /etc/profile resets PATH for login shells — and VS Code probes the
# container environment with one. Put the project venv (and ~/.local/bin) back
# in front, matching the image's ENV PATH.
cat > /etc/profile.d/10-devcontainer-path.sh << 'PROFILE'
case ":${PATH}:" in
    *":/workspace/.venv/bin:"*) ;;
    *) PATH="/workspace/.venv/bin:${HOME}/.local/bin:${PATH}" ;;
esac
export PATH
PROFILE

for rc in /etc/skel/.bashrc /root/.bashrc; do
    printf '\n# django-devcontainer shell config\n[ -f /etc/bash.devcontainer ] && . /etc/bash.devcontainer\n' >> "$rc"
done

echo "✅ Shell setup complete"
