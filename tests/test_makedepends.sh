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

# Test 7: Verify skip-abi options passed to apexm (default level 3, explicit level, custom)
echo "[Test 7] Verify skip-abi flags forwarded to apexm"
MOCK_DIR="$TEST_TMPDIR/mock_bin"
mkdir -p "$MOCK_DIR"
cat > "$MOCK_DIR/apexm" << 'EOF'
#!/bin/bash
echo "MOCK_APEXM_ARGS: $@" >> "$MOCK_APEXM_LOG"
exit 0
EOF
chmod +x "$MOCK_DIR/apexm"

MOCK_APEXM_LOG="$TEST_TMPDIR/apexm.log"
export MOCK_APEXM_LOG

TEST_CONF="$TEST_TMPDIR/test_makeapex.conf"
cat "$BUILD_DIR/makeapex.conf" > "$TEST_CONF"
echo "PACMAN_AUTH=()" >> "$TEST_CONF"

# Package with runtime dependency to trigger handle_deps in resolve_deps
TEST_DEP_PKG="$TEST_TMPDIR/deppkg"
mkdir -p "$TEST_DEP_PKG"
cat > "$TEST_DEP_PKG/APEXBUILD" << 'EOF'
pkgname=com.test.deppkg
pkgver=1.0.0
pkgrel=1
arch=('any')
depends=('libmissing.so')
EOF
cd "$TEST_DEP_PKG"

# 7a: Default should pass --skip-abi-level=3
> "$MOCK_APEXM_LOG"
PATH="$MOCK_DIR:$PATH" is_bionic=1 "$MAKEAPEX_BIN" --config "$TEST_CONF" --syncdeps --noconfirm --nobuild >/dev/null 2>&1 || true
if ! grep "MOCK_APEXM_ARGS: -S" "$MOCK_APEXM_LOG" | grep -q -- "--skip-abi-level=3"; then
    echo "FAILED: makeapex did not pass --skip-abi-level=3 by default to apexm"
    exit 1
fi
echo "PASSED: makeapex defaults to --skip-abi-level=3 when invoking apexm"

# 7b: Explicit --skip-abi-level 1
> "$MOCK_APEXM_LOG"
PATH="$MOCK_DIR:$PATH" is_bionic=1 "$MAKEAPEX_BIN" --config "$TEST_CONF" --syncdeps --noconfirm --nobuild --skip-abi-level 1 >/dev/null 2>&1 || true
if ! grep "MOCK_APEXM_ARGS: -S" "$MOCK_APEXM_LOG" | grep -q -- "--skip-abi-level=1"; then
    echo "FAILED: makeapex did not forward --skip-abi-level=1 to apexm"
    exit 1
fi
if grep "MOCK_APEXM_ARGS: -S" "$MOCK_APEXM_LOG" | grep -q -- "--skip-abi-level=3"; then
    echo "FAILED: makeapex should not pass --skip-abi-level=3 when overridden"
    exit 1
fi
echo "PASSED: makeapex overrides --skip-abi-level properly"

# 7c: --disable-skip-abis and --skip-abi-custom
> "$MOCK_APEXM_LOG"
PATH="$MOCK_DIR:$PATH" is_bionic=1 "$MAKEAPEX_BIN" --config "$TEST_CONF" --syncdeps --noconfirm --nobuild --disable-skip-abis --skip-abi-custom /path/to/libcustom.so >/dev/null 2>&1 || true
if ! grep "MOCK_APEXM_ARGS: -S" "$MOCK_APEXM_LOG" | grep -q -- "--disable-skip-abis"; then
    echo "FAILED: makeapex did not forward --disable-skip-abis to apexm"
    exit 1
fi
if ! grep "MOCK_APEXM_ARGS: -S" "$MOCK_APEXM_LOG" | grep -q -- "--skip-abi-custom=/path/to/libcustom.so"; then
    echo "FAILED: makeapex did not forward --skip-abi-custom to apexm"
    exit 1
fi
# Test 8: End-to-end install available makedepends via apexm on non-Android and warn on unavailable
echo "[Test 8] End-to-end install available makedepends via apexm on non-Android"
TEST_AVAIL_PKG_DIR="$TEST_TMPDIR/testpkg_avail"
mkdir -p "$TEST_AVAIL_PKG_DIR"

cat > "$TEST_AVAIL_PKG_DIR/APEXBUILD" << 'EOF'
pkgname=com.test.availmakedeps
pkgver=1.0.0
pkgrel=1
arch=('any')
payload_fs=erofs
makedepends=('libavail.so' 'libunavail.so')

build() {
  echo "BUILD_EXECUTED"
}

package() {
  mkdir -p "$pkgdir/bin"
}
EOF

MOCK_AVAIL_DIR="$TEST_TMPDIR/mock_avail_bin"
mkdir -p "$MOCK_AVAIL_DIR"
MOCK_AVAIL_APEX_DIR="$TEST_TMPDIR/mock_avail_apex"
mkdir -p "$MOCK_AVAIL_APEX_DIR"

