#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

node scripts/verify-site-scripts.mjs

xcrun swiftc -parse-as-library \
    scripts/verify-website.swift \
    Sources/NodeSeekClient/Website/AccountScripts.swift Sources/NodeSeekClient/Website/SiteScripts.swift \
    -o "$build_dir/verify-website"
"$build_dir/verify-website"
