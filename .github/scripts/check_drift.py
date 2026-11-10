#!/usr/bin/env python3
"""Report pinned versions that are behind upstream.

Run by .github/workflows/dependency-drift.yml. Stdlib only.

Dependabot already tracks the literal FROM lines (the python and uv images), the
pip pins in docker/requirements-tools.txt and the GitHub Actions. What it cannot
see, and this script compares with the official release data on endoflife.date
(and, for the tools below, with their newest releases):

  PG_MAJOR          the PostgreSQL client major vs the newest released PostgreSQL
  Debian codename   the Debian in the python image tag vs the newest stable Debian
  Python minor      the Python line in the FROM line vs the newest Python that
                    Django officially supports (the version classifiers Django
                    publishes on PyPI), NOT the newest Python released: the image
                    follows Django, so Python 3.15 is not drift while Django does
                    not list it. Dependabot only proposes Python patch bumps (see
                    its ignore rule), so this row is what announces a new minor.
  actionlint        the version pinned in .github/workflows/lint.yml vs the newest
                    actionlint release (the action would otherwise run the newest
                    one, so Lint could fail on a day nothing in the repository changed)
  zizmor            the version pinned in .github/workflows/lint.yml vs the newest
                    release on PyPI
  Starship          the version pinned in scripts/shell_setup.sh vs the newest
                    release that is at least 7 days old (the cooldown Dependabot
                    applies to everything else); a younger release is only noted
  Dockerfile syntax the frontend pinned in line 1 of docker/Dockerfile.dev
                    (# syntax=docker/dockerfile:X.Y.Z@sha256:...) vs the newest
                    release on Docker Hub

The weekly rebuild check (scripts/check-rebuild.sh) covers the apt packages.

Usage: check_drift.py REPORT_FILE
Writes a Markdown report to REPORT_FILE and "drift=true|false" to $GITHUB_OUTPUT.
Always exits 0 unless a pin cannot be parsed; a source that cannot be reached is
reported as "unknown" and never counts as drift.
GITHUB_TOKEN, when set, is sent to api.github.com (higher rate limit).
"""
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request

DOCKERFILE = "docker/Dockerfile.dev"
LINT_WORKFLOW = ".github/workflows/lint.yml"
SHELL_SETUP = "scripts/shell_setup.sh"
# The `version:` input of the actionlint step (comment lines may sit in between).
ACTIONLINT_PIN = r"uses: raven-actions/actionlint@[^\n]*\n(?:[ \t]+(?:#[^\n]*|with:)\n)*[ \t]+version: (\d+\.\d+\.\d+)"
# `pipx run zizmor==X.Y.Z ...` in the zizmor step of lint.yml.
ZIZMOR_PIN = r"zizmor==(\d+\.\d+\.\d+)"
# `starship_version="X.Y.Z"` in shell_setup.sh.
STARSHIP_PIN = r'^starship_version="(\d+\.\d+\.\d+)"\s*$'
# Line 1 of the Dockerfile: `# syntax=docker/dockerfile:X.Y.Z@sha256:<64 hex>`.
SYNTAX_PIN = r"\A# syntax=docker/dockerfile:(\d+\.\d+\.\d+)@sha256:[0-9a-f]{64}\s*$"
# The same 7-day cooldown that Dependabot applies to everything else.
COOLDOWN_DAYS = 7
TIMEOUT = 30


def fetch_json(url):
    headers = {"User-Agent": "dependency-drift"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def is_behind(current, newest):
    """True when current is older than newest; plain inequality for non-numeric values (Debian codenames)."""
    try:
        return version_tuple(current) < version_tuple(newest)
    except ValueError:
        return current != newest


def newest_github_release(repo):
    """Version of the newest GitHub release of repo (drafts and pre-releases excluded)."""
    tag = fetch_json(f"https://api.github.com/repos/{repo}/releases/latest")["tag_name"]
    return tag[1:] if tag.startswith("v") else tag


def newest_aged_release(repo, min_days):
    """(newest version at least min_days old, newest version overall) among the stable releases of repo."""
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=min_days)
    found = []
    for release in fetch_json(f"https://api.github.com/repos/{repo}/releases?per_page=30"):
        version = release["tag_name"].lstrip("v")
        if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"\d+\.\d+\.\d+", version):
            continue
        published = datetime.datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
        found.append((version_tuple(version), version, published))
    if not found:
        raise ValueError(f"no stable release found for {repo}")
    aged = [release for release in found if release[2] <= cutoff]
    if not aged:
        raise ValueError(f"no release of {repo} is {min_days} days old yet")
    return max(aged)[1], max(found)[1]


