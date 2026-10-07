#!/bin/bash
set -e

echo "=== Running makeapex versionCode test suite ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${MESON_BUILD_ROOT:-$ROOT_DIR/build}"
MAKEAPEX_BIN="$BUILD_DIR/makeapex"
LIBMAKEAPEX_DIR="$BUILD_DIR/src/libmakeapex"

export MAKEAPEX_LIBRARY="$LIBMAKEAPEX_DIR"

TEST_TMPDIR=$(mktemp -d /tmp/makeapex_vercode_test.XXXXXX)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Source makeapex library helpers
for lib in "$LIBMAKEAPEX_DIR"/*.sh; do
    # shellcheck source=/dev/null
    source "$lib"
done
source "$LIBMAKEAPEX_DIR/util/message.sh"
source "$LIBMAKEAPEX_DIR/util/apexbuild.sh"

echo "[Test 1] Unit test of get_apex_version_code calculation"

# Test 1a: 3-part version (7.2.11-1 -> 7002012)
pkgver="7.2.11"
pkgrel="1"
pkgvercode=""
epoch=""
res=$(get_apex_version_code)
if [[ "$res" != "7002012" ]]; then
    echo "FAILED: Expected 7002012 for 7.2.11-1, got '$res'"
    exit 1
fi
echo "PASSED: 7.2.11-1 -> 7002012"

# Test 1b: 2-part version (2.4-1 -> 2005)
pkgver="2.4"
pkgrel="1"
res=$(get_apex_version_code)
if [[ "$res" != "2005" ]]; then
    echo "FAILED: Expected 2005 for 2.4-1, got '$res'"
    exit 1
fi
echo "PASSED: 2.4-1 -> 2005"

# Test 1c: 1-part version (5-1 -> 6)
pkgver="5"
pkgrel="1"
res=$(get_apex_version_code)
if [[ "$res" != "6" ]]; then
    echo "FAILED: Expected 6 for 5-1, got '$res'"
    exit 1
fi
echo "PASSED: 5-1 -> 6"

# Test 1d: pkgrel bump (7.2.11-2 -> 7002013)
pkgver="7.2.11"
pkgrel="2"
res=$(get_apex_version_code)
if [[ "$res" != "7002013" ]]; then
    echo "FAILED: Expected 7002013 for 7.2.11-2, got '$res'"
    exit 1
fi
echo "PASSED: 7.2.11-2 -> 7002013"

# Test 1e: pkgrel with decimal (1.0.0-1.2 -> 1000001)
pkgver="1.0.0"
pkgrel="1.2"
res=$(get_apex_version_code)
if [[ "$res" != "1000001" ]]; then
    echo "FAILED: Expected 1000001 for 1.0.0-1.2, got '$res'"
    exit 1
fi
echo "PASSED: 1.0.0-1.2 -> 1000001"

# Test 1f: explicit pkgvercode override
pkgver="7.2.11"
pkgrel="1"
pkgvercode="998877"
res=$(get_apex_version_code)
if [[ "$res" != "998877" ]]; then
    echo "FAILED: Expected 998877 for explicit pkgvercode, got '$res'"
    exit 1
fi
echo "PASSED: explicit pkgvercode override -> 998877"
pkgvercode=""

echo "[Test 2] Unit test of get_apex_version_code_major (epoch)"

epoch=0
major_res=$(get_apex_version_code_major)
if [[ -n "$major_res" ]]; then
    echo "FAILED: Expected empty versionCodeMajor for epoch=0, got '$major_res'"
    exit 1
fi

epoch=1
major_res=$(get_apex_version_code_major)
if [[ "$major_res" != "1" ]]; then
    echo "FAILED: Expected 1 for epoch=1, got '$major_res'"
    exit 1
fi

epoch=3
major_res=$(get_apex_version_code_major)
if [[ "$major_res" != "3" ]]; then
    echo "FAILED: Expected 3 for epoch=3, got '$major_res'"
    exit 1
fi
echo "PASSED: get_apex_version_code_major behaves as expected"

echo "[Test 3] End-to-end makeapex manifest generation test"

TEST_PKG_DIR="$TEST_TMPDIR/testpkg"
mkdir -p "$TEST_PKG_DIR"

cat > "$TEST_PKG_DIR/APEXBUILD" << 'EOF'
pkgname=com.test.vercodetest
pkgver=7.2.11
pkgrel=1
arch=('any')
payload_fs=erofs

package() {
  mkdir -p "$pkgdir/bin"
  echo "test" > "$pkgdir/bin/test"
}
EOF

# Run makeapex --nobuild to parse APEXBUILD and lint
cd "$TEST_PKG_DIR"
BUILD_OUTPUT=$(bash "$MAKEAPEX_BIN" --nobuild 2>&1 || true)
if ! echo "$BUILD_OUTPUT" | grep -q "Sources are ready."; then
    echo "FAILED: makeapex --nobuild failed: $BUILD_OUTPUT"
    exit 1
fi
echo "PASSED: makeapex parses APEXBUILD cleanly"

echo "[Test 3b] Verify manifest attributes for calculated and overridden versionCode"
MANIFEST_OUTPUT=$(bash -c "
for lib in '$LIBMAKEAPEX_DIR'/*.sh; do
    source \"\$lib\"
done
source '$LIBMAKEAPEX_DIR/util/message.sh'
source '$LIBMAKEAPEX_DIR/util/apexbuild.sh'

pkgname=com.test.manifesttest
pkgver=7.2.11
pkgrel=1
epoch=2
fullver=\$(get_full_version)
android_pkgname=\"\$pkgname\"

vercode=\$(get_apex_version_code \"\$pkgname\")
vercode_major=\$(get_apex_version_code_major)
manifest_vercode_attr=\"android:versionCode=\\\"\$vercode\\\"\"
if [[ -n \"\$vercode_major\" ]] && (( vercode_major > 0 )); then
    manifest_vercode_attr+=\" android:versionCodeMajor=\\\"\$vercode_major\\\"\"
fi

manifest_version=\"\$vercode\"
if [[ -n \"\$vercode_major\" ]] && (( vercode_major > 0 )); then
    manifest_version=\$(( (vercode_major << 32) | (vercode & 0xFFFFFFFF) ))
fi

echo \"XML_ATTR: \$manifest_vercode_attr\"
echo \"PB_VER: \$manifest_version\"
")

echo "$MANIFEST_OUTPUT"
if ! echo "$MANIFEST_OUTPUT" | grep -q 'android:versionCode="7002012"'; then
    echo "FAILED: Expected android:versionCode=\"7002012\""
    exit 1
fi
if ! echo "$MANIFEST_OUTPUT" | grep -q 'android:versionCodeMajor="2"'; then
    echo "FAILED: Expected android:versionCodeMajor=\"2\""
    exit 1
fi
EXPECTED_PB_VER=$(( (2 << 32) | 7002012 ))
if ! echo "$MANIFEST_OUTPUT" | grep -q "PB_VER: $EXPECTED_PB_VER"; then
    echo "FAILED: Expected PB_VER: $EXPECTED_PB_VER"
    exit 1
fi
echo "PASSED: manifest attributes and protobuf version code match expected values"

echo "[Test 4] Verify linter catches non-integer pkgvercode"

TEST_INVALID_DIR="$TEST_TMPDIR/invalidpkg"
mkdir -p "$TEST_INVALID_DIR"

cat > "$TEST_INVALID_DIR/APEXBUILD" << 'EOF'
pkgname=com.test.invalidpkg
pkgver=1.0.0
pkgrel=1
arch=('any')
payload_fs=erofs
pkgvercode="abc12"

package() {
  mkdir -p "$pkgdir/bin"
}
EOF

cd "$TEST_INVALID_DIR"
LINT_OUTPUT=$(bash "$MAKEAPEX_BIN" --nobuild 2>&1 || true)
if ! echo "$LINT_OUTPUT" | grep -q "pkgvercode must be a positive integer"; then
    echo "FAILED: Linter did not reject non-integer pkgvercode: $LINT_OUTPUT"
    exit 1
fi
echo "PASSED: linter rejects non-integer pkgvercode"

echo "=== All versionCode tests PASSED successfully ==="

if [[ -n "$1" ]]; then
    touch "$1"
fi