cat > "$MOCK_AVAIL_DIR/apexm" << 'EOF'
#!/bin/bash
echo "MOCK_APEXM_INVOKED: $@" >> "$MOCK_APEXM_AVAIL_LOG"
if [[ "$*" == *"-Ss "* ]]; then
    if [[ "$*" == *"libavail.so"* ]]; then
        echo "apex/libavail 1.0.0 [installed]"
        exit 0
    else
        exit 1
    fi
elif [[ "$*" == *"-S "* ]]; then
    if [[ "$*" == *"libavail.so"* ]]; then
        mkdir -p "$MOCK_AVAIL_APEX_DIR/lib"
        touch "$MOCK_AVAIL_APEX_DIR/lib/libavail.so"
        exit 0
    fi
fi
exit 0
EOF
chmod +x "$MOCK_AVAIL_DIR/apexm"

MOCK_APEXM_AVAIL_LOG="$TEST_TMPDIR/apexm_avail.log"
export MOCK_APEXM_AVAIL_LOG
export MOCK_AVAIL_APEX_DIR

cd "$TEST_AVAIL_PKG_DIR"
AVAIL_OUTPUT=$(APEX_SEARCH_PATH="$MOCK_AVAIL_APEX_DIR" PATH="$MOCK_AVAIL_DIR:$PATH" is_bionic=0 "$MAKEAPEX_BIN" --config "$TEST_CONF" -s --nobuild 2>&1 || true)
echo "$AVAIL_OUTPUT"

if ! echo "$AVAIL_OUTPUT" | grep -q "Installing available make dependencies"; then
    echo "FAILED: Expected 'Installing available make dependencies' when available makedepends found"
    exit 1
fi
if ! grep -q "MOCK_APEXM_INVOKED: -S " "$MOCK_APEXM_AVAIL_LOG"; then
    echo "FAILED: apexm -S was not called to install available makedepends"
    exit 1
fi
if ! grep "MOCK_APEXM_INVOKED: -S " "$MOCK_APEXM_AVAIL_LOG" | grep -q "libavail.so"; then
    echo "FAILED: libavail.so was not passed to apexm -S"
    exit 1
fi
if grep "MOCK_APEXM_INVOKED: -S " "$MOCK_APEXM_AVAIL_LOG" | grep -q "libunavail.so"; then
    echo "FAILED: libunavail.so should not be passed to apexm -S"
    exit 1
fi
if ! echo "$AVAIL_OUTPUT" | grep -q "WARNING:.*Unmet make dependencies:"; then
    echo "FAILED: Unavailable makedepends was not warned"
    exit 1
fi
if ! echo "$AVAIL_OUTPUT" | grep -q "libunavail.so"; then
    echo "FAILED: libunavail.so was not listed under unmet make dependencies"
    exit 1
fi
UNMET_SECTION=$(echo "$AVAIL_OUTPUT" | sed -n '/Unmet make dependencies:/,/Sources are ready./p')
if echo "$UNMET_SECTION" | grep -q "libavail.so"; then
    echo "FAILED: libavail.so was warned as unmet after successful installation"
    exit 1
fi
if ! echo "$AVAIL_OUTPUT" | grep -q "Sources are ready."; then
    echo "FAILED: makeapex did not continue successfully after installing available makedepends"
    exit 1
fi
# Test 9: Verify buildenv_apex_install handling of companion .dev APEX and lib64 vs lib prioritization
echo "[Test 9] buildenv_apex_install .dev APEX and lib64 vs lib prioritization"

