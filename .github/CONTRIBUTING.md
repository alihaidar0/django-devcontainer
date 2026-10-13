# Contributing & repository operations — `django-devcontainer`

Source of truth for **branching, protection rules, CI/CD, and dependency
automation**. Some pieces are applied on GitHub (rulesets, settings) rather than
in the repo. The image itself is documented in the root [`README.md`](../README.md).

> **Scope check first:** a change belongs here only if it improves the developer
> environment for *every* Django project (a system tool, a Python upgrade, a
> global CLI tool, an alias). Project structure, compose, hooks, app CI, and the
> production image belong in `django-template`.

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md);
vulnerabilities go through [`SECURITY.md`](SECURITY.md), never a public issue.
The reasons behind each rule below are in
[`docs/design-decisions.md`](../docs/design-decisions.md); setting the repository
up or recovering it is in [`docs/github-setup.md`](../docs/github-setup.md).

---

## 1. Branching model

```text
 feat/*  fix/*  docs/*  ci/*  chore/*          Dependabot PRs
        │                                            │
        └──── PR (merge commit) ──────┬──────────────┘
                                      ▼
                develop  ← default branch, protected, tested on every push
                                      │
                                      └──PR (merge commit)──▶  main
                                                         (every merge publishes)
```

| Branch | Role | Direct push? | Accepts PRs from |
| --- | --- | --- | --- |
| `main` | Released history — the publish branch; merges publish the image | ❌ | `develop` **only** |
| `develop` | Integration branch and the repository's **default branch** | ❌ | Any topic branch, and Dependabot |

- **Nobody pushes to `main` or `develop`**, administrators included. Work goes on a
  topic branch (`feat/…`, `fix/…`, `docs/…`, `ci/…`, `chore/…`) and reaches
  `develop` through a PR, which needs `Lint` and `Image tests` green and the
  branch up to date with `develop`. Every PR is merged with a **merge commit**
  (never squash or rebase), on `develop` and on `main` alike.
- **The PR title is the release note.** The notes of a release are the titles of
  the PRs merged since the previous release, read from their merge commits, so the
  title must be a Conventional Commit (`Lint` checks it; Dependabot titles
  already are). Set *Settings → General → Pull Requests → Allow merge commits →
  Default commit message* to **Pull request title and description**, so the merge
  commit is named after the PR title.
- Every push to `develop` (a merged PR) runs `Lint` and `Image tests` again on the
  new head commit.
- A release is a PR **`develop` → `main`**, opened and merged by you with a **merge
  commit**. The PR itself needs no new CI run: status checks attach to the commit, so
  it reuses the results of develop's head commit. The publish run on `main` then
  rebuilds and tests the image once more, because every build upgrades the Debian
  packages.
- Dependabot opens every update PR against `develop`. Review and merge them in
  one monthly pass, then release once.
- What the release publishes depends on what changed: a new Python version
  (a Dependabot bump of the `FROM python:` line) is built as a new image
  `python-X.Y.Z.1`, while a tools-only or system-package update is the next
  revision of the same Python and **replaces** `latest` and `python-X.Y` (the old
  revision stays available).

Commit messages and PR titles follow **Conventional Commits**
(`feat` `fix` `chore` `docs` `style` `refactor` `perf` `test` `build` `ci` `revert`).

A change to the image's runtime contract (user, paths, `PATH`, removed tools)
is **breaking** for `django-template`: use `feat!:` / a `BREAKING CHANGE:`
footer, label the PR `breaking change`, and land the matching template change
at the same time.

---

## 2. GitHub settings (apply in the UI)

This section is a summary of the rulesets and the settings that matter for the
branch model. **The complete, click-by-click list of every GitHub and Docker Hub
setting (General, Rulesets, Actions permissions, Environments, Advanced Security)
is [`docs/github-setup.md`](../docs/github-setup.md)**; keep the two in step.

**Settings → Rules → Rulesets → New branch ruleset** — create two branch
rulesets and one tag ruleset. All three are also stored as JSON in
[`rulesets/`](rulesets/) ([`protect-main.json`](rulesets/protect-main.json),
[`protect-develop.json`](rulesets/protect-develop.json),
[`protect-tags.json`](rulesets/protect-tags.json)): on a fresh or recreated
repository use **New ruleset → Import a ruleset** instead of clicking the settings
below by hand. The JSON mirrors the tables below; after changing a ruleset in the UI,
update the JSON (and these tables) to match.

### Ruleset `protect-main`