def newest_pypi(project):
    """Newest stable version of a PyPI project."""
    return fetch_json(f"https://pypi.org/pypi/{project}/json")["info"]["version"]


def newest_dockerfile_frontend():
    """Newest X.Y.Z tag of the docker/dockerfile image on Docker Hub."""
    tags = fetch_json("https://hub.docker.com/v2/repositories/docker/dockerfile/tags?page_size=100&ordering=last_updated")
    versions = [t["name"] for t in tags["results"] if re.fullmatch(r"\d+\.\d+\.\d+", t["name"])]
    if not versions:
        raise ValueError("no X.Y.Z tag found for docker/dockerfile")
    return max(versions, key=version_tuple)


def newest_released(product):
    """Newest cycle of an endoflife.date product whose release date has passed."""
    today = datetime.date.today().isoformat()
    cycles = fetch_json(f"https://endoflife.date/api/{product}.json")
    released = [c for c in cycles if c.get("releaseDate") and c["releaseDate"] <= today]
    if not released:
        raise ValueError(f"no released cycle for {product}")
    return max(released, key=lambda c: c["releaseDate"])


def django_pythons():
    """(newest Django release, sorted Python minors it declares support for)."""
    info = fetch_json("https://pypi.org/pypi/django/json")["info"]
    minors = sorted(
        tuple(int(part) for part in c.rsplit("::", 1)[1].strip().split("."))
        for c in info["classifiers"]
        if re.fullmatch(r"Programming Language :: Python :: 3\.\d+", c)
    )
    if not minors:
        raise ValueError("Django declares no Python 3.x classifiers")
    return info["version"], minors


def pinned(text):
    pg = re.search(r"^ARG PG_MAJOR=(\d+)\s*$", text, re.M)
    base = re.search(r"^FROM python:(\d+\.\d+)\.\d+-slim-([a-z]+)@", text, re.M)
    if not pg or not base:
        sys.exit(f"Could not read PG_MAJOR and the python FROM line from {DOCKERFILE}")
    return pg.group(1), base.group(1), base.group(2)


