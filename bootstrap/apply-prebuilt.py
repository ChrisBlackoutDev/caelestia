#!/usr/bin/env python3

"""Deploy an exact Caelestia revision after reviewed packages are preinstalled."""

from __future__ import annotations

import argparse
import importlib.metadata
import os
import re
import subprocess
import sys
from pathlib import Path


EXPECTED_CLI_VERSION = "1.1.2"
REVISION_PATTERN = re.compile(r"[0-9a-f]{40}")
PACMAN = "/usr/bin/pacman"
MAKEPKG = "/usr/bin/makepkg"
GIT = "/usr/bin/git"


def command_output(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.PIPE).strip()


def run_command(*args: str, cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def package_query(name: str) -> tuple[str, str]:
    try:
        fields = command_output(PACMAN, "-Q", name).split()
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        raise RuntimeError(f"required prebuilt package is not installed: {name}") from error
    if len(fields) < 2:
        raise RuntimeError(f"unexpected pacman query result for: {name}")
    return fields[0], fields[1]


def srcinfo_packages(directory: Path) -> tuple[list[str], str]:
    try:
        text = command_output(MAKEPKG, "--printsrcinfo", cwd=directory)
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        raise RuntimeError(f"failed to read local package metadata: {directory}") from error

    values: dict[str, list[str]] = {}
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator:
            values.setdefault(key.strip(), []).append(value.strip())

    names = values.get("pkgname", [])
    pkgver = next(iter(values.get("pkgver", [])), None)
    pkgrel = next(iter(values.get("pkgrel", [])), None)
    epoch = next(iter(values.get("epoch", [])), None)
    if not names or pkgver is None or pkgrel is None:
        raise RuntimeError(f"incomplete local package metadata: {directory}")
    version = f"{pkgver}-{pkgrel}"
    if epoch:
        version = f"{epoch}:{version}"
    return names, version


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Deploy configs and modern managed-dots state without running a package transaction."
    )
    parser.add_argument("--expected-revision", required=True)
    parser.add_argument("--expected-url", required=True)
    parser.add_argument("--expected-branch", required=True)
    parser.add_argument("--aur-helper", choices=("yay", "paru"), required=True)
    parser.add_argument("--enable-components", required=True)
    args = parser.parse_args()
    if not REVISION_PATTERN.fullmatch(args.expected_revision):
        parser.error("--expected-revision must be a full lowercase SHA-1 commit ID")
    if args.expected_branch.startswith("-"):
        parser.error("--expected-branch must not begin with a dash")
    return args


def require_cli_version() -> None:
    try:
        installed = importlib.metadata.version("caelestia")
    except importlib.metadata.PackageNotFoundError as error:
        raise RuntimeError("prebuilt deployment requires caelestia-cli 1.1.2") from error
    if installed != EXPECTED_CLI_VERSION:
        raise RuntimeError(
            f"prebuilt deployment requires caelestia-cli {EXPECTED_CLI_VERSION}; found {installed}"
        )


def require_explicit_package(desired: str, installed_name: str, explicit_packages: set[str]) -> None:
    if installed_name not in explicit_packages:
        raise RuntimeError(
            f"required prebuilt package is not explicitly installed: {desired} -> {installed_name}"
        )


def resolve_requested_components(manifest: object, enabled: list[str]) -> None:
    disabled = [name for name in manifest.components if name not in enabled]
    manifest.resolve_components(enable=enabled, disable=disabled)


