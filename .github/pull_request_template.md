<!-- markdownlint-disable-file MD041 — the PR title is the page heading -->
<!-- Branch flow: feature/* → main. PR title follows Conventional Commits (feat:, fix:, build:, ci:, docs:, chore:, …). -->

## What & why

<!-- What does this change do, and what problem does it solve? Link issues with "Closes #123". -->

## How to verify

<!-- Commands run, smoke-test output, or tool versions printed from the built image. -->

```bash
docker build -f docker/Dockerfile.dev -t django-devcontainer:test .
docker run --rm -v "$PWD/tests:/tests:ro" django-devcontainer:test bash /tests/smoke.sh
```

## Checklist

- [ ] The change improves the dev environment for **all** projects (otherwise it belongs in `django-template`)
- [ ] No Django files, `pyproject.toml`, `uv.lock`, or Node.js added
- [ ] `Lint` and `Image tests` are green
- [ ] `tests/smoke.sh` covers any tool or behaviour added or changed
- [ ] `README.md` updated if tools, versions, aliases, tags, or the runtime contract changed (it is also the Docker Hub page)
- [ ] Runtime-contract change (user, paths, `PATH`, removed tool)? → marked breaking and matching `django-template` change ready
- [ ] No secrets or tokens committed
