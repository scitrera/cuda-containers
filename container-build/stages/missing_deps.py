#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
import tomllib  # py3.11+

from importlib import metadata
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name


def load_pyproject(path: str) -> dict:
    with open(path, "rb") as f:
        return tomllib.load(f)


def iter_declared_requirements(pyproject: dict, extras: list[str]) -> list[str]:
    project = pyproject.get("project", {})

    reqs: list[str] = []
    base = project.get("dependencies", []) or []
    reqs.extend(base)

    opt = project.get("optional-dependencies", {}) or {}
    for extra in extras:
        reqs.extend(opt.get(extra, []) or [])

    return reqs


def marker_applies(req: Requirement) -> bool:
    # Evaluate PEP 508 markers for this environment.
    if req.marker is None:
        return True
    # packaging evaluates against default environment markers automatically
    return bool(req.marker.evaluate())


def is_installed(dist_name: str) -> bool:
    try:
        metadata.version(dist_name)
        return True
    except metadata.PackageNotFoundError:
        return False


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Emit only missing dependencies from pyproject.toml, optionally skipping a whitelist."
    )
    ap.add_argument("--pyproject", default="pyproject.toml", help="Path to pyproject.toml")
    ap.add_argument(
        "--extra",
        action="append",
        default=[],
        help="Optional dependency group (can be repeated), e.g. --extra dev",
    )
    ap.add_argument(
        "--ignore",
        action="append",
        default=[],
        help="Package name to ignore/skip (can be repeated).",
    )
    ap.add_argument(
        "--ignore-file",
        default=None,
        help="File with package names to ignore (one per line, # comments allowed).",
    )
    ap.add_argument(
        "--print-installed",
        action="store_true",
        help="Also print installed versions for the packages encountered (to stderr).",
    )

    args = ap.parse_args()

    ignore = {canonicalize_name(x) for x in (args.ignore or [])}

    if args.ignore_file:
        with open(args.ignore_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                ignore.add(canonicalize_name(line))

    pyproject = load_pyproject(args.pyproject)
    declared = iter_declared_requirements(pyproject, args.extra)

    missing_lines: list[str] = []

    for raw in declared:
        req = Requirement(raw)
        name = canonicalize_name(req.name)

        if name in ignore:
            continue

        if not marker_applies(req):
            continue

        installed = is_installed(req.name)
        if args.print_installed:
            if installed:
                ver = metadata.version(req.name)
                print(f"{req.name}=={ver} (installed)", file=sys.stderr)
            else:
                print(f"{req.name} (missing)", file=sys.stderr)

        if not installed:
            # Keep the original specifier (>=,==, etc.) from pyproject
            # but only emit it when the dist isn't installed at all.
            missing_lines.append(raw)

    # Deterministic output
    for line in sorted(missing_lines, key=lambda s: canonicalize_name(Requirement(s).name)):
        print(line)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
