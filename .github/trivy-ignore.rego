# Trivy ignore policy for the image scan in .github/workflows/docker.yml (scan job),
# passed through the action's `ignore-policy` input.
#
# A finding belongs here only when it cannot affect this image and cannot be fixed
# from this repository. Per-version exceptions with a reason live in
# vex.openvex.json; this file is for a whole package.
package trivy

import rego.v1

default ignore := false

# linux-libc-dev is the Linux kernel *headers* package (/usr/include/linux/…).
# libc6-dev depends on it, so build-essential pulls it in; it is needed to compile
# native extensions. A container never runs that package's code: it runs on the
# host's kernel, and the headers contain no kernel code. Debian files every kernel
# CVE against it, so each week brings dozens of findings (63 HIGH at the time this
# rule was added) that no change here could address. Kernel fixes belong to the
# host (Docker Desktop / WSL2 / the cloud VM), not to this image.
ignore if {
	input.PkgName == "linux-libc-dev"
}
