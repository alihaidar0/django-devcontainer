# django-devcontainer

> The shared development image for every Django project built from
> [`django-template`](https://github.com/alihaidar0/django-template).
> **Pulled, never built, on your laptop.**

Python 3.14 · uv · pre-commit · PostgreSQL 18 client · gettext · GitHub CLI · Starship — **non-root, multi-arch**

[![Docker](https://github.com/alihaidar0/django-devcontainer/actions/workflows/docker.yml/badge.svg?branch=main)](https://github.com/alihaidar0/django-devcontainer/actions/workflows/docker.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/alihaidar199527/django-devcontainer)](https://hub.docker.com/r/alihaidar199527/django-devcontainer)
[![Image Size](https://img.shields.io/docker/image-size/alihaidar199527/django-devcontainer/latest)](https://hub.docker.com/r/alihaidar199527/django-devcontainer)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/alihaidar0/django-devcontainer/blob/main/LICENSE)

```bash
docker pull alihaidar199527/django-devcontainer:latest
```

---

## Why this exists

Building a full Django dev environment — compilers, database clients, system
libraries and tools — takes 20–30 minutes and drifts from machine to machine. This repo
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

Base: official `python:3.14-slim-trixie` (Debian 13), pinned by digest. The
image carries the **environment** and nothing a project pins for itself.

| Category | Tool | Notes |
| --- | --- | --- |
| **Runtime** | Python 3.14 (latest patch) | The newest minor [Django officially supports](https://docs.djangoproject.com/en/stable/faq/install/); patch updates arrive as their own Dependabot PR |
| **Packages** | uv + uvx | Pinned version, copied from the official uv image. uv is the installer; there is no `pip` |
| **Git hooks** | pre-commit | The template's post-create step runs `pre-commit install`; hooks pin their own tool versions |
| **Worker reload** | watchfiles | The template's celery service restarts the worker with it on code changes |
| **Database** | PostgreSQL **18** client (`psql`, `pg_dump`, `pg_isready`) + libpq headers | From the official PGDG repo — matches the template's Postgres 18. The headers build `psycopg[c]` |
| **Cache / queue** | redis-cli | Inspect the cache or the Celery broker |
| **i18n** | GNU gettext | Django's `makemessages` and `compilemessages` |
| **Build** | build-essential | For the rare package without a prebuilt wheel |
| **Git** | git · GitHub CLI (`gh`) · openssh-client · gnupg | SSH push and signed commits from inside the container |
| **Shell** | Starship prompt · bash aliases | Git branch/status, Python version in the prompt |
| **Utilities** | curl · jq · vim · nano · less · unzip · htop · tree · procps · ping · dig · nc · sudo | |

`pre-commit` and `watchfiles` are installed with `uv tool install` into their own
isolated environments, so the system Python stays clean. Their versions are
pinned in
[`docker/requirements-tools.txt`](https://github.com/alihaidar0/django-devcontainer/blob/main/docker/requirements-tools.txt)
(also inside the image at `/opt/uv-tools/requirements-tools.txt`) and kept
current by Dependabot.

**Not inside, by design — it belongs to the project:** Django and every other
package, and the tooling a project pins in `uv.lock`: ruff, mypy, pytest,
Celery, Flower, IPython, django-stubs, debug toolbar, … A single global copy
would drift from the version your lock file and pre-commit hooks use. Pillow,
lxml, cffi and `psycopg[binary]` install from prebuilt wheels on amd64 and
arm64, so their `-dev` headers (JPEG, XML, FFI, …) are absent; a package that
does need one: `sudo apt-get install -y <package>-dev`. Ad-hoc tools run without
installing anything: `uvx pgcli`, `uvx httpie`, `uvx ipython`. No Node.js.

---

## Runtime contract

What a project using this image can rely on:

| | |
| --- | --- |
| **User** | `dev` — UID/GID `1000`, passwordless `sudo`. Declared in the image's `devcontainer.metadata` label, so `devcontainer.json` needs no `remoteUser`. |
| **Workspace** | `/workspace` (owned by `dev`) — mount your project here |
| **Home** | `/home/dev` — `.ssh` (0700), `.cache/uv`, `.shell_history` pre-created and owned by `dev`, so named volumes mounted there inherit the right ownership |
| **PATH** | `/workspace/.venv/bin` comes **first** — in every container and every shell, login shells included (`/etc/profile` would otherwise reset it; VS Code probes the environment with one). After `uv sync`, `python`, `celery`, `ruff`, `mypy`, `pytest` … resolve to the project's versions — no activation step. Before that, only the image's two global tools (`pre-commit`, `watchfiles`) answer. |
| **Env** | `UV_LINK_MODE=copy` (cache and bind-mounted `.venv` live on different filesystems), `PYTHONPATH=/workspace` in interactive shells, `PYTHONUNBUFFERED=1`, UTF-8 locale |
| **Ports** | `8000` Django dev server (other ports, such as Flower's `5555`, are published by your compose file) |
| **Command** | `sleep infinity` — the container stays up for VS Code to attach |

### Parsed by django-template

`django-template` checks itself against this repository every week by reading
four things from `main`. Their format is part of the contract: changing one
needs a matching change in the template's `.github/scripts/check-image-contract.sh`
in the same release, and `Lint` here fails if the format drifts.

| What | Where | Must match in the template |
| --- | --- | --- |
| `ARG PG_MAJOR=NN` | `docker/Dockerfile.dev` | The PostgreSQL major in its compose file and CI |
| The first `FROM python:X.Y.Z…` line | `docker/Dockerfile.dev` | The Python minor in its production Dockerfile and CI |
| `FROM ghcr.io/astral-sh/uv:X.Y.Z@…` | `docker/Dockerfile.dev` | The uv version it documents |
| One `alias name=` per line | `scripts/shell_setup.sh` | The aliases it uses: `pm` `pmr` `pms` `pmm` `pmmk` `pmcs` `pmt` `pmsu` |

### Using it from docker compose

```yaml
services:
  app:
    image: alihaidar199527/django-devcontainer:latest   # or :python-3.14 / :python-3.14.8.1 — see Tags
    volumes:
      - .:/workspace:cached
      - uv-cache:/home/dev/.cache/uv
      - shell-history:/home/dev/.shell_history
    ports: ["8000:8000"]

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

The image is named after the Python it contains, like the official `python`
images.

| Tag | Moves? | Published | Use |
| --- | --- | --- | --- |
| `latest` | yes | every publish from `main` | Default for projects: always the newest image |
| `python-X.Y` (e.g. `python-3.14`) | yes | every publish of that Python line | Stay on a Python line and still get every tool and OS update |
| `python-X.Y.Z.R` (e.g. `python-3.14.8.1`) | **never** | every publish | Pin a project to one exact image |

`X.Y.Z` is the Python release inside the image and `R` is the image revision:

- **Python changes** (e.g. 3.14.8 → 3.14.9, or 3.14 → 3.15): a new image
  `python-3.14.9.1` is built, and `python-3.14` (or `python-3.15`) points to it.
- **Anything else changes** (a tool, a system package, Debian, Starship, the
  weekly rebuild): the same Python gets the next revision (`python-3.14.8.2`).
  `latest` and `python-3.14` are replaced by it, and the older revision stays
  available for projects that pinned it.

Every image has a git tag of the same name. Each push-triggered publish, and
the first image of every new Python version, also gets a
[GitHub Release](https://github.com/alihaidar0/django-devcontainer/releases)
with the same name, the `docker pull` command, the digest, and the commits
since the previous release. `python-X.Y.Z.R` tags and digests are never
overwritten or deleted, and a revision number is never reused (numbers can
skip). Keep Docker Hub tag retention off for this repository, otherwise old tags
can expire outside this pipeline.

**Choosing a tag:** `latest` for day-to-day work; `python-3.14` when a project's
`requires-python` must stay on one line; `python-X.Y.Z.R` (or the digest) when a
project must keep building on a known image — bump it deliberately.

**Every Monday** a check compares the published `latest` with what is available
now: any Debian, GitHub CLI or PostgreSQL package upgrade, or a newer Starship.
Only then is the image rebuilt, so `latest` always carries current security fixes
and a quiet week publishes nothing. Each rebuild is the next revision of the
current Python.
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
| **uv** | `uvs` sync · `uva` add · `uvr` remove · `uvl` pip list · `uvf` pip freeze |
| **Git** | `gs` status · `ga` add · `gc` commit -m · `gp` push · `gl` log graph · `gco` checkout · `gb` branch |
| **Utilities** | `ll` · `la` · `cls` |

Shell history (50 000 lines) persists when a volume is mounted at `/home/dev/.shell_history`.

---

## How it is built

```text
Push to develop ──▶ Lint (hadolint · ShellCheck · actionlint · format · README sync ·
Dependabot PR ────┤       cspell · markdownlint)
                  └─▶ Image tests: if the image inputs changed, native build on
                      amd64 + arm64 runners → tests/smoke.sh → vulnerability
                      gate (CRITICAL with a fix fails)

PR develop → main ─▶ PR source + the Lint / Image tests results of develop's
                     head commit (required)
Merge to main ────▶ Test (again) ─▶ Reserve tag ─▶ Publish ─▶ Scan + Release
Weekly (Mon 05:00) ▶ Rebuild needed? ─(apt or Starship changed)─▶ Test ─▶ Reserve tag
                     ─▶ Publish ─▶ Scan      (nothing changed: all skipped)
Weekly (Mon 06:00) ▶ Dependency drift: one issue for what Dependabot can't see
Manual dispatch ──▶ Test ─▶ Reserve tag ─▶ Publish ─▶ Scan
                            │              │          └─ Trivy → Security tab
                            │              └─ docker/github-builder: native
                            │                 per-arch builds, multi-arch manifest,
                            │                 SBOM, signed provenance, push
                            │                 python-X.Y.Z.R · python-X.Y · latest
                            └─ next free revision R of the Python in the Dockerfile;
                               creates the git tag first, so image, tag and
                               GitHub Release always share one name
```

- **No emulation:** arm64 is built on GitHub's native arm64 runners, not QEMU.
- **Tested before pushed:** `tests/smoke.sh` checks the user, every tool, the
  shell config, and `.venv` precedence on both architectures — on every PR and
  `develop` commit (required to release), and again right before every publish,
  because each build upgrades the Debian packages and the image must be tested
  with the packages it ships.
- **Branch model:** nobody pushes to `develop` or `main`. Work goes on a topic
  branch and reaches `develop` through a PR merged with a merge commit (the PR
  title is the release note); `main` accepts PRs from `develop` only, and every merge into
  `main` is a release.
- **Pinned supply chain:** every action and the base/uv images are pinned by
  commit SHA, digest, or exact version; Dependabot checks **everything** —
  actions, the Python and uv images, and the global CLI pins — weekly, after a
  7-day cooldown.

Details: [`.github/CONTRIBUTING.md`](https://github.com/alihaidar0/django-devcontainer/blob/main/.github/CONTRIBUTING.md).

---

## Repository structure

```text
django-devcontainer/
├── .github/
│   ├── ISSUE_TEMPLATE/              # Bug + feature forms (blank issues disabled)
│   ├── workflows/
│   │   ├── docker.yml               # Rebuild check → test → reserve tag → publish → scan → release
│   │   ├── dependency-drift.yml     # Weekly issue: PostgreSQL major, Debian, Python minor
│   │   ├── release.yml              # Reusable: GitHub Release named after the image tag
│   │   ├── branch-policy.yml        # PR source: only develop may open PRs into main
│   │   ├── lint.yml                 # hadolint · ShellCheck · actionlint · format · README sync · cspell · markdownlint
│   │   ├── dockerhub-description.yml# README.md → Docker Hub
│   │   ├── labels.yml               # labels.yml → GitHub labels
│   │   └── pr-labels.yml            # Labels a PR from its Conventional Commit title
│   ├── rulesets/                    # Rulesets as importable JSON (protect-main, protect-develop, protect-tags)
│   ├── scripts/                     # Helper scripts and their tests: tag reservation, release notes,
│   │                                #   weekly rebuild check, drift check, README sync (see CONTRIBUTING)
│   ├── actionlint.yaml              # actionlint config
│   ├── CODEOWNERS · CONTRIBUTING.md · SECURITY.md · pull_request_template.md
│   ├── CODE_OF_CONDUCT.md           # Contributor Covenant 2.1
│   ├── dependabot.yml               # Weekly: Actions, Docker (python, uv), CLI pins
│   ├── labels.yml                   # Labels as code
│   ├── trivy-ignore.rego            # Trivy: packages that can't affect a container (kernel headers)
│   └── vex.openvex.json             # Trivy: findings that don't apply (one version each)
├── .cspell/
│   └── project-words.txt            # Spell-check dictionary: tool, package, alias names
├── .vscode/
│   └── extensions.json              # Recommended editor extensions (same checks as CI)
├── docker/
│   ├── Dockerfile.dev               # The image recipe
│   └── requirements-tools.txt       # Pinned versions of the global CLIs (Dependabot: pip)
├── docs/
│   ├── design-decisions.md          # Why it works this way: decisions, reasons, alternatives
│   └── github-setup.md              # Setup and recovery guide: GitHub, Docker Hub, rulesets
├── scripts/
│   └── shell_setup.sh               # Starship prompt, aliases, history (build time)
├── tests/
│   └── smoke.sh                     # Runtime contract test (CI, amd64 + arm64)
├── .dockerignore                    # Allowlist — only what the build COPYs
├── .editorconfig · .gitattributes   # LF everywhere, consistent formatting
├── .gitignore                       # Editor settings, .env files, packed-repository output, bytecode
├── .hadolint.yaml                   # Dockerfile lint config
├── .markdownlint-cli2.jsonc         # Markdown lint config (editor + CI)
├── cspell.json                      # Spell-check config (en + en-GB, code dictionaries)
├── LICENSE                          # MIT
├── repomix.config.json              # Packs the repository into one file for sharing (output is git-ignored)
└── README.md                        # This file — also the Docker Hub page
```

---

## Updating the image

Open a PR from a topic branch into `develop`; `Lint` and the `Test` jobs build
and smoke-test both architectures. Merge it (merge commit, with a Conventional
Commit title). When `develop` is ready, open a PR `develop` → `main` and merge it — the
image publishes automatically.

**Updates arrive as Dependabot PRs into `develop`** (every Monday, after a 7-day
cooldown): GitHub Actions, the Python and uv images, and the pinned CLI tools —
every version, majors included. Review them in one monthly pass, let CI go
green, merge — they reach `main` with the next `develop` → `main` release. A
release with a new Python builds a new image; with only tool or system updates it
replaces `latest` and `python-X.Y` with the next revision.

**Python follows Django.** The image stays on the newest Python minor that
Django officially supports (3.12–3.14 today), so Dependabot proposes Python
**patch** updates only: 3.14.8 → 3.14.9 arrives as its own PR and publishes
`python-3.14.9.1`. A new minor (3.15, …) is never proposed while Django does not
list it. A weekly check reads the Python versions Django declares on PyPI and
opens an issue when Django adds one; then you move the `FROM python:` line,
`tests/smoke.sh` and this README together, and the image publishes
`python-3.15.0.1`. Projects on `python-3.14` keep getting 3.14 images until they
change their tag.

**A system package:** add it to the single `apt-get install` list in
`Dockerfile.dev`, grouped under a comment explaining why, and name it in the
"What's inside" table above (`Lint` checks that every package is documented).
Every build also runs `apt-get upgrade`, so the Debian packages are always the
newest at build time.

**uv:** a Dependabot PR bumps the pinned image (tag and digest). uv is pre-1.0, so
read the PR's release notes before merging a minor version.

**Starship:** nothing is pinned. Each build downloads the newest release and
checks it against the SHA-256 published with it; the weekly check rebuilds when a
newer release exists.

**A global Python CLI:** add `name==version` to `docker/requirements-tools.txt`
and a matching `uv tool install -c "$c" <name>` line in `Dockerfile.dev`. Only
tools useful to *every* project belong here — project dependencies go in the
project.

**Optionally, before opening the PR**, build and test locally (CI does the same on
every PR, about 15–25 minutes on a cold cache):

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

### Problems with the CI, tags or schedules

Those are for maintainers: a failed publish, a burned tag number, a quiet weekly
run, a paused schedule, an expired Docker Hub token. See
[`docs/github-setup.md`](https://github.com/alihaidar0/django-devcontainer/blob/main/docs/github-setup.md#12-maintenance-and-recovery).

---

## Documentation

- **This page:** what the image contains, its contract, tags and how it is built.
- [`.github/CONTRIBUTING.md`](https://github.com/alihaidar0/django-devcontainer/blob/main/.github/CONTRIBUTING.md): how the repository is operated (branches, rulesets, CI/CD, Dependabot).
- [`docs/github-setup.md`](https://github.com/alihaidar0/django-devcontainer/blob/main/docs/github-setup.md): setting it up and recovering it (GitHub, Docker Hub).
- [`docs/design-decisions.md`](https://github.com/alihaidar0/django-devcontainer/blob/main/docs/design-decisions.md): why each choice was made, and what was left out on purpose.

---

## License

[MIT](https://github.com/alihaidar0/django-devcontainer/blob/main/LICENSE) © Ali Haidar