def read_pin(path, pattern, what):
    """The first capture group of pattern in the file at path; exits when it is not there."""
    with open(path, encoding="utf-8") as handle:
        match = re.search(pattern, handle.read(), re.M)
    if not match:
        sys.exit(f"Could not read {what} from {path}")
    return match.group(1)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    report_path = sys.argv[1]
    with open(DOCKERFILE, encoding="utf-8") as handle:
        pg_major, py_minor, debian = pinned(handle.read())
    actionlint = read_pin(LINT_WORKFLOW, ACTIONLINT_PIN, "the pinned actionlint version")
    zizmor = read_pin(LINT_WORKFLOW, ZIZMOR_PIN, "the pinned zizmor version")
    starship = read_pin(SHELL_SETUP, STARSHIP_PIN, "the pinned Starship version")
    frontend = read_pin(DOCKERFILE, SYNTAX_PIN, "the pinned Dockerfile syntax (line 1)")

    rows = []  # (component, pinned, newest, status)
    notes = []

    def record(component, current, resolver, hint=None):
        try:
            newest = resolver()
        except (urllib.error.URLError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            rows.append((component, current, "unknown", f"could not check ({type(error).__name__})"))
            return
        behind = is_behind(current, newest)
        rows.append((component, current, newest, "behind" if behind else "current"))
        if behind and hint:
            notes.append(hint(newest))

    record(
        "PostgreSQL major (PG_MAJOR)",
        pg_major,
        lambda: newest_released("postgresql")["cycle"],
        lambda newest: (
            f"PostgreSQL {newest} is released. PG_MAJOR must stay equal to, or newer than, the server in "
            "django-template's compose file and CI; move both in the same release, and check that PGDG "
            f"publishes postgresql-client-{newest} for the Debian in use."
        ),
    )
    record(
        "Debian (python image tag)",
        debian,
        lambda: newest_released("debian")["codename"].lower(),
        lambda newest: (
            f"Debian '{newest}' is the newest stable. The python image tag follows it "
            f"(python:X.Y.Z-slim-{newest}); Dependabot will not switch the suffix, so change it by hand."
        ),
    )
    # Python follows Django: compare with the newest minor Django lists, and say
    # separately when a newer Python exists that Django does not support yet.
    try:
        django_version, minors = django_pythons()
        newest_supported = ".".join(map(str, minors[-1]))
        pinned_tuple = tuple(int(part) for part in py_minor.split("."))
        if pinned_tuple < minors[-1]:
            status = "behind"
            notes.append(
                f"Django {django_version} supports Python {newest_supported}. To move: change the python FROM line "
                "(tag and digest), the pinned minor in tests/smoke.sh and the README together. Dependabot only "
                "proposes Python patch bumps, so this is a manual step."
            )
        elif pinned_tuple > minors[-1]:
            status = "ahead"
            notes.append(
                f"The image pins Python {py_minor}, which Django {django_version} does not list "
                f"(it supports {', '.join('.'.join(map(str, m)) for m in minors)}). Move back, or confirm that "
                "Django supports it before releasing."
            )
        else:
            status = "current"
        rows.append(("Python minor (newest Django supports)", py_minor, newest_supported, status))
        try:
            released = newest_released("python")["cycle"]
            if status == "current" and tuple(int(part) for part in released.split(".")) > minors[-1]:
                notes.append(
                    f"Python {released} is released, but Django {django_version} does not support it yet: staying on "
                    f"{py_minor} is deliberate and not counted as drift."
                )
        except (urllib.error.URLError, OSError, ValueError, KeyError, json.JSONDecodeError):
            pass
    except (urllib.error.URLError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        rows.append(("Python minor (newest Django supports)", py_minor, "unknown", f"could not check ({type(error).__name__})"))

    record(
        "actionlint (Lint)",
        actionlint,
        lambda: newest_github_release("rhysd/actionlint"),
        lambda newest: (
            f"actionlint {newest} is released. Bump `version:` in {LINT_WORKFLOW} in a PR and let Lint run: a new "
            "release can add checks that fail on unchanged workflows. Remove the runner labels from "
            ".github/actionlint.yaml once actionlint knows them."
        ),
    )

    record(
        "zizmor (Lint)",
        zizmor,
        lambda: newest_pypi("zizmor"),
        lambda newest: (
            f"zizmor {newest} is released. Bump `zizmor==` in {LINT_WORKFLOW} in a PR and let Lint run: a new "
            "release can add audits that fail on unchanged workflows."
        ),
    )

    younger = []

    def starship_newest():
        aged, newest = newest_aged_release("starship/starship", COOLDOWN_DAYS)
        if newest != aged:
            younger.append(newest)
        return aged

    record(
        "Starship (prompt binary)",
        starship,
        starship_newest,
        lambda newest: (
            f"Starship {newest} is released (at least {COOLDOWN_DAYS} days ago). In {SHELL_SETUP} change "
            "`starship_version` and both SHA-256 values in one PR: download the two musl tarballs (x86_64 and "
            "aarch64), compute their SHA-256 yourself, and compare with the digests GitHub shows for the release "
            "assets. Do not copy the `.sha256` files from the release."
        ),
    )
    if younger:
        notes.append(
            f"Starship {younger[0]} is released but is less than {COOLDOWN_DAYS} days old: wait, as for every other "
            "dependency."
        )

    record(
        "Dockerfile syntax (frontend)",
        frontend,
        newest_dockerfile_frontend,
        lambda newest: (
            f"docker/dockerfile {newest} is released. Change line 1 of {DOCKERFILE} to "
            f"`# syntax=docker/dockerfile:{newest}@sha256:<digest>`; get the digest with "
            f"`docker buildx imagetools inspect docker/dockerfile:{newest} --format '{{{{.Manifest.Digest}}}}'`. "
            "Dependabot does not update this line."
        ),
    )

    drift = any(status in ("behind", "ahead") for *_, status in rows)

    lines = [
        f"Versions pinned in `{DOCKERFILE}`, `{SHELL_SETUP}` and `{LINT_WORKFLOW}` compared with the newest stable "
        "releases (endoflife.date, PyPI, GitHub, Docker Hub).",
        "",
        "| Component | Pinned | Newest stable (or supported) | Status |",
        "| --- | --- | --- | --- |",
    ]
    lines += [f"| {c} | `{p}` | `{n}` | {s} |" for c, p, n, s in rows]
    if notes:
        lines += ["", *[f"- {note}" for note in notes]]
    lines += [
        "",
        "Dependabot covers the python (patch updates only) and uv `FROM` lines, `docker/requirements-tools.txt` and the GitHub Actions; apt packages are checked by the weekly rebuild; the pins listed above (actionlint, zizmor, Starship, the Dockerfile syntax) are compared here.",
        "",
        "This report is kept by the `dependency-drift` workflow: it opens one issue while something is behind and closes it once nothing is.",
    ]
    with open(report_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")

    print("\n".join(lines))
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"drift={'true' if drift else 'false'}\n")


if __name__ == "__main__":
    main()
