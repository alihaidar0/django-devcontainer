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
            direct pushes          Dependabot PRs
                  │                      │
                  ▼                      ▼
develop  ──────────────────────────────────────  (integration: tested on every push)
                  │
                  └──PR──▶  main   (release: every merge publishes :latest)
```

| Branch | Role | Direct push? | Accepts PRs from |
| --- | --- | --- | --- |
| `main` | Released history — the default branch; merges publish the image | ❌ | `develop` **only** |
| `develop` | Integration branch — daily work lands here | ✅ | Dependabot (and any short-lived branch) |

- Work is committed and pushed **directly to `develop`**. Every push runs
  `Lint` and `Image tests` on that commit.
- A release is a PR **`develop` → `main`**. It needs no new CI run: status checks
  attach to the commit, so the PR reuses the results of develop's head commit.
- Dependabot opens every update PR against `develop`.

Commit messages and PR titles follow **Conventional Commits**
(`feat` `fix` `chore` `docs` `style` `refactor` `perf` `test` `build` `ci` `revert`).

A change to the image's runtime contract (user, paths, `PATH`, removed tools)
is **breaking** for `django-template`: use `feat!:` / a `BREAKING CHANGE:`
footer, label the PR `breaking change`, and land the matching template change
at the same time.

---

## 2. GitHub settings (apply in the UI)

**Settings → Rules → Rulesets → New branch ruleset** — create two.

### Ruleset `protect-main`

| Setting | Value |
| --- | --- |
| Target branches | `main` (Include default branch) |
| Enforcement status | **Active** |
| Bypass list | *empty* |
| **Restrict creations** | ✅ |
| **Restrict updates** | ❌ — with an empty bypass list it blocks **every** update to `main`, PR merges included |
| **Restrict deletions** | ✅ |
| **Block force pushes** | ✅ |
| **Require a pull request before merging** | ✅ |
| &nbsp;&nbsp;Required approvals | **0** while solo (raise to 1 with a second maintainer) |
| &nbsp;&nbsp;Require review from Code Owners | ❌ while solo — the author can't approve their own PR, so it would block every merge; enable (with 1 approval) once there is a second maintainer ([`CODEOWNERS`](CODEOWNERS) is ready) |
| &nbsp;&nbsp;Require conversation resolution | ✅ |
| &nbsp;&nbsp;Allowed merge methods | **Merge** only — squash/rebase would give `main` new commits that `develop` doesn't have |
| **Require status checks to pass** | ✅ → **`PR source`**, **`Lint`**, **`Image tests`** — set each check's source to **GitHub Actions** (not "Any source"), so no other integration can post a passing status with the same name |
| &nbsp;&nbsp;Require branches to be up to date | ❌ — `main` only ever receives `develop`, so this would just force a pointless re-sync after every release |

> **"Only `develop` may open PRs into `main`"** can't be expressed as a
> ruleset — GitHub has no "restrict PR source branch" rule. The `PR source`
> check in [`workflows/branch-policy.yml`](workflows/branch-policy.yml) fails any
> PR into `main` whose head isn't this repo's `develop`; requiring it here makes
> the rule binding.
>
> `Lint` and `Image tests` run on every `develop` commit. Require `Image tests`,
> not the per-arch `Test (…)` jobs: a matrix job skipped by `if` reports an
> unexpanded name, so a required per-arch check would wait forever.

### Ruleset `protect-develop`

| Setting | Value |
| --- | --- |
| Target branches | `develop` |
| Enforcement status | **Active** |
| **Restrict deletions** | ✅ — also stops *Automatically delete head branches* from deleting `develop` after a release |
| **Block force pushes** | ✅ |
| **Require a pull request before merging** | ❌ — direct pushes are allowed |

**Settings → General:** default branch **`main`**; *Template repository* ❌ (only
`django-template` is a template); under *Pull Requests*: *Allow merge commits* ✅
(the only method `protect-main` accepts) and *Automatically delete head
branches* ✅ (cleans up Dependabot branches — `develop` is protected by the
ruleset above).

**Settings → Advanced Security:** enable *Private vulnerability reporting*,
*Dependency graph*, *Dependabot alerts*, *Dependabot malware alerts*, *Secret
Protection* + *Push protection*, and *CodeQL analysis → Default setup* (it
scans the GitHub Actions workflows; Trivy SARIF lands in the same Code scanning
tab). Leave **Dependabot security updates OFF**: GitHub always opens those PRs against the default
branch (`main`), which only accepts PRs from `develop`. The weekly version
updates in §4 carry fixed versions through `develop` instead.

**Settings → General → About:** the repository description is also published
as the Docker Hub short description (≤ 100 characters).

---

## 3. CI/CD

### [`workflows/docker.yml`](workflows/docker.yml) — test on develop, publish on main

Every commit is tested **once**; merging into `main` only publishes.

| Trigger | Jobs |
| --- | --- |
| Push to `develop` | `Detect image changes` (develop vs `main`) → `Test (amd64)` + `Test (arm64)` **only if** `docker/`, `scripts/`, `tests/`, `.dockerignore`, or the workflow differ → `Image tests` |
| PR into `develop` (Dependabot) | Same, based on the PR's files — so an update is tested before you merge it |
| Merge `develop` → `main` | **Publish** → **Scan**, only if the image inputs changed (no re-test: develop's head commit already passed `Image tests`) |
| Weekly — Monday 05:00 UTC (`main`) | Test → Publish → Scan (fresh Debian/apt packages + Starship; untested build, so it's tested first) |
| Manual dispatch (`main`) | Test → Publish (toggle `push`; `no_cache` for a clean rebuild) → Scan |

- **Test** builds each architecture on its own native runner (`ubuntu-26.04`,
  `ubuntu-26.04-arm`) and runs the smoke test inside the image.
- On `develop`, change detection compares against **`main`**, so every develop
  commit that carries unreleased image changes is tested — a later docs-only
  push can't hide an earlier failing image change.
- **Publish** uses Docker's official reusable
  [`docker/github-builder`](https://github.com/docker/github-builder): native
  per-arch builds, a multi-arch manifest, SBOM, and a **Sigstore-signed SLSA
  provenance attestation** (keyless, GitHub OIDC). Tags: `latest`,
  `YYYYMMDD`, `sha-<short>`. It only ever runs on `main`.
- **Scan** runs Trivy against the pushed digest and uploads SARIF to the
  Security tab. Informational (`exit-code: 0`): a dev image intentionally ships
  compilers and headers.

GitHub pauses scheduled workflows after 60 days without repository activity —
re-enable under **Actions → Docker**.

### [`workflows/branch-policy.yml`](workflows/branch-policy.yml) — required check `PR source`

Runs on every PR into `main` and fails unless the head is this repository's
`develop` branch.

### [`workflows/lint.yml`](workflows/lint.yml) — required check `Lint` (develop pushes + PRs into develop)

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

Weekly (Monday 09:00 UTC), PRs against **`develop`**, **7-day cooldown**:

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
  majors arrive alone.
- **Security updates:** the *Dependabot security updates* setting stays off —
  GitHub opens those PRs against `main` only, which accepts PRs from `develop`
  alone. Alerts stay on; the weekly version updates bring the fixed versions
  through `develop`, and `Image tests` checks them before release.
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
| `workflows/branch-policy.yml` | `PR source` — only `develop` may open PRs into `main` |
| `workflows/dockerhub-description.yml` | README → Docker Hub |
| `workflows/labels.yml` | `labels.yml` → GitHub labels |
