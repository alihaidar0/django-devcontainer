#!/usr/bin/env python3
"""Report versions pinned in docker/Dockerfile.dev that are behind upstream.

Run by .github/workflows/dependency-drift.yml. Stdlib only.

Dependabot already tracks the literal FROM lines (the python and uv images), the
pip pins in docker/requirements-tools.txt and the GitHub Actions. What it cannot
see, and this script compares with the official release data on endoflife.date:

  PG_MAJOR          the PostgreSQL client major vs the newest released PostgreSQL
  Debian codename   the Debian in the python image tag vs the newest stable Debian
  Python minor      the Python line in the FROM line vs the newest Python that
                    Django officially supports (the version classifiers Django
                    publishes on PyPI), NOT the newest Python released: the image
                    follows Django, so Python 3.15 is not drift while Django does
                    not list it. Dependabot only proposes Python patch bumps (see
                    its ignore rule), so this row is what announces a new minor.

Starship is not pinned (it is installed from its latest release); the weekly
rebuild check (scripts/check-rebuild.sh) compares it with the newest release.

Usage: check_drift.py REPORT_FILE
Writes a Markdown report to REPORT_FILE and "drift=true|false" to $GITHUB_OUTPUT.
Always exits 0 unless the Dockerfile cannot be parsed; a source that cannot be
reached is reported as "unknown" and never counts as drift.
"""
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request

DOCKERFILE = "docker/Dockerfile.dev"
TIMEOUT = 30


def fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "dependency-drift"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


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


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    report_path = sys.argv[1]
    with open(DOCKERFILE, encoding="utf-8") as handle:
        pg_major, py_minor, debian = pinned(handle.read())

    rows = []  # (component, pinned, newest, status)
    notes = []

    def record(component, current, resolver, hint=None):
        try:
            newest = resolver()
        except (urllib.error.URLError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            rows.append((component, current, "unknown", f"could not check ({type(error).__name__})"))
            return
        behind = current != newest
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

    drift = any(status in ("behind", "ahead") for *_, status in rows)

    lines = [
        "Versions pinned in `docker/Dockerfile.dev` compared with the newest stable releases (endoflife.date).",
        "",
        "| Component | Pinned | Newest stable (or supported) | Status |",
        "| --- | --- | --- | --- |",
    ]
    lines += [f"| {c} | `{p}` | `{n}` | {s} |" for c, p, n, s in rows]
    if notes:
        lines += ["", *[f"- {note}" for note in notes]]
    lines += [
        "",
        "Dependabot covers the python (patch updates only) and uv `FROM` lines, `docker/requirements-tools.txt` and the GitHub Actions; Starship floats and is checked by the weekly rebuild.",
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
