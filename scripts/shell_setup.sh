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
curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin

cat > /etc/starship.toml << 'STARSHIP'
format = """
[╭─](bold green)$directory$git_branch$git_status$python$docker_context
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

[docker_context]
symbol = " "
style = "bold blue"
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

# ── Celery aliases ───────────────────────────────────────────
alias cw="celery -A config worker -l INFO --pool=solo"
alias cb="celery -A config beat -l INFO --scheduler django_celery_beat.schedulers:DatabaseScheduler"
alias cf="celery -A config flower --port=5555"
alias cpurge="celery -A config purge"

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

# ── Docker aliases (work when the host socket is mounted) ────
alias dps="docker ps"
alias dlogs="docker logs"

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
