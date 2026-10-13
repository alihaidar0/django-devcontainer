# Security Policy

## Reporting a vulnerability

Report security issues **privately** using GitHub's
[Report a vulnerability](https://github.com/alihaidar0/django-devcontainer/security/advisories/new)
form (repository **Security → Advisories → Report a vulnerability**).

Please do **not** open a public issue or PR for anything security-sensitive.
We aim to acknowledge a report within 3 business days and to agree a
disclosure timeline with you.

## Supported versions

Only the most recent image is supported. Fixes ship as a new image (the next
`python-X.Y.Z.R` revision, or a new Python version) that `:latest` and the
moving `:python-X.Y` tag then point to; there are no maintained release branches.

| Image tag / branch | Supported |
| --- | --- |
| `:latest` and the newest `:python-X.Y` (built from `main`, rebuilt weekly when something changed) | ✅ |
| older `:python-X.Y.Z.R` revisions | ❌ — pull `:latest` |

## Scope notes

- This is a **development** image: it runs as the non-root user `dev` but
  grants it passwordless `sudo`, and it ships compilers, headers, and CLI
  tools. That by itself is not a vulnerability — never use it as a
  production base image.
- CVEs in the Debian base, the Python base image, or pinned tools are tracked
  automatically by Dependabot, the weekly rebuild, and the Trivy scan in `workflows/docker.yml`
  (results in **Security → Code scanning**). You don't need to file those unless
  you have a working exploit path specific to this image.
- Never attach `.env` contents, Docker Hub tokens, or other credentials to a report.