TEST9_OUT=$(bash -c "
export MAKEAPEX_LIBRARY='$LIBMAKEAPEX_DIR'
source '$LIBMAKEAPEX_DIR/buildenv.sh'

MOCK_ROOT='$TEST_TMPDIR/mock_apex_root'
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev/include\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev/lib64/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev/lib/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev/share/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg/lib64/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg/lib/pkgconfig\"

export APEX_SEARCH_PATH=\"\$MOCK_ROOT\"
export CARCH=\"x86_64\"
arch=('x86_64')
makedepends=('com.test.pkg')

# 9a: 64-bit environment with companion .dev
CFLAGS=\"\"
CXXFLAGS=\"\"
LDFLAGS=\"\"
PKG_CONFIG_PATH=\"/usr/lib/pkgconfig\"

buildenv_apex_install

echo \"64BIT_CFLAGS=\$CFLAGS\"
echo \"64BIT_LDFLAGS=\$LDFLAGS\"
echo \"64BIT_PKG_CONFIG_PATH=\$PKG_CONFIG_PATH\"

# 9b: 32-bit environment
CARCH=\"armv7a\"
arch=('armv7a')
makedepends=('com.test.pkg')
CFLAGS=\"\"
CXXFLAGS=\"\"
LDFLAGS=\"\"
PKG_CONFIG_PATH=\"/usr/lib/pkgconfig\"

buildenv_apex_install

echo \"32BIT_LDFLAGS=\$LDFLAGS\"
echo \"32BIT_PKG_CONFIG_PATH=\$PKG_CONFIG_PATH\"
" 2>&1)

echo "$TEST9_OUT"

# Assert 64-bit include in CFLAGS
if ! echo "$TEST9_OUT" | grep -q "64BIT_CFLAGS=.*-I$TEST_TMPDIR/mock_apex_root/com.test.pkg.dev/include"; then
    echo "FAILED: 64BIT_CFLAGS missing companion .dev include path"
    exit 1
fi

# Assert 64-bit LDFLAGS ordering: lib64 must precede lib
LDFLAGS_LINE=$(echo "$TEST9_OUT" | grep "^64BIT_LDFLAGS=")
DEV_LIB64_POS=$(echo "$LDFLAGS_LINE" | awk '{print index($0, "com.test.pkg.dev/lib64")}')
DEV_LIB_POS=$(echo "$LDFLAGS_LINE" | awk '{print index($0, "com.test.pkg.dev/lib ")}')
if (( DEV_LIB64_POS == 0 || DEV_LIB_POS == 0 || DEV_LIB64_POS >= DEV_LIB_POS )); then
    echo "FAILED: In 64BIT_LDFLAGS, com.test.pkg.dev/lib64 must precede com.test.pkg.dev/lib"
    exit 1
fi

# Assert 64-bit PKG_CONFIG_PATH ordering:
# .dev/lib64/pkgconfig before .dev/lib/pkgconfig before .dev/share/pkgconfig before com.test.pkg/lib64 before /usr/lib/pkgconfig
PCP_LINE=$(echo "$TEST9_OUT" | grep "^64BIT_PKG_CONFIG_PATH=")
P_DEV_LIB64=$(echo "$PCP_LINE" | awk '{print index($0, "com.test.pkg.dev/lib64/pkgconfig")}')
P_DEV_LIB=$(echo "$PCP_LINE" | awk '{print index($0, "com.test.pkg.dev/lib/pkgconfig")}')
P_DEV_SHARE=$(echo "$PCP_LINE" | awk '{print index($0, "com.test.pkg.dev/share/pkgconfig")}')
P_MAIN_LIB64=$(echo "$PCP_LINE" | awk '{print index($0, "com.test.pkg/lib64/pkgconfig")}')
P_SYS=$(echo "$PCP_LINE" | awk '{print index($0, "/usr/lib/pkgconfig")}')

if (( P_DEV_LIB64 == 0 || P_DEV_LIB == 0 || P_DEV_LIB64 >= P_DEV_LIB )); then
    echo "FAILED: In PKG_CONFIG_PATH, .dev/lib64/pkgconfig must precede .dev/lib/pkgconfig"
    exit 1
fi
if (( P_DEV_SHARE == 0 || P_DEV_LIB >= P_DEV_SHARE )); then
    echo "FAILED: In PKG_CONFIG_PATH, .dev/lib/pkgconfig must precede .dev/share/pkgconfig"
    exit 1
fi
if (( P_MAIN_LIB64 == 0 || P_DEV_SHARE >= P_MAIN_LIB64 )); then
    echo "FAILED: In PKG_CONFIG_PATH, .dev paths must precede companion main package paths"
    exit 1
fi
if (( P_SYS == 0 || P_MAIN_LIB64 >= P_SYS )); then
    echo "FAILED: In PKG_CONFIG_PATH, apex paths must precede system /usr/lib/pkgconfig"
    exit 1
fi

# Assert 32-bit: lib64 must NOT be present
LDFLAGS_32_LINE=$(echo "$TEST9_OUT" | grep "^32BIT_LDFLAGS=")
PCP_32_LINE=$(echo "$TEST9_OUT" | grep "^32BIT_PKG_CONFIG_PATH=")
if echo "$LDFLAGS_32_LINE" | grep -q "lib64"; then
    echo "FAILED: 32BIT_LDFLAGS should not contain lib64"
    exit 1
fi
if echo "$PCP_32_LINE" | grep -q "lib64"; then
    echo "FAILED: 32BIT_PKG_CONFIG_PATH should not contain lib64"
    exit 1
fi
if ! echo "$LDFLAGS_32_LINE" | grep -q "lib"; then
    echo "FAILED: 32BIT_LDFLAGS should contain lib"
    exit 1
fi
if ! echo "$PCP_32_LINE" | grep -q "lib/pkgconfig"; then
    echo "FAILED: 32BIT_PKG_CONFIG_PATH should contain lib/pkgconfig"
    exit 1
fi

echo "PASSED: buildenv_apex_install correctly handles companion .dev APEX and prioritizes lib64 over lib"

echo "=== All tests PASSED successfully ==="

if [[ -n "$1" ]]; then
    touch "$1"
fi
