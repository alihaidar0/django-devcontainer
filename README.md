# django-devcontainer

> Blank-canvas base Docker image for VS Code Dev Containers.
> One image, shared across all your Django projects.

**Python 3.14.3 · uv · GitHub CLI · Node.js 24 LTS · Celery · Starship**

[![Docker Build](https://github.com/alihaidar0/django-devcontainer/actions/workflows/docker.yml/badge.svg)](https://github.com/alihaidar0/django-devcontainer/actions/workflows/docker.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/alihaidar199527/django-devcontainer)](https://hub.docker.com/r/alihaidar199527/django-devcontainer)
[![Image Size](https://img.shields.io/docker/image-size/alihaidar199527/django-devcontainer/latest)](https://hub.docker.com/r/alihaidar199527/django-devcontainer)

```bash
docker pull alihaidar199527/django-devcontainer:latest
```

---

## Overview

Every Django project needs the same developer tooling: Python, a package manager, a linter, a type checker, database clients, Redis tooling, Git, and a good terminal prompt. Configuring this from scratch on every machine wastes time and produces inconsistent environments.

This repository solves that problem with a single, shared base image. Push a change here and all your Django projects get the upgrade on the next `docker pull` — without touching any project code.

**This repo has one job:** build and publish the base development Docker image to Docker Hub.

It contains no Django files, no project-specific configuration, and no application code. Django itself, DRF, psycopg, redis-py, and any other project-level package are installed per project with `uv add` after the container starts.

---

## Architecture

This image is one half of a two-repo system.

| Repo | Responsibility |
|---|---|
| `django-devcontainer` ← **you are here** | Build and publish the base dev image |
| `django-template` | GitHub Template — the starting point for every new Django project |

When you open a Django project that uses this image, six containers start together via Docker Compose:

| Container | Port | Role |
|---|---|---|
| `app` | 8000 | Django development server — your code runs here |
| `celery` | — | Celery worker, auto-restarts on code change via `watchfiles` |
| `celery-beat` | — | Periodic task scheduler |
| `postgres` | 5432 | PostgreSQL 17 database |
| `redis` | 6379 | Cache and Celery broker |
| `mailpit` | 8025 / 1025 | Email catcher (SMTP on 1025, web UI on 8025) |

The `app`, `celery`, and `celery-beat` containers all pull **this same image**, which is why the Celery CLI and `watchfiles` are baked in.

---

## What's Inside

All system build libraries are included (`libpq`, `libssl`, `libjpeg`, `libxml2`, and others), so packages like `psycopg` and `Pillow` compile without additional setup.

| Category | Tool | Purpose |
|---|---|---|
| **Runtime** | Python 3.14.3 (`slim-bookworm`) | Language runtime — pinned to an exact version for reproducible builds |
| **Package manager** | uv | Ultra-fast Python package manager; replaces pip + venv |
| **Version control** | Git + GitHub CLI (`gh`) | Source control and GitHub operations from the terminal |
| **SSH** | openssh-client | Enables `git push` via SSH from inside the container |
| **JavaScript** | Node.js 24 LTS | Required by Husky and commitlint git hooks in projects |
| **Database** | PostgreSQL 17 client | `psql`, `pg_isready`, `pg_dump` |
| **Database** | pgcli | Interactive PostgreSQL client with autocomplete and syntax highlighting |
| **Cache / Queue** | redis-cli | Test Redis cache and Celery broker from the terminal |
| **Task queue** | Celery | CLI baked in — worker and beat containers start without waiting for `uv sync` |
| **Task queue** | Flower | Celery monitoring web UI, accessible at `:5555` |
| **Task queue** | watchfiles | Auto-reloads the Celery worker when source files change |
| **Code quality** | ruff | Linter and formatter — replaces flake8, isort, and black |
| **Code quality** | mypy | Static type checker |
| **Code quality** | pre-commit | Git hook manager |
| **Shell** | IPython | Rich interactive Python shell with autocomplete |
| **API testing** | HTTPie | Human-friendly HTTP client — `http GET localhost:8000/api/` |
| **Shell** | Starship | Terminal prompt showing git branch, Python version, and git status |

### What is NOT inside

These are intentionally absent. Install them per project with `uv add`:

```
Django                  →  uv add django
djangorestframework     →  uv add djangorestframework
psycopg                 →  uv add "psycopg[binary,pool]"
redis-py                →  uv add redis
Celery app config       →  defined in your project's config/celery.py
```

---

## Repository Structure

```
django-devcontainer/
├── .github/
│   ├── dependabot.yml                    # Weekly auto-updates for Actions + Docker base image
│   ├── labels.yml                        # Label definitions — name, color, description
│   └── workflows/
│       ├── docker.yml                    # Builds + pushes image on push/PR to main
│       ├── dockerhub-description.yml     # Syncs README.md to Docker Hub on push to main
│       └── labels.yml                    # Syncs labels.yml to GitHub labels
├── docker/
│   └── Dockerfile.dev                    # The image recipe
├── scripts/
│   └── shell_setup.sh                    # Shell aliases and Starship prompt
├── .dockerignore                         # Excludes unnecessary files from the build context
├── .gitignore                            # Ensures .env files are never committed
└── README.md                             # This file — also synced to Docker Hub
```

---

## GitHub Automation

Five files under `.github/` handle everything automatically.

### Workflow trigger summary

| File | Trigger | What happens |
|---|---|---|
| `workflows/docker.yml` | Push to `main` (`docker/`, `scripts/` changed) | Builds + pushes `:latest` + `:sha-xxx` to Docker Hub |
| `workflows/docker.yml` | PR targeting `main` (same path filter) | Builds only — validates Dockerfile, never pushes |
| `workflows/docker.yml` | Manual dispatch | Builds + pushes, with force-rebuild and push toggle |
| `workflows/dockerhub-description.yml` | Push to `main` (`README.md` changed) | Updates Docker Hub description |
| `workflows/dockerhub-description.yml` | PR targeting `main` (`README.md` changed) | Runs but skips update until merged |
| `workflows/dockerhub-description.yml` | Manual dispatch | Forces immediate Docker Hub sync |
| `workflows/labels.yml` | Push to `main` (`.github/labels.yml` changed) | Syncs all labels to GitHub |
| `workflows/labels.yml` | Manual dispatch | Bootstrap all labels in one go |
| `dependabot.yml` | Every Monday 09:00 UTC | Scans Actions + Docker, opens PRs against `develop` |
| `dependabot.yml` | Manual via Insights → Dependency graph | Immediate on-demand scan |
| `labels.yml` | — | Data file only — no trigger of its own |

### `workflows/docker.yml`

Builds the multi-platform Docker image (`linux/amd64` + `linux/arm64`) and pushes it to Docker Hub. Path-filtered so a README change never triggers an unnecessary image rebuild. PR builds compile the image to validate the Dockerfile without pushing — only merged pushes publish to Docker Hub.

### `workflows/dockerhub-description.yml`

Syncs `README.md` to the Docker Hub repository description page. Runs on every `README.md` change merged to `main`. PRs trigger the workflow so GitHub can show a check, but the actual Docker Hub update is skipped until the merge is complete.

### `workflows/labels.yml`

Keeps GitHub repository labels in sync with `.github/labels.yml`. Labels are version-controlled — add or rename a label in the file, push, and GitHub reflects the change automatically. Supports manual dispatch for first-time bootstrapping.

### `dependabot.yml`

Automatically monitors two ecosystems and opens PRs against `develop` when updates are found — all GitHub Actions versions used in workflows, and the Docker base image in `Dockerfile.dev`. Runs every Monday at 09:00 UTC. Can also be triggered manually from **Insights → Dependency graph → Dependabot**.

### `labels.yml`

The single source of truth for all repository labels. Defines each label's name, hex color, and description. Read by `workflows/labels.yml` — has no trigger of its own.

---

## How the Build Works

```
Push to main (Dockerfile or scripts changed)
  → GitHub Actions detects the change
  → Builds linux/amd64 + linux/arm64 in parallel
  → Pushes :latest and :sha-<commit> to Docker Hub
  → Job summary written to Actions log

PR targeting main (Dockerfile or scripts changed)
  → GitHub Actions detects the change
  → Builds linux/amd64 + linux/arm64 to validate
  → Does NOT push — PR check goes green or red
  → Merge when green
```

The first build takes 20–30 minutes (no cache). All subsequent builds complete in 3–5 minutes thanks to GitHub Actions layer caching.

---

## Platforms

| Platform | Architecture |
|---|---|
| Windows · Linux · GCP | `linux/amd64` |
| Apple Silicon Mac | `linux/arm64` |

Docker pulls the correct platform automatically.

---

## Tags

| Tag | Published when |
|---|---|
| `latest` | Every push to `main` |
| `sha-xxxxxxx` | Every build — pin to this for rollback |

---

## Shell Aliases

All aliases are defined in `scripts/shell_setup.sh` and baked into the image.

### Django

| Alias | Expands to |
|---|---|
| `pm` | `python manage.py` |
| `pmr` | `python manage.py runserver 0.0.0.0:8000` |
| `pmm` | `python manage.py migrate` |
| `pmmk` | `python manage.py makemigrations` |
| `pms` | `python manage.py shell_plus` |
| `pmsu` | `python manage.py createsuperuser` |
| `pmcs` | `python manage.py collectstatic --noinput` |
| `pmt` | `python manage.py test` |

### Celery

| Alias | Expands to |
|---|---|
| `cw` | `celery -A config worker -l INFO --pool=solo` |
| `cb` | `celery -A config beat -l INFO --scheduler django_celery_beat.schedulers:DatabaseScheduler` |
| `cf` | `celery -A config flower --port=5555` |
| `cpurge` | `celery -A config purge` |

### uv

| Alias | Expands to | Notes |
|---|---|---|
| `uvs` | `uv sync` | Sync venv from `pyproject.toml` — use after cloning or pulling |
| `uva` | `uv add` | Add a package and update `pyproject.toml` + lockfile |
| `uvr` | `uv remove` | Remove a package and update `pyproject.toml` + lockfile |
| `uvl` | `uv pip list` | List installed packages |
| `uvf` | `uv pip freeze` | Freeze installed packages |

### Git

| Alias | Expands to |
|---|---|
| `gs` | `git status` |
| `ga` | `git add` |
| `gc` | `git commit -m` |
| `gp` | `git push` |
| `gl` | `git log --oneline --graph --decorate` |
| `gco` | `git checkout` |
| `gb` | `git branch` |

### Utilities

| Alias | Expands to |
|---|---|
| `ll` | `ls -alFh --color=auto` |
| `la` | `ls -A --color=auto` |
| `cls` | `clear` |
| `dps` | `docker ps` |
| `dlogs` | `docker logs` |

---

## Updating the Image

### Upgrading Python

Edit `ARG PYTHON_VERSION` in `docker/Dockerfile.dev` — the single source of truth. Verify the tag exists at [hub.docker.com/_/python/tags](https://hub.docker.com/_/python/tags) first.

```dockerfile
ARG PYTHON_VERSION=3.15.0
```

Commit, push to a branch, open a PR against `main`. The PR build validates the new Python version compiles correctly. Merge when green — image publishes automatically.

### Adding a system package

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    your-new-tool \    # reason for including
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

### Adding a Python tool

```dockerfile
RUN uv pip install --system \
    ruff mypy pre-commit ipython \
    pgcli httpie celery flower watchfiles \
    your-new-package
```

---

## Troubleshooting

### Build fails — authentication error

**Symptom:** `denied: requested access to the resource is denied`

1. Go to **Settings → Secrets and variables → Actions**
2. Confirm both `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` are present
3. If expired: Docker Hub → **Account Settings → Personal access tokens** → delete → create new → update secret
4. Re-run from the **Actions** tab

### Build fails — Python image not found

**Symptom:** `manifest unknown` for `python:3.x.x-slim-bookworm`

Check [hub.docker.com/_/python/tags](https://hub.docker.com/_/python/tags) and update `ARG PYTHON_VERSION` to an existing tag.

### `git push` fails — permission denied (publickey)

```bash
ssh-add -l                                         # check loaded keys
ssh-add "%USERPROFILE%\.ssh\id_ed25519"            # Windows — load key
ssh-add ~/.ssh/id_ed25519                          # macOS / Linux
ssh -T git@github.com                              # verify auth
git remote set-url origin git@github.com:YOUR_USERNAME/django-devcontainer.git  # fix HTTPS remote
```

**On Windows after restart:**
```cmd
sc config ssh-agent start= auto
net start ssh-agent
```

### Docker Desktop — cannot connect

1. Wait for the taskbar whale icon to stop animating
2. Right-click whale → **Restart Docker Desktop**
3. Task Manager → end all `Docker Desktop` processes → reopen

---

*Python 3.14.3 · Node.js 24 LTS · Debian 12 Bookworm · 2026*
