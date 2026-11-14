#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

node scripts/verify-site-scripts.mjs

xcrun swiftc -parse-as-library \
    scripts/verify-account-html.swift Sources/NodeSeekClient/Website/AccountScripts.swift \
    -o "$build_dir/verify-account-html"
"$build_dir/verify-account-html"

xcrun swiftc -parse-as-library \
    scripts/verify-post-access.swift Sources/NodeSeekClient/Website/SiteScripts.swift \
    -o "$build_dir/verify-post-access"
"$build_dir/verify-post-access"
