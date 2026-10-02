#!/bin/bash
# Run every original core test with the macOS Command Line Tools alone.
# No XCTest/Xcode installation, package download or real vault is required.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /private/tmp/keynest-checks.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
module_cache="${KEYNEST_CHECK_MODULE_CACHE:-/private/tmp/keynest-check-module-cache}"
mkdir -p "$module_cache" "$work_dir/tests"

# Only imports are adapted. Line counts and every assertion/test body remain
# intact; source locations point back to the original files for diagnostics.
python3 - "$package_dir" "$work_dir" <<'PY'
import json
import pathlib
import re
import sys

package = pathlib.Path(sys.argv[1])
work = pathlib.Path(sys.argv[2])
tests = []
seen = set()
paths = sorted((package / "Tests" / "KeynestCoreTests").glob("*.swift"))
if not paths:
    raise SystemExit("No core test sources found.")

for path in paths:
    source = path.read_text(encoding="utf-8")
    classes = re.findall(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\s*\{", source, re.M)
    if len(classes) != 1:
        raise SystemExit(f"Expected exactly one XCTestCase class in {path.name}; refusing incomplete discovery.")
    case = classes[0]
    methods = re.findall(r"^\s*func\s+(test\w+)\s*\(\s*\)\s*(throws\s*)?\{", source, re.M)
    all_names = re.findall(r"\bfunc\s+(test\w+)\b", source)
    if len(methods) != len(all_names) or not methods:
        raise SystemExit(f"Unsupported test signature in {path.name}; refusing to omit tests.")
    for method, throwing in methods:
        name = f"{case}.{method}"
        if name in seen:
            raise SystemExit(f"Duplicate test discovered: {name}")
        seen.add(name)
        tests.append((case, method, bool(throwing)))
    adapted = re.sub(r"^import XCTest[ \t]*$", "// XCTest supplied by CheckHarness.swift", source, flags=re.M)
    adapted = re.sub(r"^@testable import KeynestCore[ \t]*$", "// KeynestCore compiled in this same test module", adapted, flags=re.M)
    # Foundation was otherwise re-exported by XCTest in QuotaClientTests.
    prefix = "import Foundation\n#sourceLocation(file: " + json.dumps(str(path), ensure_ascii=False) + ", line: 1)\n"
    # A distinct basename avoids Swift's #fileID collision warning while the
    # sourceLocation continues to identify the unmodified original test file.
    (work / "tests" / ("Adapted_" + path.name)).write_text(prefix + adapted, encoding="utf-8")

runner = ["import Foundation", "import Darwin", "",
          'if CommandLine.arguments.contains("--harness-negative-self-test") {',
          "    exit(CheckRunner.negativeSelfTest())", "}", ""]
for case, method, throwing in tests:
    name = f"{case}.{method}"
    runner.append(f'CheckRunner.run("{name}", makeCase: {{ {case}() }}) {{ instance in')
    runner.append(f'    {"try " if throwing else ""}instance.{method}()')
    runner.append("}")
runner.append(f"exit(CheckRunner.finish(expectedTestCount: {len(tests)}))")
(work / "main.swift").write_text("\n".join(runner) + "\n", encoding="utf-8")
print(f"Discovered all {len(tests)} tests in {len(paths)} original test sources.")
PY

core_sources=("$package_dir"/Sources/KeynestCore/*.swift)
CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
    -swift-version 5 -strict-concurrency=complete \
    -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$module_cache" \
    "${core_sources[@]}" "$script_dir/CheckHarness.swift" \
    "$work_dir"/tests/*.swift "$work_dir/main.swift" \
    -o "$work_dir/keynest-checks"

self_test_status=0
"$work_dir/keynest-checks" --harness-negative-self-test > "$work_dir/harness-self-test.log" 2>&1 || self_test_status=$?
if [[ "$self_test_status" -ne 1 ]] || ! awk '$0 == "HARNESS_SELF_TEST_OK" { found = 1 } END { exit !found }' "$work_dir/harness-self-test.log"; then
    cat "$work_dir/harness-self-test.log"
    echo "The assertion harness failed its negative-path self-test." >&2
    exit 1
fi
echo "Assertion harness negative-path self-test passed (9 real failures, nonzero exit)."
"$work_dir/keynest-checks"
