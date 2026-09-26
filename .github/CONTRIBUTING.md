# Contributing & repository operations — `django-devcontainer`

Source of truth for **branching, protection rules, CI/CD, and dependency
automation**. Some pieces are applied on GitHub (rulesets, settings) rather than
in the repo. The image itself is documented in the root [`README.md`](../README.md).

> **Scope check first:** a change belongs here only if it improves the developer
> environment for *every* Django project (a system tool, a Python upgrade, a
> global CLI tool, an alias). Project structure, compose, hooks, app CI, and the
> production image belong in `django-template`.

---

## 1. Branching model

```text
feature/*  ─PR─▶  main   (every merge publishes :latest)
```

| Branch | Role | Direct push? |
| --- | --- | --- |
| `main` | Published history — each merge builds and pushes the image | ❌ (PR only) |
| `feature/*`, `fix/*`, `chore/*` | Short-lived work branches | ✅ |

Commit messages and PR titles follow **Conventional Commits**
(`feat` `fix` `chore` `docs` `style` `refactor` `perf` `test` `build` `ci` `revert`).

A change to the image's runtime contract (user, paths, `PATH`, removed tools)
is **breaking** for `django-template`: use `feat!:` / a `BREAKING CHANGE:`
footer, label the PR `breaking change`, and land the matching template change
at the same time.

---

## 2. GitHub settings (apply in the UI)

**Settings → Rules → Rulesets → New branch ruleset** — `protect-main`:

| Setting | Value |
| --- | --- |
| Target branches | `main` (Include default branch) |
| Enforcement status | **Active** |
| Bypass list | *empty* |
| **Restrict deletions** | ✅ |
| **Block force pushes** | ✅ |
| **Require a pull request before merging** | ✅ |
| &nbsp;&nbsp;Required approvals | **0** while solo (raise to 1 with a second maintainer) |
| &nbsp;&nbsp;Require review from Code Owners | ✅ (uses [`CODEOWNERS`](CODEOWNERS)) |
| &nbsp;&nbsp;Require conversation resolution | ✅ |
| &nbsp;&nbsp;Allowed merge methods | **Squash** |
| **Require status checks to pass** | ✅ → **`Lint`** and **`Image tests`** |

