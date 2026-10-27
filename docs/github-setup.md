# Setup and recovery guide

Everything that can live in the repository (workflows, templates, labels, rulesets as JSON) is versioned under `.github/` and comes back with a `git push`. This guide covers the rest: the settings that exist only on GitHub and on Docker Hub. Follow it from top to bottom to recreate the whole setup on a new repository, or to check that an existing one still matches. Menu names change occasionally; the setting names below are what to look for.

- [What lives where](#what-lives-where)
- [Branch model and merge rules](#branch-model-and-merge-rules)
- [1. Create the repository and push the branches](#1-create-the-repository-and-push-the-branches)
- [2. Docker Hub](#2-docker-hub)
- [3. Settings → General, and the pages around it](#3-settings--general-and-the-pages-around-it)
- [4. Settings → Actions → General](#4-settings--actions--general)
- [5. Environments and secrets](#5-environments-and-secrets)
- [6. Settings → Advanced Security (Code security)](#6-settings--advanced-security-code-security)
- [7. Labels](#7-labels)
- [8. Rulesets](#8-rulesets)
- [9. Bootstrap order](#9-bootstrap-order)
- [10. Verify the setup](#10-verify-the-setup)
- [11. Everyday workflow](#11-everyday-workflow)
- [12. Maintenance and recovery](#12-maintenance-and-recovery)
- [13. After the first publish](#13-after-the-first-publish)
- [Settings checklist](#settings-checklist)

## What lives where

| Where | What | How it comes back |
| --- | --- | --- |
| The repository (`git`) | Dockerfile, scripts, tests, workflows, rulesets as JSON, labels, templates, README, docs | `git push` of `develop` and `main` |
| GitHub settings | Default branch, merge rules, Actions policy, secrets, security features, imported rulesets | Sections 3 to 6 and 8 |
| Docker Hub | The image repository, its description and categories, the access token, the published images | Section 2 (images come back with the first publish) |

Names used everywhere (the Docker Hub name is hardcoded in `docker.yml` and in several docs, so change them together if they ever change):

| Item | Value |
| --- | --- |
| GitHub owner and repository | `alihaidar0/django-devcontainer` (public) |
| Docker Hub repository | `alihaidar199527/django-devcontainer` (public) |
| Default branch and integration branch | `develop` |
| Publish branch | `main` |
| Consuming template | `alihaidar0/django-template` |
| Licence | MIT |

## Branch model and merge rules

```text
 feat/*  fix/*  docs/*  ci/*  chore/*      Dependabot PRs
        │                                       │
        └────── PR, merge commit ───────┬───────┘
                                        ▼
   develop   ← default and integration branch, protected, tested on every push
      │  pull request, merge commit, source must be `develop`
      ▼
    main     ← publish branch, protected
      │  push (only when an image file changed)
      ▼
  docker.yml: reserve the tag → publish → scan → release
```

The rules, in one place:

1. **No direct push to `main`.** `main` accepts pull requests from `develop` only, merged with a **merge commit** (a squash or rebase would give `main` commits that `develop` lacks, and the next release would conflict). Every pull request in this repository, on either branch, is merged with a merge commit: never squash, never rebase.
2. **No direct push to `develop` either.** `develop` accepts pull requests from any topic branch and from Dependabot, merged with a merge commit once `Lint` and `Image tests` are green and the branch is up to date with `develop` (the merge commit is named after the PR title, so the title must be a Conventional Commit; `Lint` checks it). Each merge is a push to `develop` that runs `Lint` and `Image tests` again; the `develop` → `main` pull request reuses those results, because status checks attach to the commit.
3. **You release by merging `develop` into `main` by hand, after your monthly review of the Dependabot pull requests.** An image is published only when that merge changes an image file (`docker/**`, `scripts/**`, `tests/**`, `.dockerignore`, `docker.yml`), when the weekly check finds something stale, or when you run the Docker workflow by hand on `main`. A new Python version (the `FROM python:` line) is built as a new image `python-X.Y.Z.1`; a tools-only or system-package update is the next revision of the same Python and moves `latest` and `python-X.Y` to it, while the old revision stays available.
4. **The weekly run builds only when something changed.** Monday 05:00 UTC it simulates `apt-get upgrade` inside the published `latest` and compares the installed Starship with the newest release. Scheduled workflows run from the default branch (`develop`), which never publishes, so when the check finds something it dispatches the Docker workflow on `main`, and that run is an ordinary manual publish. Nothing new: nothing is dispatched and the run finishes green.

Pull requests into `main` from any branch other than `develop` fail the required **PR source** check: GitHub rulesets cannot restrict a pull request's source branch, so `branch-policy.yml` enforces it.

## 1. Create the repository and push the branches

1. Create the repository `alihaidar0/django-devcontainer` as **Public**, empty (no README, licence or `.gitignore`).
2. Push both branches from a clone. The rulesets do not exist yet, so direct pushes still work. The default branch is `develop`, so set it last (section 3), after both branches exist:

   ```bash
   git remote add origin git@github.com-freelance:alihaidar0/django-devcontainer.git
   git push -u origin main
   git push -u origin develop
   ```

3. On the repository page, click the gear next to **About** and set:

   | Field | Value |
   | --- | --- |
   | Description | `Shared Django dev image: Python 3.14, uv, pre-commit, Postgres 18 client, gettext. Pull, don't build` |
   | Website | `https://github.com/alihaidar0/django-template` |
   | Topics | `dev-container` `devcontainer` `developer-tools` `django` `docker` `docker-image` `gettext` `multi-arch` `postgresql` `pre-commit` `python` `starship` `uv` `vscode-devcontainer` |

   The description is not only cosmetic: the Docker Hub short description is copied from it, and Docker Hub allows 100 bytes. Keep it accurate and under that limit.

## 2. Docker Hub

The image repository is created and configured by hand; the workflows only push to it and sync its README.

1. **Start clean (only when a repository with old images already exists).** Docker Hub → **Repositories** → `django-devcontainer` → **Settings** → **Delete repository** → type the repository name → confirm. This removes every tag, the description and the categories, and every project pulling `latest` breaks until the first publish finishes, so do it right before the release. To keep the description and categories, open the **Tags** tab instead, select all tags and delete them. Also delete the old access token (Account settings → **Personal access tokens**) and create a new one in step 4.
2. **Create the repository.** Docker Hub → **Repositories** → **Create repository**: namespace `alihaidar199527`, name `django-devcontainer`, visibility **Public**. Create it before the first publish; the README sync only runs once it exists.
3. **Short description:** the same text as the GitHub description (100 bytes at most; the sync workflow overwrites it from there).
4. **Categories:** `Developer tools` and `Languages & frameworks`.
5. **Access token.** Docker Hub → Account settings → **Personal access tokens** → **Generate new token**, permission **Read, Write & Delete** (the description sync needs Delete). Copy it once; it goes into the repository secrets in section 5. Note the expiry date and renew the token before then.
6. **Never enable tag retention or inactive-image clean-up** for this repository. Old `python-X.Y.Z.R` tags are restore points and must not expire outside the pipeline. Never delete or move a `python-X.Y.Z.R` tag by hand either.
7. **The README is synced by the pipeline.** The **Docker Hub description** workflow copies `README.md` and the GitHub description to the repository on every README change merged to `main`. After creating a new repository, run it once by hand (Actions → **Docker Hub description** → **Run workflow**, branch `main`).

What the pipeline writes to the repository (all expected):

| Tag | What it is |
| --- | --- |
| `latest` | The newest image (moving) |
| `python-X.Y` | The newest image of that Python line (moving), for example `python-3.14` |
| `python-X.Y.Z.R` | Permanent name of one image: Python `X.Y.Z`, image revision `R`, for example `python-3.14.8.1` |

The builder also attaches SBOM and signed provenance attestations to every image. `django-template` looks the tags up through the Docker Hub API (its `scripts/pin-image.sh`), so both `python-3.14` and the exact `python-X.Y.Z.R` must exist after the first publish.

Deleting the **GitHub** repository does not touch Docker Hub. Deleting the **Docker Hub** repository removes the images, tags, description and categories, and every project pinned to one of its tags stops working until the next publish (see [Maintenance and recovery](#12-maintenance-and-recovery)).

## 3. Settings → General, and the pages around it

Open the repository on GitHub and click **Settings**. The left menu lists every page below.

### 3.1 General

| Setting | Value |
| --- | --- |
| Repository name | `django-devcontainer` |
| Visibility | **Public** (Danger Zone: leave it; never archive, transfer or delete the repository) |
| Template repository | Off |
| Default branch | **`develop`**: Default branch → the switch icon (⇄) → choose `develop` → **Update** → confirm. Do it last, after both branches exist |
| Features | Issues on · Wikis off · Projects off · Discussions off · Sponsorships off |
| Pull Requests → Allow merge commits | **On**. Set **Default commit message** to **Pull request title and description** (the merge commit is named after the PR title) |
| Pull Requests → Allow squash merging | **Off** |
| Pull Requests → Allow rebase merging | **Off** |
| Pull Requests → Always suggest updating pull request branches | Off |
| Pull Requests → Allow auto-merge | Optional: On is convenient for Dependabot pull requests once the checks pass |
| Pull Requests → Automatically delete head branches | **On** |
| Releases → Enable release immutability (if offered) | **On** |
| Social preview | Optional |

The **About** box on the repository home page (gear icon) holds the description, website and topics from section 1.

**Release immutability** locks a published release and its tag, and it reserves the tag name for good: even if the release and the tag are deleted, GitHub never lets that name be used again (creating it fails with "tag_name was used by an immutable release"). The pipeline copes with this by reserving each image's git tag before publishing and skipping names that GitHub refuses (see [A burned tag number](#12-maintenance-and-recovery)), so keep it on.

### 3.2 The other pages to confirm

| Page (Settings →) | Expected |
| --- | --- |
| Collaborators and teams | Only the owner (add a second maintainer later, and then raise the ruleset approvals) |
| Branches | **No** classic branch protection rules: the rulesets in section 8 replace them. Delete any that exist |
| Webhooks | None |
| Deploy keys | None |
| Pages | Disabled: the repository publishes no site |
| Codespaces | Nothing to configure, and no Codespaces secrets |
| Packages (on the repository home page) | Nothing published to GitHub Packages: the image goes to Docker Hub |
| Rules → Rulesets | The three rulesets of section 8 |

### 3.3 What the default branch changes

The default branch is `develop`, the integration branch. New pull requests, Dependabot *security* updates and the **Run workflow** dropdown therefore start from `develop`, which is where all changes belong. Four consequences are handled in the repository:

- **Scheduled workflows run from the default branch**, so the weekly rebuild check and **Dependency drift** run from `develop`. `develop` never publishes, so when the weekly check finds something it dispatches **Docker** on `main` itself.
- **The repository page shows `develop`**, including documentation that is not released yet. The Docker Hub README is synced from `main` and always reflects what is published.
- **Manual runs of Docker must pick `main`** in the **Branch** dropdown, because it defaults to `develop` and the publish jobs only run on `main`. A manual **Docker Hub description** run from any other branch is skipped on purpose.
- **The release pull request needs its base set to `main`**, because a new pull request defaults to `develop`: use the compare link `https://github.com/alihaidar0/django-devcontainer/compare/main...develop`, or `gh pr create --base main --head develop`.

`latest` is tied to `refs/heads/main` in `docker.yml`, not to the default branch, so changing the default branch can never stop or redirect it.

## 4. Settings → Actions → General

### 4.1 Permissions and policy

| Setting | Value |
| --- | --- |
| Actions permissions | **Allow `alihaidar0`, and select non-`alihaidar0`, actions and reusable workflows** |
| Allow actions created by GitHub | On (covers `actions/*` and `github/codeql-action/*`) |
| Allow Marketplace actions by verified creators | Off |
| Allowed actions and reusable workflows (one per line) | `docker/*`, `aquasecurity/trivy-action@*`, `aquasecurity/setup-trivy@*`, `hadolint/hadolint-action@*`, `raven-actions/actionlint@*`, `streetsidesoftware/cspell-action@*`, `DavidAnson/markdownlint-cli2-action@*`, `crazy-max/ghaction-github-labeler@*`, `peter-evans/dockerhub-description@*`, `google-github-actions/auth@*`, `aws-actions/configure-aws-credentials@*`, `azure/login@*`, `chainguard-dev/setup-chainctl@*` |
| Fork pull request workflows from outside collaborators | **Require approval for all outside collaborators** |
| Send write tokens or secrets to fork pull request workflows | Off |
| Workflow permissions | **Read repository contents and packages permissions** |
| Allow GitHub Actions to create and approve pull requests | Off |
| Artifact and log retention | 30 days |

`aquasecurity/setup-trivy` is needed because `trivy-action` calls it internally: GitHub checks every action that an allowed action uses, not only the ones the workflow names, and the first run fails with "The action aquasecurity/setup-trivy@… is not allowed" without it. The last four entries of the allowed list are not used by this repository: Docker's reusable builder mentions them for registry identities (cloud sign-in) that stay switched off here. GitHub's policy can reject a workflow over any action that a called workflow references, so they are allowed to avoid a start-up failure. `azure/login` and `chainguard-dev/setup-chainctl` arrived with builder v1.18.0: until they were allowed, every `Docker` run on the bump PR ended in `startup_failure` and the required `Image tests` check stayed at "Expected — waiting for status to be reported". If a run is refused with "action is not allowed", the message names the action: add it to the list, and pin it to a full commit SHA in the workflow.

Every workflow also declares its own `permissions:` block (default `contents: read`); jobs that need more request it explicitly: the `Reserve image tag` job and the release job (`contents: write`, to create the git tag and the release), the `Start the rebuild on main` job (`actions: write`, to dispatch the build), the dependency-drift and labels jobs (`issues: write`), the scan job (`security-events: write`), and the publish job (`id-token: write` for keyless signing, no secret involved). A job can request more than the repository default; nothing else is granted.

**Optional hardening, after the first green publish:** tick **Require actions to be pinned to a full-length commit SHA**. Every action and the reusable builder in this repository are already pinned. If a later run fails because a third-party workflow refers to an unpinned action, untick it again.

### 4.2 The other Actions pages

| Page (Settings → Actions →) | Expected |
| --- | --- |
| Runners | None to add. GitHub-hosted amd64 and arm64 runners are free for public repositories |
| Caches (also under the repository's Actions tab) | Delete all caches for a cold start after a reset (`gh cache delete --all`) |
| Variables (under Secrets and variables) | None |

Workflows run on explicit runner images (`ubuntu-26.04`, and `ubuntu-26.04-arm` for arm64), never `ubuntu-latest`. Moving to a newer image is a deliberate edit of the `runs-on:` lines and `.github/actionlint.yaml`.

## 5. Environments and secrets

### 5.1 Environments

Settings → **Environments**. The expected state is **no environments**. Delete any that exist, for example a leftover `docker-hub`.

There is no environment on purpose: the publish is a call to a reusable workflow, and a job that calls one cannot declare an environment. The Docker Hub credentials are therefore repository secrets, and they are only handed to the publish job and the description sync, both of which run on `main`.

### 5.2 Secrets and variables

Settings → **Secrets and variables → Actions**, the **Secrets** tab → **New repository secret**, twice:

| Name | Value |
| --- | --- |
| `DOCKERHUB_USERNAME` | `alihaidar199527` |
| `DOCKERHUB_TOKEN` | The access token from section 2 |

Delete any other secret. Leave the **Variables** tab empty, and leave the **Dependabot** and **Codespaces** secret tabs empty: the checks that run on Dependabot pull requests need no secrets. With the GitHub CLI: `gh secret set DOCKERHUB_USERNAME -R alihaidar0/django-devcontainer` and `gh secret set DOCKERHUB_TOKEN -R alihaidar0/django-devcontainer` (each prompts for the value).

## 6. Settings → Advanced Security (Code security)

The page is called **Advanced Security** in the settings menu, and **Code security** in some views. Every row is a toggle or an **Enable** button on that page.

| Feature | Value |
| --- | --- |
| Private vulnerability reporting | **Enable** (`SECURITY.md` links to the reporting form) |
| Dependency graph | Enable |
| Dependabot alerts | Enable |
| Dependabot malware alerts | Enable |
| Dependabot security updates | **Enable**, and **Grouped security updates** too |
| Dependabot version updates | Nothing to click: `.github/dependabot.yml` drives it (weekly, 7-day cooldown, pull requests to `develop`) |
| Code scanning → CodeQL analysis | **Set up → Default**, language **Actions** (it analyses the workflow files), then **Enable CodeQL** |
| Secret Protection → Secret scanning | Enable |
| Secret Protection → Push protection | **Enable** |
| Dependency graph → Automatic dependency submission | Leave **Disabled**: no ecosystem here needs build-time submission |
| Dependabot auto-triage rules | GitHub's preset rule may stay enabled; it only dismisses low-impact alerts for development-only dependencies |
| Code scanning → Protection rules (check-runs failure threshold) | Leave the defaults: no ruleset requires code scanning |

On the page, **Private vulnerability reporting**, **Secret scanning** and **Push protection** show a **Disable** button when they are on, so a red **Disable** button means the feature is enabled.

### 6.1 Reading the Security tab

The tab opens on the default branch, `develop`. The Trivy scan runs after each publish on `main`, so use the branch filter `branch:main` to see its findings, and the tool filter to tell **CodeQL** (workflow files) from **Trivy** (the image).

| Page | Expected | What to do otherwise |
| --- | --- | --- |
| Code scanning, Trivy (`branch:main`) | Only HIGH or CRITICAL findings that have a fix, ideally none | Open the alert and read the package and the fixed version. Rebuild (every build runs `apt-get upgrade`) or bump the pin. If the finding cannot affect a development container, add a `not_affected` statement with a written reason to `.github/vex.openvex.json`. Dismiss an alert in the UI only when it is a false positive, with that reason |
| Code scanning, CodeQL | None. It reads the workflow files | Fix the workflow (usually a missing `permissions:` block or an unsafe `${{ }}` in a `run:` script) in a pull request |
| Dependabot | No alerts. Dependabot pull requests are listed under Pull requests, not here | Merge the pull request that Dependabot opened for the alert, after `Image tests` is green |
| Secret scanning | No alerts | Revoke the exposed credential first, then clean up. Push protection should have blocked the push in the first place |
| Security policy and Advisories | `SECURITY.md` is shown; no advisories | Reports arrive privately through the reporting form |

After the first publish, the Trivy list is also what decides which statements in `.github/vex.openvex.json` are still needed (section 13).

**Dependabot security updates are on** because GitHub opens those pull requests against the default branch, which is `develop`: they are tested by `Image tests` and reach `main` with the next release like every other change. The Trivy scan after each publish uploads its findings to the same **Security → Code scanning** tab.

## 7. Labels

Labels are defined in `.github/labels.yml`. The **Labels** workflow syncs them to GitHub when that file changes on `develop` (labels belong to the repository, so they come from the default branch); on a new repository run it once by hand (Actions → **Labels** → **Run workflow**, branch `develop`). Dependabot applies `dependencies`, `github-actions`, `docker` and `python` itself, so every one of those must exist in the file.

The **PR labels** workflow adds labels to every pull request from its Conventional Commit title, so nobody has to set them: `feat` → `enhancement`, `fix` → `bug`, `docs` → `documentation`, `ci` → `ci`, `build` / `chore` / `refactor` / `style` / `test` / `perf` → `chore`, scope `deps` → `dependencies`, scope `docker` → `docker`, a `!` or a `BREAKING CHANGE:` line → `breaking change`, and a pull request from `develop` into `main` → `release`. It only adds labels (hand-set ones stay), skips Dependabot pull requests (Dependabot labels its own) and skips forks. A label that does not exist yet is reported as a warning and skipped, which is why the sync has to run first on a new repository. It is not a required check.

## 8. Rulesets

Settings → **Rules → Rulesets**. If rulesets of the same names already exist, open each one → the `⋯` menu → **Delete ruleset**. Then **New ruleset → Import a ruleset**, choose the file, review the page it shows, and click **Create**, once per file:

| File | Targets | What it enforces |
| --- | --- | --- |
| `.github/rulesets/protect-main.json` | `main` | No creation, no deletion, no force-push, pull request required (merge commits only, conversations resolved), required checks **PR source**, **Lint** and **Image tests** |
| `.github/rulesets/protect-develop.json` | `develop` | No deletion, no force-push, pull request required (merge commits only, conversations resolved), required checks **Lint** and **Image tests**, branch must be up to date |
| `.github/rulesets/protect-tags.json` | `python-*` tags | A released tag can be neither moved nor deleted (creating tags stays allowed, because `Reserve image tag` creates one per image) |

Notes:

- **The bypass list is empty** on purpose, so the rules apply to administrators too.
- **"Restrict updates" is off in `protect-main`.** With an empty bypass list it would block every merge into `main`, because a merge is an update.
- **Required approvals are 0.** A pull request author cannot approve their own pull request, so requiring 1 would block a solo maintainer. Once a second maintainer joins, set `required_approving_review_count` to `1` and `require_code_owner_review` to `true` (`CODEOWNERS` is ready), then re-import.
- **The required checks are pinned to the GitHub Actions app** (`integration_id: 15368`), so no other app or commit status can satisfy them.
- **`Image tests`, not the per-architecture jobs, is required**, because a matrix job skipped by `if` reports an unexpanded name that would wait forever.
- Import the rulesets *after* the workflows exist on `main`, otherwise nothing can report the required checks.
- Each ruleset must show **Active** with an empty bypass list. The **Insights** tab of the Rules page lists every push and merge the rules blocked or allowed.
- If a ruleset changes in the UI, change the JSON file too (the file is only the importable reference copy).

## 9. Bootstrap order

On a brand-new repository, in this order:

1. Create the repository and push `main` and `develop` (section 1), and set the About fields.
2. Create the Docker Hub repository, its categories and the access token (section 2).
3. Confirm there are no environments, and add the two repository secrets (section 5).
4. Apply the settings in sections 3, 4, 5.1 and 6. Set the default branch to `develop` last, after both branches exist.
5. Run the **Labels** workflow once by hand on `develop` (section 7).
6. Publish the first image. The rulesets are not active yet: push an image change to `develop`, wait for `Image tests` to go green, then open the pull request `develop` → `main` and merge it with a merge commit. Wait for **Docker** to finish and for the first tag and release `python-X.Y.Z.1` to appear. Alternatively run **Docker** by hand (Actions → **Docker** → **Run workflow**, branch `main`).
7. Run **Docker Hub description** once by hand on `main`, so the Docker Hub overview shows the README.
8. Import the three rulesets (section 8).
9. Verify (next section), then point `django-template` at the new tags.

## 10. Verify the setup

Do all three parts after the first release. Part A checks the settings, part B checks that the rules really block what they should, and part C checks the pipeline and its results.

### 10.A Audit the settings

In the web interface, open each page of sections 3 to 6 and compare it with the table there. To read the same settings from a terminal, install the GitHub CLI and sign in as the owner (`gh auth login`); the commands below only read.

```bash
R=alihaidar0/django-devcontainer

# General: default branch, merge methods, features
gh api repos/$R --jq '{default_branch, visibility, is_template, issues: .has_issues, wiki: .has_wiki, projects: .has_projects, discussions: .has_discussions, merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge, delete_branch_on_merge, auto_merge: .allow_auto_merge, merge_title: .merge_commit_title, merge_message: .merge_commit_message}'

# Rulesets: three, all active
gh api repos/$R/rulesets --jq '.[] | "\(.name)  \(.target)  \(.enforcement)"'

# Actions: policy, allowed list, workflow token
gh api repos/$R/actions/permissions
gh api repos/$R/actions/permissions/selected-actions
gh api repos/$R/actions/permissions/workflow

# Environments (none) and secrets (the two Docker Hub names)
gh api repos/$R/environments --jq '.total_count'
gh secret list -R $R

# Advanced Security
gh api repos/$R --jq '.security_and_analysis'
gh api repos/$R/vulnerability-alerts -i | head -1
gh api repos/$R/automated-security-fixes
gh api repos/$R/private-vulnerability-reporting
gh api repos/$R/code-scanning/default-setup
```

| Command | Expected |
| --- | --- |
| General | `default_branch` is `develop`, `visibility` is `public`, `merge` is `true`, `squash` and `rebase` are `false`, `delete_branch_on_merge` is `true`, `merge_title` is `PR_TITLE` and `merge_message` is `PR_BODY` |
| Rulesets | `protect-main`, `protect-develop` and `protect-tags`, all `active` |
| Actions permissions | `enabled` is `true` and `allowed_actions` is `selected`; the selected list matches section 4.1 |
| Workflow token | `default_workflow_permissions` is `read` and `can_approve_pull_request_reviews` is `false` |
| Environments | `0` |
| Secrets | `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` only |
| Advanced Security | secret scanning and push protection `enabled`; the vulnerability-alerts call answers `HTTP/2 204`; automated security fixes `enabled`; private vulnerability reporting `enabled`; the CodeQL default setup state is `configured` with the language `actions` |

### 10.B Check that the rules block what they should

Run these from a clone of the repository. Each push must be rejected **by the rule** (the message starts with `remote: error: GH013: Repository rule violations found`). A plain `non-fast-forward` message is a normal git refusal, not the ruleset, and proves nothing: that is why each test commit is made on top of the branch it is pushed to.

```bash
git config user.name && git config user.email && git remote get-url origin
git fetch origin

# develop: a fast-forward push must still be refused
git switch -C test/rules-develop --no-track origin/develop
git commit --allow-empty -m "chore: ruleset test"
git push origin HEAD:develop     # rejected: changes must be made through a pull request

# main: main also holds the release merge commits, so base the test on main itself
git switch -C test/rules-main --no-track origin/main
git commit --allow-empty -m "chore: ruleset test"
git push origin HEAD:main        # rejected: changes must be made through a pull request

# clean up
git switch develop
git branch -D test/rules-develop test/rules-main
```

If a push is accepted, the ruleset is not active: delete the empty commit through a pull request, and fix the ruleset (section 8) before anything else.

Then, in the web interface:

- A pull request from a topic branch into `develop` needs `Lint` and `Image tests`, offers only **Create a merge commit**, needs the branch up to date with `develop`, and `Lint` fails it when the title is not a Conventional Commit.
- A pull request from a topic branch into `main` fails **PR source**, so it cannot merge. Close it without merging.
- A pull request from `develop` into `main` offers only **Create a merge commit**.

### 10.C Check the pipeline and its results

- A push to `develop` (a merged pull request) that changes an image file runs **Test (amd64)** and **Test (arm64)**, then **Image tests**; a push to `main` runs the tests again before it publishes.
- After the publish from `main`, all of these exist, with the same digest for the first three:

  ```bash
  docker buildx imagetools inspect alihaidar199527/django-devcontainer:latest
  docker buildx imagetools inspect alihaidar199527/django-devcontainer:python-3.14
  docker buildx imagetools inspect alihaidar199527/django-devcontainer:python-3.14.8.1
  curl -s https://hub.docker.com/v2/repositories/alihaidar199527/django-devcontainer/tags/python-3.14 | jq -r .name
  ```

- The git tag `python-3.14.8.1` and a GitHub Release of the same name exist, and the release lists the pull request titles. The run summary prints the exact `cosign verify` commands for the signed provenance.
- The published image works:

  ```bash
  docker run --rm alihaidar199527/django-devcontainer:python-3.14 bash -lc 'python --version; uv --version; msgfmt --version | head -1; psql --version; starship --version | head -1; python -m pip --version || echo "no pip (expected)"'
  ```

- The Docker Hub page shows the new README, and the repository has the description from the About box.
- The Security → Code scanning tab shows only HIGH and CRITICAL findings that have a fix (filter `branch:main`: the scan runs on the publish branch).
- A Dependabot pull request (version or security) targets `develop`, and **Run workflow** lists `develop` as the default branch.

## 11. Everyday workflow

```bash
# 0. confirm the identity the commit will use
git config user.name && git config user.email && git remote get-url origin

# 1. start from an up-to-date develop (this also picks up merged Dependabot pull requests)
git switch develop
git pull --ff-only

# 2. create a topic branch (feat/ fix/ docs/ ci/ chore/)
git switch -c fix/example-topic

# 3. commit and push the branch; open a pull request into develop
git add -A
git status
git commit -m "fix(docker): describe the change"
git push -u origin fix/example-topic
gh pr create --base develop --title "fix(docker): describe the change" --fill
```

Without the GitHub CLI, open the pull request in the browser instead: after the push, GitHub shows a **Compare & pull request** banner on the repository page, or go to `https://github.com/alihaidar0/django-devcontainer/compare/develop...fix/example-topic`; check that the **base** is `develop`, paste the title, and click **Create pull request**.

Wait for `Lint` and `Image tests`, then **Create a merge commit** (if GitHub says the branch is out of date, click **Update branch** and wait for the checks again). The PR title is the release note, so it must be a Conventional Commit.

Release: open a pull request `develop` → `main` and merge it with a merge commit. In the browser, go to `https://github.com/alihaidar0/django-devcontainer/compare/main...develop` (the base must be `main`; it defaults to `develop`), or run `gh pr create --base main --head develop --title "<title>" --fill`. If an image file changed, that push publishes `python-X.Y.Z.R`, moves `python-X.Y` and `latest`, scans the image and creates the GitHub Release. A promotion that changes no image file produces no image and no release. The release notes are the titles of the PRs merged since the previous release.

**Monthly review.** Dependabot opens pull requests into `develop` as it finds updates (every Monday, after a 7-day cooldown), covering every version of the Actions, the python and uv images, and the tool pins. Once a month, go through them: let `Lint` and `Image tests` run, merge the good ones (merge commit; Dependabot rebases the others after each merge, so give them a minute and a green check), then open the release pull request `develop` → `main` yourself.

**Monday routine** (all UTC, nothing to do unless something opens):

- **05:00, Docker:** the weekly rebuild check. It builds only when apt has upgrades or Starship has a newer release, and the job summary lists the reasons. A quiet week ends green with everything else skipped.
- **06:00, Dependency drift:** keeps one issue up to date for what Dependabot cannot see (the PostgreSQL major, the Debian release, and the Python minor measured against what Django supports), and closes it when everything is current.
- **09:00, Dependabot:** pull requests into `develop` for the Actions, the python and uv images, and the tool pins.

## 12. Maintenance and recovery

**Publishing by hand.** Actions → **Docker** → **Run workflow**, branch **`main`** (the dropdown defaults to `develop`, which does not publish). `push` = off is a dry run that builds and smoke-tests both architectures without publishing. `no_cache` forces a full rebuild. A manual publish takes the next free revision of the current Python.

**Rolling back `latest`.** No rebuild is needed: point the moving tags at a known-good permanent tag. The digest, signature and attestations are unchanged.

```bash
docker login -u alihaidar199527
docker buildx imagetools create \
  -t alihaidar199527/django-devcontainer:latest \
  -t alihaidar199527/django-devcontainer:python-3.14 \
  alihaidar199527/django-devcontainer:python-3.14.8.1
```

The next publish moves them forward again, so fix the cause on `develop` and release it.

**A burned tag number.** `Reserve image tag` creates the git tag before anything is pushed, so a run that fails afterwards leaves a tag with no image. That only costs one revision number: the next run takes the first number that is free on Docker Hub **and** creatable on GitHub, so revisions always increase but can skip. Do not delete the leftover tag (the `protect-tags` ruleset forbids it, and with release immutability on, GitHub would never free the name anyway).

**A failed publish.** Open the run and re-run the failed jobs. If `Reserve image tag` failed with `Resource not accessible by integration`, check Settings → Actions → General → Workflow permissions and that `protect-tags` does not restrict creating `python-*` tags. If it failed with an unexpected Docker Hub answer, Docker Hub was unreachable: re-run. `No free revision` means 99 revisions of one Python are taken: raise `MAX_REVISION` in `.github/scripts/reserve-tag.sh`.

**A release job that says the release already exists.** A release is created once per tag and never replaced, so re-running the release job for a tag that already has one only prints that notice. It is harmless.

**The schedule paused.** GitHub pauses scheduled workflows after 60 days without repository activity, and that stops both the weekly rebuild and the dependency-drift check. Re-enable them: Actions → **Docker** → **Enable workflow**, and the same for **Dependency drift**. Any push to the repository re-arms the clock.

**A weekly run that skips.** That is normal: the job summary of **Rebuild needed?** says nothing changed. To force a build, run **Docker** by hand on `main`.

**Expired Docker Hub token.** Publishing fails with `denied: requested access to the resource is denied`. Create a new token (section 2), update `DOCKERHUB_TOKEN` and re-run the failed jobs.

**Starting over on Docker Hub (wipe every image).** Only if you accept that every project pinned to an existing tag breaks until the next publish:

1. In Docker Hub, delete the repository and create it again as in section 2, or delete only the tags to keep the description and categories.
2. Run the publish: merge an image change `develop` → `main`, or run **Docker** by hand on `main`. The first image is built cold.
3. Run **Docker Hub description** once to refresh the overview.

You do not need to delete the GitHub releases or git tags, and deleting them would not help: the first new image takes the first revision that is free on both sides, so the numbering simply continues.

**Recreating the whole repository.** Follow sections 1 to 10 in order. The pipeline, the rulesets, the labels and the documentation all come from the pushed branches; the Docker Hub repository and token, the secrets and the settings tables above are the parts you do by hand. Published images survive on Docker Hub as long as that repository exists.

## 13. After the first publish

Some things can only be confirmed by a real run. Go through them once, after the first image is published and the first Monday has passed.

1. **The vulnerability gate passed.** In the first `Image tests` run, `Test (amd64)` ends with `Vulnerability gate (CRITICAL with a fix)`. If it failed, the log names the package: rebuild (`apt-get upgrade` normally fixes it) or, only when the finding cannot affect a development container, add a `not_affected` statement with a written reason to `.github/vex.openvex.json`.
2. **The VEX file is pruned.** The image has no pip, so the statements about pip's bundled msgpack and setuptools 70.3.0 were removed after checking that neither package exists in the published image. One statement remains: virtualenv's embedded setuptools 82.0.1 seed wheel, which is still present under `virtualenv/seed/wheels/embed`. Re-check it whenever `pre-commit` is bumped: if `find /opt/uv-tools -name 'setuptools-82*'` finds nothing, drop the statement. A statement is only ever removed after confirming the package is gone from the image, because a statement that works also hides its finding, so an empty alert list proves nothing.

   **Known open findings.** Four HIGH alerts on `usr/bin/gh` (Go standard library and `golang.org/x/net`: HTTP/2 SETTINGS frames, HTTP Range headers, crypto/tls ECH). They come from the Go version the GitHub CLI release was built with, and `gh` 2.102.0 is the newest release, so there is nothing to update yet. They close by themselves when a newer `gh` is built with a fixed Go: the weekly rebuild check notices the new apt package, rebuilds on `main`, and the next scan closes them. Do not add a VEX statement for them: they are real findings, only not fixable here.
3. **Dependabot respects the Python rule.** After the first Monday, the Dependabot pull requests must contain no Python 3.15 (or newer minor) update, only patch updates. If a 3.15 pull request appears, the `ignore` rule in `.github/dependabot.yml` did not match: close it with the comment `@dependabot ignore this minor version` and tell whoever maintains the repository.
4. **The weekly run behaves.** The Docker run of the first Monday (05:00 UTC, on `develop`) shows `Rebuild needed?` with a summary. If it found something, a `Start the rebuild on main` job appears and a new Docker run on `main` starts with the event `workflow_dispatch`.
5. **The drift issue is quiet.** **Dependency drift** (06:00 UTC) should not open an issue while Python, PostgreSQL and Debian are current. It reports Python 3.15 as informational only.
6. **The first release reads well.** The release `python-X.Y.Z.1` lists the pull request titles since the previous release, grouped by type, without the `develop` → `main` merge itself.
7. **Pinning is enforced.** Settings → Actions → General → **Require actions to be pinned to a full-length commit SHA** (section 4) is ticked. If a later run fails because a called workflow uses an unpinned action, the message names it: untick the box until that workflow is updated.
8. **Sibling repository and notes.** `django-template` documents the tags `latest`, `python-3.14` and `python-X.Y.Z.R`, adds `flower` to its dependency list for its Flower command, and states the Django 6.x minimum (it uses Django 6's CSP middleware). Project notes that describe this image are updated to match.

## Settings checklist

A one-page list to tick off after a recovery. Each line points to the section with the exact values.

| Done | Where | Setting | Section |
| --- | --- | --- | --- |
| ☐ | GitHub | Repository public, `main` and `develop` pushed | 1 |
| ☐ | GitHub | About: description (100 bytes at most), website, topics | 1 |
| ☐ | Docker Hub | Repository public, categories, no tag retention | 2 |
| ☐ | Docker Hub | Access token (Read, Write & Delete) | 2 |
| ☐ | GitHub | General: default branch `develop`; merge commits only (squash and rebase off); auto-delete head branches; release immutability | 3.1 |
| ☐ | GitHub | Collaborators, classic branch rules, webhooks, deploy keys, Pages, Codespaces: empty or off | 3.2 |
| ☐ | GitHub | Actions: selected-actions policy and allow-list, fork approvals, read-only workflow token, no PR approval, 30-day retention | 4.1 |
| ☐ | GitHub | Actions: caches cleared after a reset, no variables | 4.2 |
| ☐ | GitHub | Environments: none | 5.1 |
| ☐ | GitHub | Secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` only | 5.2 |
| ☐ | GitHub | Advanced Security: private vulnerability reporting, dependency graph, Dependabot alerts, malware alerts and security updates, CodeQL (Actions), secret scanning, push protection | 6 |
| ☐ | GitHub | Labels workflow run once on `develop` | 7 |
| ☐ | GitHub | First image published, Docker Hub description run once | 9 |
| ☐ | GitHub | Rulesets imported: `protect-main`, `protect-develop`, `protect-tags` | 8 |
| ☐ | GitHub | Protection and tags verified | 10 |
| ☐ | GitHub | Gate, VEX file, Dependabot rule, weekly run, drift issue and first release checked | 13 |