def ensure_managed_clone(path: Path, url: str, branch: str) -> None:
    git_dir = path / ".git"
    if git_dir.is_dir():
        current_url = command_output(GIT, "-C", str(path), "remote", "get-url", "origin")
        if current_url != url:
            raise RuntimeError("refusing to replace an existing managed-dots clone from another origin")
        run_command(GIT, "-C", str(path), "fetch", "--prune", "origin", branch)
        return

    if path.exists():
        raise RuntimeError(f"refusing to replace a non-Git managed-dots path: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    run_command(GIT, "clone", "--single-branch", "--branch", branch, "--", url, str(path))


def main() -> int:
    args = parse_args()
    require_cli_version()
    helper_path = Path("/usr/bin") / args.aur_helper
    if not helper_path.is_file() or not os.access(helper_path, os.X_OK):
        raise RuntimeError(f"required AUR helper is unavailable: {helper_path}")
    run_command(GIT, "check-ref-format", f"refs/heads/{args.expected_branch}")

    from caelestia.utils.dots.deployer import Deployer
    from caelestia.utils.dots.manifest import Manifest
    from caelestia.utils.dots.misc import run_hooks
    from caelestia.utils.dots.source import DotsSource
    from caelestia.utils.dots.state import DotsState
    from caelestia.utils.paths import dots_dir, dots_state_path

    source = DotsSource()
    if source.url != args.expected_url or source.branch != args.expected_branch:
        raise RuntimeError("CLI dots source does not match the expected fork and branch")
    if dots_dir.is_symlink() or (dots_dir.exists() and not dots_dir.is_dir()):
        raise RuntimeError(f"refusing unsafe managed-dots path: {dots_dir}")
    ensure_managed_clone(dots_dir, args.expected_url, args.expected_branch)
    tip = command_output(GIT, "-C", str(dots_dir), "rev-parse", f"origin/{args.expected_branch}")
    if tip != args.expected_revision:
        raise RuntimeError(f"remote branch tip changed: expected {args.expected_revision}, found {tip}")
    if command_output(GIT, "-C", str(dots_dir), "rev-parse", "HEAD") != tip:
        raise RuntimeError("managed-dots working tree is not checked out at the expected tip")
    if command_output(GIT, "-C", str(dots_dir), "status", "--porcelain"):
        raise RuntimeError("managed-dots working tree is not clean")
    if dots_state_path.is_symlink() or (dots_state_path.exists() and not dots_state_path.is_file()):
        raise RuntimeError(f"refusing unsafe managed-dots state path: {dots_state_path}")

    manifest = Manifest.parse(command_output(GIT, "-C", str(dots_dir), "show", f"{tip}:manifest.toml"))
    enabled = [item.strip() for item in args.enable_components.split(",") if item.strip()]
    resolve_requested_components(manifest, enabled)

    explicit_packages = set(command_output(PACMAN, "-Qqe").splitlines())
    packages: dict[str, str] = {}
    for desired in manifest.enabled_packages():
        installed_name, _ = package_query(desired)
        require_explicit_package(desired, installed_name, explicit_packages)
        packages[desired] = installed_name

    local_packages: dict[str, list[str]] = {}
    for relative in manifest.enabled_local_packages():
        directory = dots_dir / relative
        if not directory.is_dir():
            raise RuntimeError(f"local package directory is absent: {relative}")
        names, expected_version = srcinfo_packages(directory)
        for name in names:
            installed_name, installed_version = package_query(name)
            if installed_name != name or installed_version != expected_version:
                raise RuntimeError(
                    f"local package version mismatch for {name}: "
                    f"expected {expected_version}, found {installed_name} {installed_version}"
                )
            require_explicit_package(name, installed_name, explicit_packages)
        local_packages[relative] = names

    run_hooks(manifest, "post_package")
    deployer = Deployer()
    for entry in manifest.enabled_entries():
        src = dots_dir / entry.expanded_src()
        if not src.exists():
            print(f"warning: missing source entry, skipping: {entry.src}", file=sys.stderr)
            continue
        destinations = entry.expanded_dests()
        if not destinations:
            print(f"warning: destination glob matched nothing, skipping: {entry.dest}", file=sys.stderr)
            continue
        for destination in destinations:
            deployer.place(src, Path(destination))
            print(f"deployed {entry.src} -> {destination}")
    run_hooks(manifest, "post_install")

    DotsState(
        aur_helper=args.aur_helper,
        applied_rev=tip,
        enabled_components=manifest.enabled_components,
        packages=packages,
        local_packages=local_packages,
        deployed_files=deployer.deployed_files,
    ).save()
    print(
        "prebuilt deployment complete: "
        f"revision={tip} components={len(manifest.enabled_components)} "
        f"packages={len(packages)} local_packages={len(local_packages)} "
        f"files={len(deployer.deployed_files)}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
