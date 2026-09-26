# django-devcontainer

> The shared development image for every Django project built from
> [`django-template`](https://github.com/alihaidar0/django-template).
> **Pulled, never built, on your laptop.**

Python 3.14 · uv · ruff · mypy · pre-commit · Celery · PostgreSQL 18 client · GitHub CLI · Starship — **non-root, multi-arch**

[![Docker](https://github.com/alihaidar0/django-devcontainer/actions/workflows/docker.yml/badge.svg)](https://github.com/alihaidar0/django-devcontainer/actions/workflows/docker.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/alihaidar199527/django-devcontainer)](https://hub.docker.com/r/alihaidar199527/django-devcontainer)
[![Image Size](https://img.shields.io/docker/image-size/alihaidar199527/django-devcontainer/latest)](https://hub.docker.com/r/alihaidar199527/django-devcontainer)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/alihaidar0/django-devcontainer/blob/main/LICENSE)

```bash
docker pull alihaidar199527/django-devcontainer:latest
```

---

## Why this exists

Building a full Django dev environment — compilers, database clients, a dozen
CLI tools — takes 20–30 minutes and drifts from machine to machine. This repo
does that work **once, in CI**, and publishes the result to Docker Hub.

When you create a project from `django-template` and click **Reopen in
Container**, VS Code only **pulls** this image. Nothing is built locally; the
container is ready in the time it takes to download.

Improve the image here and every project gets the upgrade on its next pull,
without touching project code.

**This repo has one job:** build, test, and publish that image. It contains no
Django files, no `pyproject.toml`, and no application code — Django, DRF,
psycopg, redis-py and every other project package are installed per project
with `uv add`.

---

## How it fits together

```text
django-devcontainer ──(CI: test · build · sign · push)──▶ Docker Hub
                                                            │ docker pull
django-template ──(Use this template)──▶ your project ──────┘
                                         (app · celery · celery-beat all run this image;
                                          postgres · redis · mailpit are stock images)
```

| Repo | Responsibility |
| --- | --- |
| `django-devcontainer` ← **you are here** | The environment: Python, uv, tools, shell — built and published by CI |
| `django-template` | The project scaffold: compose stack, `devcontainer.json`, hooks, app CI, production Dockerfile |

---

## What's inside

Base: official `python:3.14-slim-trixie` (Debian 13), pinned by digest. All
common native build headers are present (`libpq`, `libssl`, `libffi`,
`libjpeg`, `libwebp`, `freetype`, `libxml2`, …), so `psycopg`, `Pillow`, and
`lxml` compile without extra setup.

| Category | Tool | Notes |
| --- | --- | --- |
| **Runtime** | Python 3.14 (latest patch) | Every new Python release arrives as its own Dependabot PR |
| **Packages** | uv + uvx | Pinned version, copied from the official uv image |
| **Code quality** | ruff · mypy · pre-commit | A project's own versions win once its `.venv` exists |
| **Shells** | IPython · Starship prompt · bash aliases | Git branch/status, Python version in the prompt |
| **Database** | PostgreSQL **18** client (`psql`, `pg_dump`, `pg_isready`) · pgcli | From the official PGDG repo — matches the template's Postgres 18 |
| **Cache / queue** | redis-cli · Celery · Flower · watchfiles | Worker/beat containers start before `uv sync`; see below |
| **API testing** | HTTPie | `http GET localhost:8000/api/` |
| **Git** | git · git-lfs · GitHub CLI (`gh`) · openssh-client · gnupg | SSH push and signed commits from inside the container |
| **Utilities** | jq · vim · nano · less · htop · tree · ping · dig · nc · sudo | |

Every Python CLI is installed with `uv tool install` into its own isolated
environment, so the system Python stays clean and tools never conflict with
each other or with your project. Their versions are pinned in
[`docker/requirements-tools.txt`](https://github.com/alihaidar0/django-devcontainer/blob/main/docker/requirements-tools.txt)
(also inside the image at `/opt/uv-tools/requirements-tools.txt`) and kept
current by Dependabot.

**Not inside, by design:** Django and any other project package (`uv add` them),
the Celery app config (your project's `config/celery.py`), and Node.js.

---

## Runtime contract

What a project using this image can rely on:

| | |
| --- | --- |
| **User** | `dev` — UID/GID `1000`, passwordless `sudo`. Declared in the image's `devcontainer.metadata` label, so `devcontainer.json` needs no `remoteUser`. |
| **Workspace** | `/workspace` (owned by `dev`) — mount your project here |
| **Home** | `/home/dev` — `.ssh` (0700), `.cache/uv`, `.shell_history` pre-created and owned by `dev`, so named volumes mounted there inherit the right ownership |
| **PATH** | `/workspace/.venv/bin` comes **first**. After `uv sync`, `python`, `celery`, `mypy`, `pytest` … resolve to the project's versions in every container — no activation step. Before that, the image's global tools answer. |
| **Env** | `UV_LINK_MODE=copy` (cache and bind-mounted `.venv` live on different filesystems), `PYTHONPATH=/workspace` in interactive shells, `PYTHONUNBUFFERED=1`, UTF-8 locale |
| **Ports** | `8000` Django dev server · `5555` Flower |
| **Command** | `sleep infinity` — the container stays up for VS Code to attach |

### Using it from docker compose

```yaml
services:
  app:
    image: alihaidar199527/django-devcontainer:latest
    volumes:
      - .:/workspace:cached
      - uv-cache:/home/dev/.cache/uv
      - shell-history:/home/dev/.shell_history
    ports: ["8000:8000", "5555:5555"]

volumes:
  uv-cache:
  shell-history:
```

**Git & SSH:** don't mount `~/.ssh` or `~/.gitconfig`. VS Code Dev Containers
forwards your host **ssh-agent** and copies your **.gitconfig** into the
container automatically — keys never touch the container and there are no
Windows NTFS permission problems. Just make sure your key is loaded on the
host (`ssh-add -l`); see [Troubleshooting](#troubleshooting).

---

## Tags

| Tag | Published | Use |
| --- | --- | --- |
| `latest` | every build from `main` (push + weekly) | Default for projects |
| `YYYYMMDD` | every build | Pin to a known-good week |
| `sha-xxxxxxx` | every build | Trace an image back to its commit |

The image is rebuilt **every Monday** even without code changes, so `latest`
always carries current Debian security fixes and the latest apt packages
(GitHub CLI, PostgreSQL client, …) and Starship.
Platforms: `linux/amd64` (Windows, Linux, cloud) and `linux/arm64` (Apple
Silicon) — Docker pulls the right one automatically.

### Supply chain

Every published image carries an **SBOM** and a **SLSA provenance attestation
signed with Sigstore** (keyless, via GitHub OIDC). The `Docker` workflow's run
summary prints the exact `cosign verify` command for each build. Inspect them:

```bash
docker buildx imagetools inspect alihaidar199527/django-devcontainer:latest --format '{{ json .Provenance }}'
docker buildx imagetools inspect alihaidar199527/django-devcontainer:latest --format '{{ json .SBOM }}'
```

Each published digest is also scanned by Trivy; results are in the
repository's **Security → Code scanning** tab.

---

## Shell aliases

Baked in via `scripts/shell_setup.sh` for every user of the image.

| Group | Aliases |
| --- | --- |
| **Django** | `pm` manage.py · `pmr` runserver 0.0.0.0:8000 · `pmm` migrate · `pmmk` makemigrations · `pms` shell · `pmsu` createsuperuser · `pmcs` collectstatic · `pmt` test |
| **Celery** | `cw` worker (solo pool) · `cb` beat (DatabaseScheduler) · `cf` flower :5555 · `cpurge` purge — all `-A config` |
| **uv** | `uvs` sync · `uva` add · `uvr` remove · `uvl` pip list · `uvf` pip freeze |
| **Git** | `gs` status · `ga` add · `gc` commit -m · `gp` push · `gl` log graph · `gco` checkout · `gb` branch |
| **Utilities** | `ll` · `la` · `cls` · `dps` · `dlogs` |

Shell history (50 000 lines) persists when a volume is mounted at `/home/dev/.shell_history`.

---

## How it is built

```text
PR into main ─────▶ Lint (hadolint · ShellCheck · actionlint · cspell · markdownlint)
                └─▶ Image tests: if the image inputs changed, native build on
                    amd64 + arm64 runners → tests/smoke.sh (both checks required)

Merge to main ────────────▶ Publish ─▶ Scan      (already tested on the PR)
Weekly (Mon 05:00) ▶ Test ─▶ Publish ─▶ Scan
Manual dispatch ──▶ Test ─▶ Publish ─▶ Scan
                            │           └─ Trivy → Security tab
                            └─ docker/github-builder: native per-arch builds,
                               multi-arch manifest, SBOM, signed provenance,
                               push :latest · :YYYYMMDD · :sha-xxxxxxx
```

- **No emulation:** arm64 is built on GitHub's native arm64 runners, not QEMU.
- **Tested before pushed, and only once:** `tests/smoke.sh` checks the user,
  every tool, the shell config, and `.venv` precedence on both architectures —
  on the PR (a required check), or right before a scheduled/manual publish.
  Nothing runs twice for the same change.
- **Pinned supply chain:** every action and the base/uv images are pinned by
  commit SHA, digest, or exact version; Dependabot checks **everything** —
  actions, the Python and uv images, and every CLI tool — weekly, after a
  7-day cooldown.

Details: [`.github/CONTRIBUTING.md`](https://github.com/alihaidar0/django-devcontainer/blob/main/.github/CONTRIBUTING.md).

---

## Repository structure

```text
django-devcontainer/
├── .github/
│   ├── ISSUE_TEMPLATE/              # Bug + feature forms (blank issues disabled)
│   ├── workflows/
│   │   ├── docker.yml               # Test → publish → scan the image
│   │   ├── lint.yml                 # hadolint · ShellCheck · actionlint · cspell · markdownlint
│   │   ├── dockerhub-description.yml# README.md → Docker Hub
│   │   └── labels.yml               # labels.yml → GitHub labels
│   ├── actionlint.yaml              # actionlint config
│   ├── CODEOWNERS · CONTRIBUTING.md · SECURITY.md · pull_request_template.md
│   ├── dependabot.yml               # Weekly: Actions, Docker (python, uv), CLI tools
│   └── labels.yml                   # Labels as code
├── .cspell/
│   └── project-words.txt            # Spell-check dictionary: tool, package, alias names
├── .vscode/
│   └── extensions.json              # Recommended editor extensions (same checks as CI)
├── docker/
│   ├── Dockerfile.dev               # The image recipe
│   └── requirements-tools.txt       # Pinned versions of the global CLIs (Dependabot: pip)
├── scripts/
│   └── shell_setup.sh               # Starship prompt, aliases, history (build time)
├── tests/
│   └── smoke.sh                     # Runtime contract test (CI, amd64 + arm64)
├── .dockerignore                    # Allowlist — only what the build COPYs
├── .editorconfig · .gitattributes   # LF everywhere, consistent formatting
├── .hadolint.yaml                   # Dockerfile lint config
├── .markdownlint-cli2.jsonc         # Markdown lint config (editor + CI)
├── cspell.json                      # Spell-check config (en + en-GB, code dictionaries)
├── LICENSE                          # MIT
└── README.md                        # This file — also the Docker Hub page
```

---

## Updating the image

Open a PR into `main`; the `Test` jobs build and smoke-test both architectures.
Merge when green — the image publishes automatically.

**Updates arrive as Dependabot PRs** every Monday: GitHub Actions, the Python
and uv images, and the pinned CLI tools. Review, let CI go green, merge.

**Python minor upgrade** (e.g. 3.14 → 3.15) also arrives as its own Dependabot
PR, but its `Test` jobs fail on purpose until you update the Python version
check in `tests/smoke.sh` — a deliberate step, so confirm your projects'
dependencies support the new version first.

**A system package:** add it to the single `apt-get install` list in
`Dockerfile.dev`, grouped under a comment explaining why.

**A global Python CLI:** add `name==version` to `docker/requirements-tools.txt`
and a matching `uv tool install -c "$c" <name>` line in `Dockerfile.dev`. Only
tools useful to *every* project belong here — project dependencies go in the
project.

**Before pushing**, build and test locally:

```bash
docker build -f docker/Dockerfile.dev -t django-devcontainer:test .
docker run --rm -v "$PWD/tests:/tests:ro" django-devcontainer:test bash /tests/smoke.sh
```

---

## Migrating from the root image

Images published before the non-root switch ran as `root` with tools in the
system Python. Projects created from an older `django-template` need these
changes (in the project / template, not here):

| File | Change |
| --- | --- |
| `docker-compose.yml` | Mount volumes under `/home/dev` instead of `/root` (`uv-cache` → `/home/dev/.cache/uv`, `shell-history` → `/home/dev/.shell_history`). Remove the `~/.ssh` and `~/.gitconfig` mounts and `GIT_SSH_COMMAND` — use ssh-agent forwarding. |
| `.devcontainer/devcontainer.json` | Remove `"remoteUser": "root"` (the image label sets `dev`). |
| `scripts/entrypoint.dev.sh` | Remove the `/root/.ssh` `chmod` block. |
| `scripts/welcome.sh` | Remove the block that appends venv activation to `/root/.bashrc` — `.venv/bin` is already first on `PATH`. |

To stay on the old behaviour temporarily, pin the project to the last root
image, `alihaidar199527/django-devcontainer:sha-7cd9005`, instead of `latest`.

---

## Troubleshooting

### `git push` fails — Permission denied (publickey)

The container uses your **host's** ssh-agent. On the host:

```bash
ssh-add -l                                   # is a key loaded?
ssh-add ~/.ssh/id_ed25519                    # macOS / Linux
ssh -T git@github.com                        # verify
```

On Windows (PowerShell as Administrator), start the agent once and load the key:

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

Then **Rebuild / Reopen in Container** so VS Code picks up the agent.

### Files in `/workspace` owned by the wrong user (Linux hosts)

Dev Containers re-maps `dev` to your host UID (`updateRemoteUserUID`, set by
the image label). Outside VS Code, run compose with a host user whose UID is
1000, or add `user: "${UID}:${GID}"` to the service.

### Build fails in CI — authentication error

**Settings → Secrets and variables → Actions**: confirm `DOCKERHUB_USERNAME`
and `DOCKERHUB_TOKEN` (Docker Hub → Account settings → Personal access tokens,
Read & Write), then re-run the workflow.

### Weekly build stopped running

GitHub pauses scheduled workflows after 60 days without repository activity.
Re-enable it under **Actions → Docker → Enable workflow**.

---

## License

[MIT](https://github.com/alihaidar0/django-devcontainer/blob/main/LICENSE) © Ali Haidar
