#!/usr/bin/env python3
"""Run avatar cache checks against the app's real loader without network access."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="nodeseek-avatar-checks-") as temporary:
    executable = str(Path(temporary) / "verify-avatar-cache")
    build = Path(temporary)
    sources = sorted(str(path) for path in (root / "Sources/NodeSeekCore").rglob("*.swift"))
    compiler = ["swiftc", "-swift-version", "6", "-parse-as-library", "-module-cache-path", str(build / "modules")]
    subprocess.run([*compiler, "-emit-library", "-emit-module", "-module-name", "NodeSeekCore",
                    "-emit-module-path", str(build / "NodeSeekCore.swiftmodule"),
                    "-o", str(build / "libNodeSeekCore.dylib"), *sources], check=True)
    sources = [str(root / path) for path in (
        "Sources/NodeSeekClient/Media/AvatarImageLoader.swift",
        "Sources/NodeSeekClient/Website/SiteError.swift",
        "scripts/verify-avatar-cache.swift",
    )]
    subprocess.run([*compiler, "-I", temporary, "-L", temporary, "-lNodeSeekCore",
                    "-Xlinker", "-rpath", "-Xlinker", temporary, "-o", executable, *sources], check=True)
    subprocess.run([executable], check=True, timeout=15)
