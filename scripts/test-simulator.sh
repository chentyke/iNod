#!/bin/bash
# CI passes the project, destination and XCTest filters as individual arguments.
set -eu -o pipefail

bundle="$RUNNER_TEMP/$RESULTS"
log="$bundle.log"
if xcodebuild "$@" -resultBundlePath "$bundle.xcresult" test 2>&1 | tee "$log"; then
    exit 0
else
    status=("${PIPESTATUS[@]}")
fi

# Only retry Xcode failures seen before any test case started. Preserve the first report.
if (( status[1] != 0 )); then exit "${status[1]}"; fi
if grep -q "^Test Case '" "$log"; then exit "${status[0]}"; fi
case "${status[0]}" in
    70) grep -Fq 'xcodebuild: error: Unable to find a device matching the provided destination specifier' "$log" || exit 70 ;;
    65) grep -Fq 'The test runner crashed while preparing to run tests:' "$log" || exit 65 ;;
    *) exit "${status[0]}" ;;
esac

echo "::warning::Xcode could not start the simulator tests. Retrying once on the same device."
xcrun simctl bootstatus "$SIMULATOR_ID" -b
exec xcodebuild "$@" -resultBundlePath "$bundle-retry.xcresult" test
