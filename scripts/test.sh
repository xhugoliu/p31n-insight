#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
SWIFT_TOOL_BIN="$(dirname "$(xcrun --find swiftc)")"
TEST_PLUGIN="$SWIFT_TOOL_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
flags=()
# Recent CLT installations ship the Testing macro plugin in a subdirectory.
if [[ -f "$TEST_PLUGIN" ]]; then
  flags+=(-Xswiftc -load-plugin-library -Xswiftc "$TEST_PLUGIN")
fi
swift test "${flags[@]}" "$@"
