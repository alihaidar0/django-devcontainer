#!/usr/bin/env bash
# =============================================================
#  shell_setup.sh
#  Runs once at image build time (Dockerfile.dev RUN step).
#  Installs Starship prompt and writes all shell config to
#  /root/.bashrc — aliases, history settings, env exports.
# =============================================================

set -euo pipefail

# ── Starship prompt ──────────────────────────────────────────
curl -sS https://starship.rs/install.sh | sh -s -- --yes

mkdir -p /root/.config

cat > /root/.config/starship.toml << 'STARSHIP'
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

# ── .bashrc ──────────────────────────────────────────────────
cat >> /root/.bashrc << 'BASHRC'
# Starship
eval "$(starship init bash)"

# ── History ──────────────────────────────────────────────────
export HISTFILE=/root/.shell_history/.bash_history
export HISTSIZE=50000
export HISTFILESIZE=50000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend

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

# ── Docker aliases ───────────────────────────────────────────
alias dps="docker ps"
alias dlogs="docker logs"

# ── Utility aliases ──────────────────────────────────────────
alias ll="ls -alFh --color=auto"
alias la="ls -A --color=auto"
alias cls="clear"

# ── Environment ──────────────────────────────────────────────
export PYTHONPATH="/workspace:$PYTHONPATH"
export TERM=xterm-256color
export CLICOLOR=1
BASHRC

# ── Shell history directory ──────────────────────────────────
mkdir -p /root/.shell_history

echo "✅ Shell setup complete"