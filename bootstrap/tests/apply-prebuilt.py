#!/usr/bin/env python3

"""Focused tests for metadata checks used by the prebuilt deployer."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "bootstrap" / "apply-prebuilt.py"
SPEC = importlib.util.spec_from_file_location("apply_prebuilt", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {MODULE_PATH}")
apply_prebuilt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(apply_prebuilt)


def expect_runtime_error(callback, expected: str) -> None:
    try:
        callback()
    except RuntimeError as error:
        if expected not in str(error):
            raise AssertionError(f"expected {expected!r} in {error!r}") from error
    else:
        raise AssertionError(f"expected RuntimeError containing {expected!r}")


with tempfile.TemporaryDirectory() as directory:
    package_dir = Path(directory)
    srcinfo = """\
pkgbase = example
\tpkgver = 2.4.0
\tpkgrel = 3
\tepoch = 1
pkgname = example
pkgname = example-docs
"""
    with mock.patch.object(apply_prebuilt, "command_output", return_value=srcinfo):
        names, version = apply_prebuilt.srcinfo_packages(package_dir)
        assert names == ["example", "example-docs"]
        assert version == "1:2.4.0-3"

    incomplete = "pkgbase = example\npkgname = example\n"
    with mock.patch.object(apply_prebuilt, "command_output", return_value=incomplete):
        expect_runtime_error(
            lambda: apply_prebuilt.srcinfo_packages(package_dir),
            "incomplete local package metadata",
        )

with mock.patch.object(apply_prebuilt, "command_output", return_value="provider 1.2.3-1"):
    assert apply_prebuilt.package_query("virtual-package") == ("provider", "1.2.3-1")
apply_prebuilt.require_explicit_package("virtual-package", "provider", {"provider"})
expect_runtime_error(
    lambda: apply_prebuilt.require_explicit_package("virtual-package", "provider", set()),
    "virtual-package -> provider",
)

failure = subprocess.CalledProcessError(1, ["pacman", "-Q", "missing"])
with mock.patch.object(apply_prebuilt, "command_output", side_effect=failure):
    expect_runtime_error(
        lambda: apply_prebuilt.package_query("missing"),
        "required prebuilt package is not installed",
    )

with mock.patch.object(apply_prebuilt.importlib.metadata, "version", return_value="1.1.2"):
    apply_prebuilt.require_cli_version()
with mock.patch.object(apply_prebuilt.importlib.metadata, "version", return_value="1.0.8"):
    expect_runtime_error(apply_prebuilt.require_cli_version, "found 1.0.8")


class FakeManifest:
    components = {"default-one": object(), "selected": object(), "unselected": object()}

    def resolve_components(self, *, enable, disable) -> None:
        assert enable == ["selected"]
        assert disable == ["default-one", "unselected"]


apply_prebuilt.resolve_requested_components(FakeManifest(), ["selected"])

with tempfile.TemporaryDirectory() as directory:
    managed = Path(directory) / "dots"
    (managed / ".git").mkdir(parents=True)
    with mock.patch.object(apply_prebuilt, "command_output", return_value="https://example.invalid/other.git"):
        expect_runtime_error(
            lambda: apply_prebuilt.ensure_managed_clone(
                managed,
                "https://github.com/ChrisBlackoutDev/caelestia.git",
                "candidate",
            ),
            "another origin",
        )

with tempfile.TemporaryDirectory() as directory:
    managed = Path(directory) / "dots"
    with mock.patch.object(apply_prebuilt, "run_command") as run:
        apply_prebuilt.ensure_managed_clone(
            managed,
            "https://github.com/ChrisBlackoutDev/caelestia.git",
            "candidate",
        )
        run.assert_called_once_with(
            apply_prebuilt.GIT,
            "clone",
            "--single-branch",
            "--branch",
            "candidate",
            "--",
            "https://github.com/ChrisBlackoutDev/caelestia.git",
            str(managed),
        )

print("apply-prebuilt-tests=passed scenarios=9")
