#!/bin/bash
set -e

echo "=== Running makeapex makedepends test suite ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${MESON_BUILD_ROOT:-$ROOT_DIR/build}"
MAKEAPEX_BIN="$BUILD_DIR/makeapex"
LIBMAKEAPEX_DIR="$BUILD_DIR/src/libmakeapex"

export MAKEAPEX_LIBRARY="$LIBMAKEAPEX_DIR"

TEST_TMPDIR=$(mktemp -d /tmp/makeapex_test.XXXXXX)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Test 1: Check environment detection (is_bionic=0 on Linux host)
echo "[Test 1] Environment detection on host"
HOST_IS_BIONIC=$(bash -c "
$(sed -n '/# Detect non-Android/,/export is_bionic/p' "$MAKEAPEX_BIN")
echo \$is_bionic
")

if [[ "$HOST_IS_BIONIC" != "0" ]]; then
    echo "FAILED: Expected is_bionic=0 on Linux host, got '$HOST_IS_BIONIC'"
    exit 1
fi
echo "PASSED: is_bionic=0 on Linux host"

# Sanity check makeapex binary
"$MAKEAPEX_BIN" --version >/dev/null
"$MAKEAPEX_BIN" --help >/dev/null
echo "PASSED: makeapex --version and --help run properly"

# Test 2: Source makeapex functions directly and test check_buildtime_deps_non_android
echo "[Test 2] Direct unit test of check_buildtime_deps_non_android"

UNIT_OUTPUT=$(bash -c "
# Source dependencies
for lib in '$LIBMAKEAPEX_DIR'/*.sh; do
    source \"\$lib\"
done
source '$LIBMAKEAPEX_DIR/util/message.sh'

# Extract helper functions from built makeapex
$(sed -n '/^check_apex_lib_exists() {/,/^handle_deps() {/p' "$MAKEAPEX_BIN" | sed '$d')

is_bionic=0
CHECKFUNC=0
makedepends=('libnonexistent_test_dep.so' 'libmissing_tool' 'libversioned_dep.so>=2.0.0')
checkdepends=('libtestonly_dep.so')

echo '--- Running with CHECKFUNC=0 ---'
check_buildtime_deps_non_android

echo '--- Running with CHECKFUNC=1 ---'
CHECKFUNC=1
check_buildtime_deps_non_android
" 2>&1)

echo "$UNIT_OUTPUT"

# Verify that CHECKFUNC=0 warns about libnonexistent_test_dep.so, libmissing_tool, and libversioned_dep.so>=2.0.0, but NOT libtestonly_dep.so
if ! echo "$UNIT_OUTPUT" | grep -q "Unmet make dependencies:"; then
    echo "FAILED: Expected 'Unmet make dependencies:' in output"
    exit 1
fi
if ! echo "$UNIT_OUTPUT" | grep -q "libnonexistent_test_dep.so"; then
    echo "FAILED: Expected 'libnonexistent_test_dep.so' in output"
    exit 1
fi
if ! echo "$UNIT_OUTPUT" | grep -q "libmissing_tool"; then
    echo "FAILED: Expected 'libmissing_tool' in output"
    exit 1
fi
if ! echo "$UNIT_OUTPUT" | grep -q "libversioned_dep.so>=2.0.0"; then
    echo "FAILED: Expected 'libversioned_dep.so>=2.0.0' in output"
    exit 1
fi

# In the first run (CHECKFUNC=0), libtestonly_dep.so must not appear before 'Running with CHECKFUNC=1'
FIRST_PART=$(echo "$UNIT_OUTPUT" | sed -n '/Running with CHECKFUNC=0/,/Running with CHECKFUNC=1/p')
if echo "$FIRST_PART" | grep -q "libtestonly_dep.so"; then
    echo "FAILED: libtestonly_dep.so should NOT be present when CHECKFUNC=0"
    exit 1
fi

# In the second run (CHECKFUNC=1), libtestonly_dep.so MUST appear
SECOND_PART=$(echo "$UNIT_OUTPUT" | sed -n '/Running with CHECKFUNC=1/,$p')
if ! echo "$SECOND_PART" | grep -q "libtestonly_dep.so"; then
    echo "FAILED: libtestonly_dep.so MUST be present when CHECKFUNC=1"
    exit 1
fi
echo "PASSED: check_buildtime_deps_non_android properly checks makedepends and conditionally checkdepends"

# Test 3: Test that satisfied dependencies in APEX_SEARCH_PATH do NOT produce warnings (testing real check_apex_lib_exists)
echo "[Test 3] Satisfied dependencies in APEX search path (real check_apex_lib_exists)"

SATISFIED_OUTPUT=$(bash -c "
for lib in '$LIBMAKEAPEX_DIR'/*.sh; do
    source \"\$lib\"
done
source '$LIBMAKEAPEX_DIR/util/message.sh'

$(sed -n '/^check_apex_lib_exists() {/,/^handle_deps() {/p' "$MAKEAPEX_BIN" | sed '$d')

is_bionic=0
CHECKFUNC=0

# Create a mock apex search path
MOCK_APEX_DIR='$TEST_TMPDIR/mock_apex/com.test.dep/lib'
mkdir -p \"\$MOCK_APEX_DIR\"
touch \"\$MOCK_APEX_DIR/libpresent.so\"

export APEX_SEARCH_PATH='$TEST_TMPDIR/mock_apex'

makedepends=('libpresent.so' 'libpresent.so>=1.0.0' 'libmissing.so')
check_buildtime_deps_non_android
" 2>&1)

echo "$SATISFIED_OUTPUT"

if echo "$SATISFIED_OUTPUT" | grep -q "libpresent.so"; then
    echo "FAILED: libpresent.so was present in APEX_SEARCH_PATH but was warned as unmet"
    exit 1
fi
if ! echo "$SATISFIED_OUTPUT" | grep -q "libmissing.so"; then
    echo "FAILED: libmissing.so was missing but was not warned"
    exit 1
fi
echo "PASSED: Satisfied libraries in APEX search paths are not warned"

# Test 4: End-to-end makeapex execution with an APEXBUILD that has missing makedepends on non-Android
echo "[Test 4] End-to-end makeapex run with missing makedepends"
TEST_PKG_DIR="$TEST_TMPDIR/testpkg"
mkdir -p "$TEST_PKG_DIR"

cat > "$TEST_PKG_DIR/APEXBUILD" << 'EOF'
pkgname=com.test.makedepstest
pkgver=1.0.0
pkgrel=1
arch=('any')
payload_fs=erofs
makedepends=('libsomemissing.so' 'libanothermissing.so')

build() {
  echo "BUILD_EXECUTED_SUCCESSFULLY"
}

package() {
  mkdir -p "$pkgdir/bin"
  echo "test" > "$pkgdir/bin/test"
}
EOF

# Run makeapex --nobuild (or normal build) inside TEST_PKG_DIR
cd "$TEST_PKG_DIR"
BUILD_OUTPUT=$(bash "$MAKEAPEX_BIN" --nobuild 2>&1 || true)
echo "$BUILD_OUTPUT"

if ! echo "$BUILD_OUTPUT" | grep -q "WARNING:.*Unmet make dependencies:"; then
    echo "FAILED: makeapex --nobuild did not emit 'WARNING: Unmet make dependencies:'"
    exit 1
fi
if ! echo "$BUILD_OUTPUT" | grep -q "libsomemissing.so"; then
    echo "FAILED: makeapex --nobuild did not report 'libsomemissing.so'"
    exit 1
fi
if ! echo "$BUILD_OUTPUT" | grep -q "libanothermissing.so"; then
    echo "FAILED: makeapex --nobuild did not report 'libanothermissing.so'"
    exit 1
fi
if echo "$BUILD_OUTPUT" | grep -q "Could not resolve all dependencies"; then
    echo "FAILED: makeapex failed on missing makedepends when it should have continued"
    exit 1
fi
if ! echo "$BUILD_OUTPUT" | grep -q "Sources are ready."; then
    echo "FAILED: makeapex --nobuild did not continue to 'Sources are ready.'"
    exit 1
fi
echo "PASSED: makeapex emits warning and continues build successfully on missing makedepends"

# Test 4b: End-to-end checkdepends with check() function and --nocheck flag
echo "[Test 4b] End-to-end makeapex with checkdepends and --nocheck"
TEST_CHECK_PKG_DIR="$TEST_TMPDIR/testpkg_check"
mkdir -p "$TEST_CHECK_PKG_DIR"

cat > "$TEST_CHECK_PKG_DIR/APEXBUILD" << 'EOF'
pkgname=com.test.checkdependstest
pkgver=1.0.0
pkgrel=1
arch=('any')
payload_fs=erofs
makedepends=()
checkdepends=('libtestonly_missing.so')

build() {
  echo "BUILD_EXECUTED"
}

check() {
  echo "CHECK_EXECUTED"
}

package() {
  mkdir -p "$pkgdir/bin"
}
EOF

cd "$TEST_CHECK_PKG_DIR"
# Run without --nocheck (check() is active, checkdepends should be warned)
CHECK_ENABLED_OUTPUT=$(bash "$MAKEAPEX_BIN" --nobuild 2>&1 || true)
echo "$CHECK_ENABLED_OUTPUT"
if ! echo "$CHECK_ENABLED_OUTPUT" | grep -q "libtestonly_missing.so"; then
    echo "FAILED: Expected checkdepends warning when test function is active"
    exit 1
fi

# Run with --nocheck (check() is inactive, checkdepends should NOT be warned)
CHECK_DISABLED_OUTPUT=$(bash "$MAKEAPEX_BIN" --nobuild --nocheck 2>&1 || true)
echo "$CHECK_DISABLED_OUTPUT"
if echo "$CHECK_DISABLED_OUTPUT" | grep -q "libtestonly_missing.so"; then
    echo "FAILED: checkdepends should NOT be warned when --nocheck is used"
    exit 1
fi
echo "PASSED: checkdepends conditionally warned only when tests are enabled"

# Test 5: End-to-end makeapex with -s/--syncdeps on non-Android
echo "[Test 5] End-to-end makeapex with -s/--syncdeps on non-Android"
cd "$TEST_PKG_DIR"
SYNCDEPS_OUTPUT=$(bash "$MAKEAPEX_BIN" -s --nobuild 2>&1 || true)
echo "$SYNCDEPS_OUTPUT"

if echo "$SYNCDEPS_OUTPUT" | grep -q "Installing missing dependencies"; then
    echo "FAILED: makeapex -s attempted to install makedepends on non-Android"
    exit 1
fi
if ! echo "$SYNCDEPS_OUTPUT" | grep -q "WARNING:.*Unmet make dependencies:"; then
    echo "FAILED: makeapex -s did not emit warning"
    exit 1
fi
if ! echo "$SYNCDEPS_OUTPUT" | grep -q "Sources are ready."; then
    echo "FAILED: makeapex -s did not continue successfully"
    exit 1
fi
echo "PASSED: makeapex -s does not attempt to install makedepends via apexm on non-Android"

# Test 6: Verify simulated Android failure behavior (is_bionic=1)
echo "[Test 6] Simulated Android behavior (is_bionic=1 fails on missing makedepends)"
cd "$TEST_PKG_DIR"
BIONIC_OUTPUT=$(is_bionic=1 "$MAKEAPEX_BIN" --nobuild 2>&1 || true)
echo "$BIONIC_OUTPUT"

if ! echo "$BIONIC_OUTPUT" | grep -q "Could not resolve all dependencies"; then
    echo "FAILED: on simulated Android (is_bionic=1), missing makedepends should cause build failure"
    exit 1
fi
echo "PASSED: on Android (is_bionic=1), missing makedepends causes failure as expected"

echo "=== All 7 tests PASSED successfully ==="

if [[ -n "$1" ]]; then
    touch "$1"
fi