| Setting | Value |
| --- | --- |
| Target branches | `main` |
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
| Bypass list | *empty* |
| **Restrict deletions** | ✅ — also stops *Automatically delete head branches* from deleting `develop` after a release |
| **Block force pushes** | ✅ |
| **Require a pull request before merging** | ✅ — no direct pushes |
| &nbsp;&nbsp;Required approvals | **0** while solo (raise to 1 with a second maintainer) |
| &nbsp;&nbsp;Require conversation resolution | ✅ |
| &nbsp;&nbsp;Allowed merge methods | **Merge** only — the merge commit is named after the PR title, which is what the release notes are built from |
| **Require status checks to pass** | ✅ → **`Lint`**, **`Image tests`** — source **GitHub Actions** |
| &nbsp;&nbsp;Require branches to be up to date | ✅ — a PR is tested on top of the current `develop` before it merges. In a monthly batch the remaining Dependabot PRs fall behind after each merge: Dependabot rebases them itself (`rebase-strategy: auto`), or use **Update branch** on a topic branch |

### Ruleset `protect-tags`

| Setting | Value |
| --- | --- |
| Target | Tags matching `python-*` |
| Enforcement status | **Active** |
| Bypass list | *empty* |
| **Restrict updates** | ✅ — a released image tag can never be moved |
| **Restrict deletions** | ✅ |
| **Restrict creations** | ❌ — the `Reserve image tag` job creates one tag per image |

**Settings → General → Releases → Enable release immutability** (if offered):
✅. It locks a published release and its tag and reserves the tag name for good —
even if the release and the tag are deleted, GitHub never lets that name be used
again. The pipeline copes with this: it reserves each image's git tag before
publishing and skips names GitHub refuses (§3).

**Docker Hub:** keep tag retention and inactive-image clean-up **off** for this
repository, otherwise old `python-X.Y.Z.R` tags can expire outside the pipeline.

**Settings → General:** default branch **`develop`** (new PRs, Dependabot security
updates and the *Run workflow* dropdown start from it, and scheduled workflows run
from it; `main` stays the publish branch); *Template repository* ❌ (only
`django-template` is a template); under *Pull Requests*: *Allow merge commits* ✅
with the default commit message **Pull request title and description** (the only
method `protect-main` and `protect-develop` accept), *Allow squash merging* ❌,
*Allow rebase merging* ❌, and *Automatically delete head branches* ✅ (cleans up
topic and Dependabot branches — `develop` is protected by the ruleset above).
*Allow auto-merge* is optional and convenient for Dependabot PRs once checks pass.

**Settings → Advanced Security:** enable *Private vulnerability reporting*,
*Dependency graph*, *Dependabot alerts*, *Dependabot malware alerts*, *Secret
Protection* + *Push protection*, and *CodeQL analysis → Default setup* (it
scans the GitHub Actions workflows; Trivy SARIF lands in the same Code scanning
tab). Turn **Dependabot security updates ON**: GitHub opens those PRs against the
default branch, which is `develop`, so they are tested by `Image tests` and reach
`main` with the next release like every other change.

**Settings → General → About:** the repository description is also published
as the Docker Hub short description (≤ 100 characters).

---

## 3. CI/CD

### [`workflows/docker.yml`](workflows/docker.yml) — test on develop, publish on main

Every commit is tested **once**; merging into `main` only publishes.

| Trigger | Jobs |
| --- | --- |
| Push to `develop` (a merged PR) | `Detect image changes` (develop vs `main`) → `Test (amd64)` + `Test (arm64)` **only if** `docker/`, `scripts/`, `tests/`, `.dockerignore`, or the workflow differ → `Image tests` |
| PR into `develop` (topic branch or Dependabot) | Same, based on the PR's files — so a change is tested before you merge it; `Lint` also checks the PR title |
| Merge `develop` → `main` | `Test` (amd64 + arm64, again) → **Reserve image tag** → **Publish** → **Scan** + **Release**, only if the image inputs changed. The release PR itself reuses develop's green `Image tests`; the image is rebuilt and tested at publish time because every build runs `apt-get upgrade` |
| Weekly — Monday 05:00 UTC (runs on `develop`, the default branch) | `Rebuild needed?` → only if apt has upgrades or Starship has a newer release: `Start the rebuild on main` dispatches **Docker** on `main`, which runs Test → Reserve image tag → Publish → Scan. Nothing new: nothing starts and the run is green. A Release only if it is the first image of a new Python version |
| Manual dispatch (`main`) | Test → Reserve image tag → Publish (toggle `push`; `no_cache` for a clean rebuild) → Scan (+ Release for a new Python version) |

