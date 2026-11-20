#!/bin/bash
set -euo pipefail

app=$1
package=$2
scripts=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

helper="$app/Contents/Helpers/iNodUpdateInstaller"
mkdir -p "$(dirname "$helper")"
for arch in arm64 x86_64; do
  xcrun --sdk macosx swiftc -module-cache-path "$work/modules" -swift-version 6 -O \
    -target "$arch-apple-macos26.0" \
    "$scripts/mac-update-installer.swift" -o "$work/$arch"
done
xcrun lipo -create "$work/arm64" "$work/x86_64" -output "$helper"
xcrun swift -module-cache-path "$work/modules" "$scripts/sign-mac-update.swift" public-key \
  > "$app/Contents/Resources/MacUpdatePublicKey"
codesign --force --sign - "$helper"
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags,runtime "$app"
codesign --verify --deep --strict "$app"

ditto -c -k --keepParent "$app" "$package"
unzip -tq "$package"
xcrun swift -module-cache-path "$work/modules" "$scripts/sign-mac-update.swift" sign "$package" "$package.ed25519"