> Both checks report on **every** PR. `Image tests` passes when the image was
> built and smoke-tested on amd64 + arm64, or when the PR doesn't touch the
> image inputs (docs-only PRs aren't blocked). Require `Image tests`, not the
> per-arch `Test (…)` jobs: a matrix job skipped by `if` reports an unexpanded
> name, so a required per-arch check would wait forever.
>
> These required checks are what make the merge safe **without re-running
> anything**: `Lint` is PR-only, and the merge only publishes.

**Settings → Code security:** enable *Dependabot alerts*, *Dependabot security
updates*, *Private vulnerability reporting*, and *Code scanning* (Trivy SARIF).

**Settings → General → About:** the repository description is also published
as the Docker Hub short description (≤ 100 characters).

---

## 3. CI/CD

### [`workflows/docker.yml`](workflows/docker.yml) — test on the PR, publish on merge

Each job runs **once per change** — nothing tested on the PR is re-run on merge.

| Trigger | Jobs |
| --- | --- |
| Any PR into `main` | `Detect image changes` → `Test (amd64)` + `Test (arm64)` **only if** `docker/`, `scripts/`, `tests/`, `.dockerignore`, or the workflow changed → `Image tests` (required) |
| Merge to `main` touching those paths | **Publish** → **Scan** (no re-test: the PR tested the exact merged tree) |
| Weekly — Monday 05:00 UTC | Test → Publish → Scan (fresh Debian/apt packages + Starship; untested build, so it's tested first) |
| Manual dispatch | Test → Publish (toggle `push`; `no_cache` for a clean rebuild) → Scan |

- **Test** builds each architecture on its own native runner (`ubuntu-26.04`,
  `ubuntu-26.04-arm`) and runs the smoke test inside the image.
- **Publish** uses Docker's official reusable
  [`docker/github-builder`](https://github.com/docker/github-builder): native
  per-arch builds, a multi-arch manifest, SBOM, and a **Sigstore-signed SLSA
  provenance attestation** (keyless, GitHub OIDC). Tags: `latest` (main only),
  `YYYYMMDD`, `sha-<short>`.
- **Scan** runs Trivy against the pushed digest and uploads SARIF to the
  Security tab. Informational (`exit-code: 0`): a dev image intentionally ships
  compilers and headers.

GitHub pauses scheduled workflows after 60 days without repository activity —
re-enable under **Actions → Docker**.

### [`workflows/lint.yml`](workflows/lint.yml) — required check `Lint` (PR-only)

hadolint ([`.hadolint.yaml`](../.hadolint.yaml)) · ShellCheck (`scripts/`,
`tests/`) · actionlint ([`actionlint.yaml`](actionlint.yaml)) · cspell
([`cspell.json`](../cspell.json)) over every tracked file, dotfiles included ·
markdownlint ([`.markdownlint-cli2.jsonc`](../.markdownlint-cli2.jsonc)) over every
Markdown file — the VS Code markdownlint extension reads the same config.

**Spelling:** cspell uses English (US + GB) plus code dictionaries (Python,
Bash, Docker, software terms, companies). When it flags a **real name** — a
tool, package, env var, or alias — add it to
[`.cspell/project-words.txt`](../.cspell/project-words.txt) in the matching
group; when it flags a **typo**, fix the typo. Keep the file sorted per group.
The VS Code *Code Spell Checker* extension (recommended in
`.vscode/extensions.json`) reads the same config, so issues show while typing.

### Other workflows

| Workflow | What |
| --- | --- |
| [`dockerhub-description.yml`](workflows/dockerhub-description.yml) | Syncs `README.md` + repo description to Docker Hub on merge to `main` (no PR trigger — unmerged docs never publish) |
| [`labels.yml`](workflows/labels.yml) | Syncs [`labels.yml`](labels.yml) on `main`; PRs get a dry run; labels not in the file are kept |

Required secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (Docker Hub personal
access token, Read & Write). `GITHUB_TOKEN` is automatic.

### Workflow hardening (keep it when editing)

- Every action — and the reusable builder workflow — pinned to a **full commit
  SHA** with a `# vX.Y.Z` comment; Dependabot bumps both. Resolve a SHA with
  `git ls-remote https://github.com/<owner>/<repo>.git refs/tags/<tag>`.
- Explicit runner images (`ubuntu-26.04`, `ubuntu-26.04-arm`), never
  `ubuntu-latest`, so the OS changes only in a reviewed PR. Dependabot does not
  bump runner labels; moving to the next LTS is a manual PR.
- Top-level `permissions: contents: read`; jobs widen only what they need
  (`id-token: write` for signing, `security-events: write` for SARIF).
- `persist-credentials: false` on every checkout; `timeout-minutes` on every job.
- Event values reach `run:` scripts only through `env:`, never as inline
  `${{ }}`, so a crafted branch name can't inject shell.

---

## 4. Dependency automation — [`dependabot.yml`](dependabot.yml)

Weekly (Monday 09:00 UTC), PRs against `main`, **7-day cooldown** (security
updates are never delayed):

| Ecosystem | Scans | Notes |
| --- | --- | --- |
| `github-actions` | `.github/workflows/*` | SHA pins + version comments, incl. the reusable builder; one grouped PR |
| `docker` | `docker/Dockerfile.dev` | `FROM` lines — the `python` base image and the `uv` image (tag + digest) |
| `pip` | `docker/requirements-tools.txt` | Pinned global CLIs: ruff, mypy, pre-commit, ipython, pgcli, httpie, celery, flower, watchfiles |

- `FROM` lines are **literal** (no `ARG` substitution) because Dependabot
  cannot resolve build args in `FROM` — an `ARG`-based base image is never
  updated.
- Every **Python** bump arrives as its own PR (excluded from the Docker
  group). A minor bump (3.14 → 3.15) fails `tests/smoke.sh` on purpose until
  the pinned minor there is updated — the upgrade stays a deliberate step.
- Other Docker and all tool minor + patch updates are grouped per ecosystem;
  majors arrive alone; security updates have their own groups.
- `tests/smoke.sh` verifies every pin in `requirements-tools.txt` is exactly
  what's installed, so a tool PR can't silently resolve to another version.
- Every label Dependabot applies must exist in [`labels.yml`](labels.yml).
- Only Debian/apt packages (gh, PostgreSQL client, …) and the Starship binary
  are outside Dependabot — no ecosystem exists for them. The weekly scheduled
  rebuild keeps them current.

---

## 5. Local checks before a PR

```bash
docker build -f docker/Dockerfile.dev -t django-devcontainer:test .
docker run --rm -v "$PWD/tests:/tests:ro" django-devcontainer:test bash /tests/smoke.sh
docker run --rm -i hadolint/hadolint hadolint - < docker/Dockerfile.dev
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable scripts/*.sh tests/*.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest
docker run --rm -v "$PWD:/repo" -w /repo node:24-slim npx -y cspell@10 lint --no-progress --dot "**"
docker run --rm -v "$PWD:/workdir" davidanson/markdownlint-cli2 "**/*.md"
```

cspell runs in a throwaway Node container (or as the GitHub Action in CI) —
Node is repository tooling only and never enters the image.

---

## 6. Files in `.github/`

| Path | Purpose |
| --- | --- |
| `CONTRIBUTING.md` | This document |
| `CODEOWNERS` | Auto review-request routing (`@alihaidar0`) |
| `SECURITY.md` | Private vulnerability reporting policy |
| `actionlint.yaml` | actionlint config (Ubuntu 26.04 runner labels) |
| `dependabot.yml` | Dependency update automation |
| `labels.yml` | Repository labels as code |
| `pull_request_template.md` | PR checklist |
| `ISSUE_TEMPLATE/` | Bug + feature issue forms; blank issues disabled |
| `workflows/docker.yml` | Test, publish, and scan the image |
| `workflows/lint.yml` | hadolint · ShellCheck · actionlint · cspell · markdownlint |
| `workflows/dockerhub-description.yml` | README → Docker Hub |
| `workflows/labels.yml` | `labels.yml` → GitHub labels |