- **Rebuild needed?** ([`scripts/check-rebuild.sh`](scripts/check-rebuild.sh),
  tested on every `Lint` run by
  [`scripts/test-check-rebuild.sh`](scripts/test-check-rebuild.sh)) runs only on
  the weekly schedule. Scheduled workflows run from the default branch
  (`develop`), which never publishes, so when the check finds something the
  `Start the rebuild on main` job dispatches the Docker workflow on `main`; that
  run is an ordinary manual publish. Inside the published `latest` it simulates
  `apt-get upgrade` (any `Inst` line means a rebuild picks up a fix) and compares
  the installed Starship with the newest release; a missing `latest` always
  builds. It writes the reasons to the job summary. When nothing changed nothing
  is dispatched and the run finishes green; manual runs always build. This works because the Dockerfile runs
  `apt-get upgrade`: the base image is pinned by digest, so without it a rebuild
  would leave every base package at that day's version (hadolint's `DL3005` is
  ignored in [`.hadolint.yaml`](../.hadolint.yaml) for that reason).
- **Vulnerability gate** (last step of `Test (amd64)`): Trivy fails the job on a
  CRITICAL finding that already has a fix, which fails the required
  `Image tests` check before anything is published. Accepted findings are
  `vex.openvex.json` and `trivy-ignore.rego`, each with its reason. The scan
  after publishing stays informational.
- **Test** builds each architecture on its own native runner (`ubuntu-26.04`,
  `ubuntu-26.04-arm`) and runs the smoke test inside the image.
- On `develop`, change detection compares against **`main`**, so every develop
  commit that carries unreleased image changes is tested — a later docs-only
  push can't hide an earlier failing image change.
- **Reserve image tag** names the image `python-X.Y.Z.R`: `X.Y.Z` is read from
  the literal `FROM python:…` line of `docker/Dockerfile.dev` (the base image is
  pinned by digest, so it is exactly the Python inside), and `R` is the first
  revision that is free on Docker Hub **and** creatable as a git tag
  ([`scripts/reserve-tag.sh`](scripts/reserve-tag.sh), tested on every `Lint`
  run by [`scripts/test-reserve-tag.sh`](scripts/test-reserve-tag.sh)). It creates
  the git tag **before** anything is pushed, so the image, the git tag and the
  release can never disagree. It also carries the publish conditions: when it is
  skipped, nothing is published.
