# Design decisions

Why this repository works the way it does. Each entry says what was decided, why, what was rejected and where it lives, so a later change starts from the reasons and not from guesswork. Operations (how to run it) are in [`.github/CONTRIBUTING.md`](../.github/CONTRIBUTING.md); setup and recovery are in [`github-setup.md`](github-setup.md); what the image contains is in the [README](../README.md).

- [The image](#the-image)
- [Supply chain and releases](#supply-chain-and-releases)
- [Branches and automation](#branches-and-automation)
- [Keeping the documentation true](#keeping-the-documentation-true)
- [Deliberately not done](#deliberately-not-done)

## The image

### 1. One job: build and publish the shared development image

- **Decision:** the repository builds, tests and publishes `alihaidar199527/django-devcontainer`, and nothing else. No Django files, no `pyproject.toml`, no Node.js, no application CI.
- **Why:** every project generated from `django-template` pulls this image, so a change here upgrades all of them. Anything about how a project is structured or deployed belongs in the template.
- **Where:** [README](../README.md), `docker/Dockerfile.dev`.

### 2. Pulled, never built, on a developer's machine

- **Decision:** CI builds the image once and publishes it; projects only pull it.
- **Why:** building a full Django environment takes 20–30 minutes and drifts between machines. A pull is seconds and identical everywhere.

### 3. Python follows Django

- **Decision:** the image uses the newest Python minor that Django officially supports (3.12–3.14 today, from the [Django FAQ](https://docs.djangoproject.com/en/stable/faq/install/) and the classifiers Django publishes on PyPI), on the latest patch. Dependabot proposes Python **patch** updates only; the weekly drift check announces when Django supports a new minor, and the move is then manual.
- **Why:** a project inherits the image's Python, so a Python Django does not support would put every new project outside what Django tests. Python 3.15 was released while Django still lists 3.14 as its newest.
- **Rejected:** following the newest Python released (a release candidate was once merged that way); a Dependabot `versions` range (its Docker range syntax is only loosely documented, `update-types` is explicit).
- **Where:** `docker/Dockerfile.dev` (the `FROM python:` line and its comment), the `ignore` rule in `.github/dependabot.yml`, `.github/scripts/check_drift.py`, the Python check in `tests/smoke.sh`.

### 4. uv is the installer; the image has no pip and almost no global tools

- **Decision:** only `pre-commit` and `watchfiles` are installed globally, each in its own `uv tool` environment. pip is removed. Everything else (ruff, mypy, pytest, Celery, Flower, IPython, pgcli, HTTPie) is project-level, pinned in the project's `uv.lock`; ad-hoc tools run with `uvx`.
- **Why:** `django-template` needs `pre-commit` before any virtual environment exists (its post-create step) and `watchfiles` for its Celery service. A global copy of anything else would drift from the version a project locks, and its own tool environments would bring pip along with vendored copies of `urllib3` and `msgpack` that scanners flag and no pip release fixes.
- **Rejected:** keeping the tools "for convenience"; patching or ignoring pip's vendored findings.
- **Where:** `docker/Dockerfile.dev` (tools block), `docker/requirements-tools.txt`, the "Left out on purpose" checks in `tests/smoke.sh`.

### 5. System packages: only what every Django project needs

- **Decision:** build-essential and `libpq-dev` (the one source build in a Django stack, `psycopg[c]`), the PostgreSQL client, redis-cli, GNU gettext, git, GitHub CLI, ssh, gnupg and a few shell and network utilities. No `-dev` headers for libraries that ship wheels (Pillow, lxml, cffi, `psycopg[binary]`), no `git-lfs`, no Docker CLI, no ripgrep, fzf, direnv or graphviz.
- **Why:** Pillow, lxml, cryptography, cffi and `psycopg[binary]` publish `cp314` wheels for amd64 and arm64, so their headers are dead weight and attack surface. gettext is required by Django's `makemessages` and `compilemessages`, which otherwise silently create empty files. A project that needs more installs it with `sudo apt-get`.
- **Where:** the apt block in `docker/Dockerfile.dev`; `Lint` fails when an installed package is not documented in the README.

### 6. A non-root user, and the project's environment wins

- **Decision:** user `dev` (UID/GID 1000, passwordless sudo). `/workspace/.venv/bin` is first on `PATH` in every shell, login shells included.
- **Why:** files created in the bind-mounted workspace keep sane ownership; after `uv sync` a project's own tools win with no activation step, and VS Code (which probes the environment with a login shell) sees the same `PATH`.
- **Where:** `docker/Dockerfile.dev`, `scripts/shell_setup.sh` (the profile script), the "Project venv precedence" section of `tests/smoke.sh`.

### 7. Aliases only for tools the image has

- **Decision:** Django (`pm`, `pmr`, …), uv, Git and a few `ls` aliases. No Celery or Docker aliases, no Starship Docker module.
- **Why:** an alias for a missing tool only fails. The eight Django aliases are also part of the contract that `django-template` reads.
- **Where:** `scripts/shell_setup.sh`, the "Shell aliases" table in the README, `tests/smoke.sh`.

### 8. Starship from a verified release, not a remote script

- **Decision:** each build downloads the newest Starship release tarball and checks it against the SHA-256 published with it. Nothing is pinned; the weekly check rebuilds when a newer release exists.
- **Why:** running a downloaded install script as root is the pattern supply-chain guidance warns against, and the Dockerfile already avoids it for uv. The checksum comes from the same release, so it catches a corrupted or tampered download but not a compromised release; that residual risk is accepted for a prompt binary.
- **Where:** `scripts/shell_setup.sh`.

### 9. `apt-get upgrade` on every build

- **Decision:** the base image is pinned by digest, and the build upgrades every Debian package on top of it. hadolint's rule against `apt-get upgrade` is ignored, with the reason written next to it.
- **Why:** a digest-pinned base freezes its packages at that day. Without an upgrade, a rebuild would change nothing, and security fixes (OpenSSL, the kernel headers, Redis) would wait for the next base-image bump. The cost is that a rebuild is not bit-for-bit reproducible; every revision is kept for rollback.
- **Where:** `docker/Dockerfile.dev`, `.hadolint.yaml`.

## Supply chain and releases

### 10. Tags: `python-X.Y.Z.R`, `python-X.Y`, `latest`

- **Decision:** `python-X.Y.Z.R` is immutable (Python `X.Y.Z`, image revision `R`); `python-X.Y` and `latest` move to the newest image. A new Python starts at revision 1 (for example `python-3.14.9.1`); any other change takes the next revision and moves the two moving tags. The git tag is created before anything is pushed, and every push-triggered publish (and the first image of a new Python) gets a GitHub Release with the same name.
- **Why:** the image is defined by its Python, as the official `python` images are. Reserving the git tag first keeps the image, tag and release from ever disagreeing, and skips names that release immutability has burned. The dotted numeric form lets Dependabot in a consuming repository order and bump the tag.
- **Rejected:** date and `sha-` tags (the commit is in the image label and the job summary); overwriting a tag.
- **Where:** `docker.yml` (`reserve-tag`, `publish`, `release`), `.github/scripts/reserve-tag.sh` and its tests, `.github/workflows/release.yml`, the `protect-tags` ruleset.

### 11. Release notes are the titles of the merged PRs

- **Decision:** the notes of a release list the PRs merged since the previous release, read from their merge commits (the PR title is the subject, or the first line of the body with GitHub's default message), grouped by Conventional Commit type. The `develop` → `main` merge itself is left out. `Lint` rejects a PR title that is not a Conventional Commit.
- **Why:** a PR is the unit of change, and its title is the only line a reviewer wrote on purpose. GitHub's generated notes are organised by label, which this repository does not maintain.
- **Where:** `.github/scripts/release-notes.sh` and its tests, the PR-title step in `lint.yml`.

### 12. Build and test what is published

- **Decision:** a PR is tested before it merges into `develop`, and the release run on `main` builds and tests the image again right before publishing. The Trivy gate (a CRITICAL finding that already has a fix fails the job) runs in the same test job.
- **Why:** because every build upgrades Debian packages (decision 9), the image published days or weeks after `develop` was tested contains newer packages than the tested one. Testing at publish time means the published image is one that was tested.
- **Where:** `docker.yml` (`test`, `reserve-tag`), `tests/smoke.sh`.

### 13. SBOM, signed provenance, and two scans

- **Decision:** publishing uses Docker's reusable builder (native amd64 and arm64 runners, no emulation, SBOM, keyless Sigstore-signed provenance). The gate before publishing fails on CRITICAL findings with a fix; the scan after publishing is informational and feeds the Security tab with HIGH and CRITICAL findings that have a fix.
- **Why:** a development image deliberately carries compilers, so a blocking scan of everything would block every release; a blocking scan of the worst findings that can be fixed does not.
- **Accepted findings:** `.github/vex.openvex.json` (one package version each, with the reason) and `.github/trivy-ignore.rego` (the kernel-headers package, which a container never runs, with the reason).
- **Where:** `docker.yml` (`publish`, `scan`).

### 14. The weekly rebuild check, and why it dispatches

- **Decision:** every Monday a job on `develop` simulates `apt-get upgrade` inside the published `latest` and compares the installed Starship with the newest release. If anything is newer, it starts the normal Docker run on `main`; otherwise nothing happens.
- **Why:** Debian, the GitHub CLI and PostgreSQL publish fixes continuously, and a monthly release would leave the image stale in between. Scheduled workflows always run from the default branch (`develop`), which never publishes, so the build itself runs on `main` as an ordinary manual publish.
- **Alternative:** delete the dispatch job and the check only reports; every publish is then a human merge. That is the choice made by repositories that publish only on release.
- **Where:** `docker.yml` (`rebuild-check`, `dispatch-build`), `.github/scripts/check-rebuild.sh` and its tests.

### 15. What Dependabot cannot see is watched by a weekly issue

- **Decision:** `dependency-drift.yml` compares the PostgreSQL major, the Debian release in the python image tag and the Python minor (against what Django supports) with upstream, and keeps one issue up to date; it closes itself when nothing is behind.
- **Why:** those pins are not in a manifest Dependabot reads, or, for Python, Dependabot is deliberately limited to patches.
- **Where:** `.github/workflows/dependency-drift.yml`, `.github/scripts/check_drift.py`.

## Branches and automation

### 16. `develop` is the default branch; nobody pushes to `develop` or `main`

- **Decision:** work goes on a topic branch and reaches `develop` through a PR with `Lint` and `Image tests` green and the branch up to date; Dependabot opens PRs the same way. `main` takes only a PR from `develop`, opened and merged by hand, and every merge into `main` is a release. Every PR is merged with a merge commit.
- **Why:** the model is the one used by the sibling Flutter image repository. Merge commits keep `main` and `develop` from diverging (a squash or rebase into `main` would give it commits `develop` lacks) and let the release notes read PR titles. `main` does not require "up to date": after each release it holds one merge commit `develop` does not.
- **Rejected:** squash merging into `develop` (one commit per PR, but it breaks the rule above for `main` and invites mixed methods); direct pushes to `develop`.
- **Where:** the three ruleset files in `.github/rulesets/`, `.github/workflows/branch-policy.yml` (the `PR source` check, because rulesets cannot restrict a PR's source branch).

### 17. Dependabot: everything, into `develop`, reviewed monthly

- **Decision:** GitHub Actions, the python and uv images and the tool pins are checked weekly after a 7-day cooldown, with no version ignored except Python minors and majors (decision 3). Each ecosystem is grouped; majors arrive alone; up to 10 PRs stay open. Dependabot security updates are on.
- **Why:** the cooldown lets a compromised or broken release be pulled upstream before it reaches a PR. With `develop` as the default branch, security PRs also land on `develop`, so every update is tested before it reaches `main`. A monthly review matches the monthly release.
- **Where:** `.github/dependabot.yml`.

### 18. Rulesets, secrets and labels

- **Decision:** the rulesets are stored as importable JSON; required checks are `PR source`, `Lint` and `Image tests` (never the per-architecture jobs, because a skipped matrix job reports an unexpanded name). The Docker Hub credentials are repository secrets, not an environment. Labels are limited to those something uses, are synced from `develop` (the default branch), and `pr-labels.yml` adds them to each PR from its Conventional Commit title; it only adds, and is not a required check.
- **Why:** the JSON files make a recreated repository a matter of importing three files. A job that calls a reusable workflow cannot declare an environment, so repository secrets are the only option for the publish job.
- **Where:** `.github/rulesets/`, `.github/labels.yml` and its two workflows (`labels.yml`, `pr-labels.yml`), [`github-setup.md`](github-setup.md).

## Keeping the documentation true

### 19. Documentation is checked, not trusted

- **Decision:** `Lint` fails when the README disagrees with the code: aliases, pinned tools, apt packages, the Python, PostgreSQL and Debian versions, the formats `django-template` parses, the workflow list, and the README's size (Docker Hub truncates it at 25 000 bytes). The scripts that carry logic have tests that need only bash.
- **Why:** the README is also the public Docker Hub page, and a stale table there is a public bug.
- **Where:** `.github/scripts/check-readme-sync.sh` and the `test-*.sh` scripts, run by `lint.yml`.

### 20. The contract with `django-template`

- **Decision:** four formats are read by the template's weekly check and are part of the runtime contract: `ARG PG_MAJOR=NN`, the first `FROM python:X.Y.Z…`, `FROM ghcr.io/astral-sh/uv:X.Y.Z@…`, and one `alias name=` per line. Changing one needs a matching change in the template in the same release; removing a tool or alias is a breaking change (`feat!:`).
- **Where:** the "Parsed by django-template" table in the README, enforced by `check-readme-sync.sh`.

## Deliberately not done

| Not done | Why |
| --- | --- |
| Global ruff, mypy, Celery, Flower, IPython, pgcli, HTTPie | Project-level; each project pins its own (decision 4) |
| ripgrep, fzf, direnv, graphviz, a Docker CLI | Not needed by every project; VS Code ships its own search, and the Docker CLI is useless without a mounted socket |
| `-dev` headers for Pillow, lxml, cffi | Wheels exist for both architectures (decision 5) |
| Python 3.15 | Not yet supported by any Django release (decision 3) |
| Renovate | Dependabot covers every pin |
| A `docker-hub` environment | A reusable-workflow caller cannot declare one (decision 18) |
| Required reviewers | There is one maintainer, and an author cannot approve their own PR; raise the count when a second maintainer joins |
| OpenSSF Scorecard and a dependency-review workflow | Optional extras; Dependabot alerts, CodeQL, secret scanning and the Trivy gate already cover the same ground |
| Pinning Starship to a version | The weekly check keeps it current without manual bumps (decision 8) |