- **Publish** uses Docker's official reusable
  [`docker/github-builder`](https://github.com/docker/github-builder): native
  per-arch builds, a multi-arch manifest, SBOM, and a **Sigstore-signed SLSA
  provenance attestation** (keyless, GitHub OIDC). Tags: `python-X.Y.Z.R`
  (immutable), plus the moving `python-X.Y` and `latest`. It only ever runs on
  `main`.
- **Release** ([`workflows/release.yml`](workflows/release.yml), reusable) creates
  the GitHub Release named after the image tag from the reserved git tag, with
  the `docker pull` command, the digest and the commits since the previous
  release grouped by Conventional Commit type
  ([`scripts/release-notes.sh`](scripts/release-notes.sh)). Every PR into
  `develop` is merged with a merge commit named after its title: write
  meaningful Conventional Commit titles, they are the release notes.
  A release is created for every push to `main` that changes the image and for
  the first image of a new Python version; other rebuilds (the weekly one)
  only add a revision.
- **Scan** runs Trivy against the pushed digest and uploads SARIF to the
  Security tab. Informational (`exit-code: 0`): a dev image intentionally ships
  compilers and headers. [`vex.openvex.json`](vex.openvex.json) (OpenVEX,
  passed as `TRIVY_VEX`) marks findings that don't apply as `not_affected`, each
  pinned to one package version with its reason. It covers packages that appear
  only in SBOM files shipped inside pip and virtualenv (bundled or embedded copies).
  Add a statement only after confirming the vulnerable code isn't installed or
  can't run. Remove it once upstream ships the fix.
  [`trivy-ignore.rego`](trivy-ignore.rego) (`ignore-policy`) drops whole packages
  that cannot affect a container — today only `linux-libc-dev`, the kernel
  *headers* pulled in by `build-essential`: Debian files every kernel CVE against
  it, but a container runs on the host's kernel. `limit-severities-for-sarif`
  keeps the Security tab to the HIGH/CRITICAL findings that have a fix.
  Most remaining findings clear with the next rebuild, because every build runs
  `apt-get upgrade` and the Monday check rebuilds when apt has something new:
  check the date of `latest` before treating an alert as a bug.

GitHub pauses scheduled workflows after 60 days without repository activity —
re-enable under **Actions → Docker**.

### [`workflows/branch-policy.yml`](workflows/branch-policy.yml) — required check `PR source`

Runs on every PR into `main` and fails unless the head is this repository's
`develop` branch.

### [`workflows/lint.yml`](workflows/lint.yml) — required check `Lint` (develop pushes + PRs into develop)

hadolint ([`.hadolint.yaml`](../.hadolint.yaml)) · ShellCheck (`scripts/`,
`tests/`, `.github/scripts/`) · actionlint ([`actionlint.yaml`](actionlint.yaml)) ·
format (LF line endings, no trailing whitespace, final newline — a CRLF
`shell_setup.sh` breaks the image) · README sync · cspell
([`cspell.json`](../cspell.json)) over every tracked file, dotfiles included ·
markdownlint ([`.markdownlint-cli2.jsonc`](../.markdownlint-cli2.jsonc)) over every
Markdown file — the VS Code markdownlint extension reads the same config.

**README sync** ([`scripts/check-readme-sync.sh`](scripts/check-readme-sync.sh)):
`README.md` is also the Docker Hub page, so `Lint` fails when it drifts from the
code. It checks that every alias in `scripts/shell_setup.sh` is in the README
alias table (and the reverse), every CLI pinned in `docker/requirements-tools.txt`
is named, the Python minor, PostgreSQL major, and Debian codename in
`docker/Dockerfile.dev` match what the README says, and every file in
`.github/workflows/` appears in the repository tree. Run it locally with
`bash .github/scripts/check-readme-sync.sh`.

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
| [`labels.yml`](workflows/labels.yml) | Syncs [`labels.yml`](labels.yml) when it changes on `develop`; PRs get a dry run; labels not in the file are kept |
| [`pr-labels.yml`](workflows/pr-labels.yml) | Adds labels to a PR from its Conventional Commit title (`feat` → `enhancement`, `fix` → `bug`, `docs` → `documentation`, `ci` → `ci`, other types → `chore`, scope `deps` / `docker`, `!` → `breaking change`, `develop` → `main` → `release`). It only adds, never removes, and skips Dependabot (which labels itself) |
| [`dependency-drift.yml`](workflows/dependency-drift.yml) | Mondays 06:00 UTC: one issue for the PostgreSQL major, the Debian release and the Python minor that are behind upstream (Python is compared with what **Django supports**, not with the newest Python); closes itself when current |

Required secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (Docker Hub personal
access token, **Read, Write & Delete** — the description sync needs Delete). `GITHUB_TOKEN` is automatic.

### Workflow hardening (keep it when editing)

- Every action — and the reusable builder workflow — pinned to a **full commit
  SHA** with a `# vX.Y.Z` comment; Dependabot bumps both. Resolve a SHA with
  `git ls-remote https://github.com/<owner>/<repo>.git refs/tags/<tag>`.
- Explicit runner images (`ubuntu-26.04`, `ubuntu-26.04-arm`), never
  `ubuntu-latest`, so the OS changes only in a reviewed PR. Dependabot does not
  bump runner labels; moving to the next LTS is a manual PR.
- Top-level `permissions: contents: read`; jobs widen only what they need
  (`id-token: write` for signing, `security-events: write` for SARIF,
  `contents: write` only in `Reserve image tag` and the release job, to create the
  git tag and the release).
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
| `pip` | `docker/requirements-tools.txt` | The two pinned global CLIs: pre-commit, watchfiles |

- `FROM` lines are **literal** (no `ARG` substitution) because Dependabot
  cannot resolve build args in `FROM` — an `ARG`-based base image is never
  updated.
- **Python follows Django.** The base image stays on the newest Python minor
  that Django officially supports (3.12–3.14 today, per the
  [Django FAQ](https://docs.djangoproject.com/en/stable/faq/install/)).
  Dependabot's `ignore` rule for `python` skips every minor and major bump, so
  only patch updates arrive, each as its own PR (excluded from the Docker group).
  When Django adds a newer Python, `dependency-drift.yml` opens the issue; the move
  is then manual: the `FROM python:` line (tag and digest), the pinned minor in
  `tests/smoke.sh` and the README together, and remove nothing from the ignore rule
  (minor moves are always manual).
- Other Docker and all tool minor + patch updates are grouped per ecosystem;
  majors arrive alone.
- **Security updates:** the *Dependabot security updates* setting is on —
  GitHub opens those PRs against the default branch, which is `develop`, so
  `Image tests` checks them before release like every other update.
- `tests/smoke.sh` verifies every pin in `requirements-tools.txt` is exactly
  what's installed, so a tool PR can't silently resolve to another version.
- Every label Dependabot applies must exist in [`labels.yml`](labels.yml). The file
  lists only labels that something uses (Dependabot's four, the two issue-form
  labels, the ones [`pr-labels.yml`](workflows/pr-labels.yml) adds, and `breaking change`);
  GitHub's built-in labels stay as they are, because the sync never deletes.
- Only Debian/apt packages (gh, PostgreSQL client, …) and the Starship binary
  are outside Dependabot — no ecosystem exists for them. The weekly rebuild
  check keeps them current: it rebuilds when apt has upgrades or Starship has a
  newer release.
- The versions Dependabot cannot read at all — the PostgreSQL major
  (`PG_MAJOR`), the Debian release in the python image tag and the Python
  minor — are compared with the newest stable releases every Monday by
  [`workflows/dependency-drift.yml`](workflows/dependency-drift.yml), which keeps
  one issue (label `dependencies`) up to date and closes it when nothing is
  behind.

---

## 5. Local checks before a PR

```bash
# Optional: CI builds and smoke-tests the image on every PR (about 15–25 minutes cold)
docker build -f docker/Dockerfile.dev -t django-devcontainer:test .
docker run --rm -v "$PWD/tests:/tests:ro" django-devcontainer:test bash /tests/smoke.sh

# Static checks, the same as the Lint job
docker run --rm -i hadolint/hadolint hadolint --config .hadolint.yaml - < docker/Dockerfile.dev
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable scripts/*.sh tests/*.sh .github/scripts/*.sh
bash .github/scripts/check-readme-sync.sh
bash .github/scripts/test-reserve-tag.sh
bash .github/scripts/test-check-rebuild.sh
bash .github/scripts/test-release-notes.sh
python3 -m py_compile .github/scripts/check_drift.py
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
| `CODE_OF_CONDUCT.md` | Contributor Covenant 2.1 — how to behave and where to report conduct issues |
| `actionlint.yaml` | actionlint config (Ubuntu 26.04 runner labels) |
| `dependabot.yml` | Dependency update automation |
| `labels.yml` | Repository labels as code |
| `pull_request_template.md` | PR checklist |
| `ISSUE_TEMPLATE/` | Bug + feature issue forms; blank issues disabled |
| `rulesets/` | `protect-main`, `protect-develop` and `protect-tags` as importable ruleset JSON (§2) |
| `scripts/check-readme-sync.sh` | README ↔ implementation check run by `Lint` |
| `scripts/reserve-tag.sh` | Picks the next free `python-X.Y.Z.R` and creates its git tag (§3) |
| `scripts/test-reserve-tag.sh` | Tests `reserve-tag.sh` with stubbed `curl` and `gh`, run by `Lint` |
| `scripts/test-release-notes.sh` | Tests the title handling of `release-notes.sh` (section mapping, scopes, breaking changes, titles read from merge commits), run by `Lint` |
| `scripts/check-rebuild.sh` | Weekly: does the published `latest` have apt upgrades or an older Starship? |
| `scripts/test-check-rebuild.sh` | Tests `check-rebuild.sh` with stubbed `docker` and `curl`, run by `Lint` |
| `scripts/check_drift.py` | Compares `PG_MAJOR`, the Debian release and the Python minor (vs Django's supported Pythons on PyPI) with upstream |
| `scripts/release-notes.sh` | Release notes: commits since the previous release, grouped by type |
| `vex.openvex.json` | OpenVEX statements read by the Trivy scan (§3) |
| `trivy-ignore.rego` | Trivy ignore policy: packages that cannot affect a container (§3) |
| `workflows/docker.yml` | Test, reserve the image tag, publish, scan, and release |
| `workflows/release.yml` | Reusable: GitHub Release named after the image tag (called by `docker.yml`) |
| `workflows/dependency-drift.yml` | Weekly drift issue for what Dependabot cannot see |
| `../docs/github-setup.md` | Setup and recovery guide: GitHub settings, Docker Hub, rulesets, secrets |
| `../docs/design-decisions.md` | Why the repository works the way it does: each decision, its reason, the alternative and where it lives |
| `../repomix.config.json` | Config of a tool that packs the repository into one file for sharing; its output file is git-ignored |
| `../.gitignore` | Local-only files: editor settings, `.env*`, the packed-repository output, Python bytecode |
| `workflows/lint.yml` | hadolint · ShellCheck · actionlint · tag tests · format · README sync · cspell · markdownlint |
| `workflows/branch-policy.yml` | `PR source` — only `develop` may open PRs into `main` |
| `workflows/dockerhub-description.yml` | README → Docker Hub |
| `workflows/labels.yml` | `labels.yml` → GitHub labels |
| `workflows/pr-labels.yml` | Labels a PR from its title |
