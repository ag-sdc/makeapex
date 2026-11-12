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
# Test 9: Verify buildenv_apex_install scans standard candidate only (avoiding .dev auto-expansion / .dev.dev) and prioritizes lib64/libx32 over lib
echo "[Test 9] buildenv_apex_install standard-only candidate and lib64/libx32 vs lib prioritization"

TEST9_OUT=$(bash -c "
export MAKEAPEX_LIBRARY='$LIBMAKEAPEX_DIR'
source '$LIBMAKEAPEX_DIR/buildenv.sh'

MOCK_ROOT='$TEST_TMPDIR/mock_apex_root'
mkdir -p \"\$MOCK_ROOT/com.test.pkg/include\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg/lib64/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg/lib/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg/libx32/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg/share/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev/include\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev/lib64/pkgconfig\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev.dev/include\"
mkdir -p \"\$MOCK_ROOT/com.test.pkg.dev.dev/lib64/pkgconfig\"

export APEX_SEARCH_PATH=\"\$MOCK_ROOT\"
export CARCH=\"x86_64\"
arch=('x86_64')
depends=()
makedepends=('com.test.pkg')
checkdepends=()

# 9a: 64-bit environment with standard package only (must NOT scan .dev companion)
CFLAGS=\"\"
CXXFLAGS=\"\"
LDFLAGS=\"\"
PKG_CONFIG_PATH=\"/usr/lib/pkgconfig\"

buildenv_apex_install

echo \"64BIT_CFLAGS=\$CFLAGS\"
echo \"64BIT_LDFLAGS=\$LDFLAGS\"
echo \"64BIT_PKG_CONFIG_PATH=\$PKG_CONFIG_PATH\"

# 9b: Explicit .dev package in makedepends (must scan .dev only, NOT base or .dev.dev)
makedepends=('com.test.pkg.dev')
CFLAGS=\"\"
CXXFLAGS=\"\"
LDFLAGS=\"\"
PKG_CONFIG_PATH=\"/usr/lib/pkgconfig\"

buildenv_apex_install

echo \"DEV_ONLY_CFLAGS=\$CFLAGS\"
echo \"DEV_ONLY_PKG_CONFIG_PATH=\$PKG_CONFIG_PATH\"

# 9c: 32-bit environment
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

# 9d: x32 environment (libx32 prioritized over lib, lib64 excluded)
CARCH=\"x32\"
arch=('x32')
makedepends=('com.test.pkg')
CFLAGS=\"\"
CXXFLAGS=\"\"
LDFLAGS=\"\"
PKG_CONFIG_PATH=\"/usr/lib/pkgconfig\"

buildenv_apex_install

echo \"X32_LDFLAGS=\$LDFLAGS\"
echo \"X32_PKG_CONFIG_PATH=\$PKG_CONFIG_PATH\"
" 2>&1)

echo "$TEST9_OUT"

# 9a assertions: standard candidate only, no .dev
CFLAGS_LINE=$(echo "$TEST9_OUT" | grep "^64BIT_CFLAGS=")
if ! echo "$CFLAGS_LINE" | grep -q -- "-I$TEST_TMPDIR/mock_apex_root/com.test.pkg/include"; then
    echo "FAILED: 64BIT_CFLAGS missing standard package include path"
    exit 1
fi
if echo "$CFLAGS_LINE" | grep -q "com.test.pkg.dev"; then
    echo "FAILED: 64BIT_CFLAGS should not scan .dev companion when makedepends only lists com.test.pkg"
    exit 1
fi

LDFLAGS_LINE=$(echo "$TEST9_OUT" | grep "^64BIT_LDFLAGS=")
MAIN_LIB64_POS=$(echo "$LDFLAGS_LINE" | awk '{print index($0, "com.test.pkg/lib64")}')
MAIN_LIB_POS=$(echo "${LDFLAGS_LINE} " | awk '{print index($0, "com.test.pkg/lib ")}')
if (( MAIN_LIB64_POS == 0 || MAIN_LIB_POS == 0 || MAIN_LIB64_POS >= MAIN_LIB_POS )); then
    echo "FAILED: In 64BIT_LDFLAGS, com.test.pkg/lib64 must precede com.test.pkg/lib"
    exit 1
fi

PCP_LINE=$(echo "$TEST9_OUT" | grep "^64BIT_PKG_CONFIG_PATH=")
if echo "$PCP_LINE" | grep -q "com.test.pkg.dev"; then
    echo "FAILED: 64BIT_PKG_CONFIG_PATH should not include com.test.pkg.dev"
    exit 1
fi
P_MAIN_LIB64=$(echo "$PCP_LINE" | awk '{print index($0, "com.test.pkg/lib64/pkgconfig")}')
P_MAIN_LIB=$(echo "$PCP_LINE" | awk '{print index($0, "com.test.pkg/lib/pkgconfig")}')
P_MAIN_SHARE=$(echo "$PCP_LINE" | awk '{print index($0, "com.test.pkg/share/pkgconfig")}')
P_SYS=$(echo "$PCP_LINE" | awk '{print index($0, "/usr/lib/pkgconfig")}')

if (( P_MAIN_LIB64 == 0 || P_MAIN_LIB == 0 || P_MAIN_LIB64 >= P_MAIN_LIB )); then
    echo "FAILED: In PKG_CONFIG_PATH, com.test.pkg/lib64/pkgconfig must precede com.test.pkg/lib/pkgconfig"
    exit 1
fi
if (( P_MAIN_SHARE == 0 || P_MAIN_LIB >= P_MAIN_SHARE )); then
    echo "FAILED: In PKG_CONFIG_PATH, com.test.pkg/lib/pkgconfig must precede com.test.pkg/share/pkgconfig"
    exit 1
fi
if (( P_SYS == 0 || P_MAIN_SHARE >= P_SYS )); then
    echo "FAILED: In PKG_CONFIG_PATH, apex paths must precede system /usr/lib/pkgconfig"
    exit 1
fi

# 9b assertions: explicit .dev only, no .dev.dev or non-.dev base
DEV_PCP_LINE=$(echo "$TEST9_OUT" | grep "^DEV_ONLY_PKG_CONFIG_PATH=")
if ! echo "$DEV_PCP_LINE" | grep -q "com.test.pkg.dev/lib64/pkgconfig"; then
    echo "FAILED: DEV_ONLY_PKG_CONFIG_PATH missing com.test.pkg.dev/lib64/pkgconfig"
    exit 1
fi
if echo "$DEV_PCP_LINE" | grep -q "com.test.pkg/lib"; then
    echo "FAILED: DEV_ONLY_PKG_CONFIG_PATH should not scan base com.test.pkg"
    exit 1
fi
if echo "$DEV_PCP_LINE" | grep -q "com.test.pkg.dev.dev"; then
    echo "FAILED: DEV_ONLY_PKG_CONFIG_PATH must never touch com.test.pkg.dev.dev"
    exit 1
fi

# 9c assertions: 32-bit must NOT contain lib64
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

# 9d assertions: x32 prioritizes libx32 over lib
X32_PCP_LINE=$(echo "$TEST9_OUT" | grep "^X32_PKG_CONFIG_PATH=")
P_X32_LIB=$(echo "$X32_PCP_LINE" | awk '{print index($0, "com.test.pkg/libx32/pkgconfig")}')
P_X32_BASE=$(echo "$X32_PCP_LINE" | awk '{print index($0, "com.test.pkg/lib/pkgconfig")}')
if (( P_X32_LIB == 0 || P_X32_BASE == 0 || P_X32_LIB >= P_X32_BASE )); then
    echo "FAILED: On x32, libx32/pkgconfig must precede lib/pkgconfig"
    exit 1
fi

echo "PASSED: buildenv_apex_install scans standard candidate only (no .dev.dev) and prioritizes lib64/libx32 over lib"

# Test 10: End-to-end build() receives PKG_CONFIG_PATH, CFLAGS, LDFLAGS for depends=('libz.so') + makedepends=('pc:zlib')
echo "[Test 10] End-to-end PKG_CONFIG_PATH propagation to build() with depends=libz.so and makedepends=pc:zlib"
TEST10_ROOT="$TEST_TMPDIR/test10_apex"
TEST10_PKG="$TEST_TMPDIR/test10_pkg"
mkdir -p "$TEST10_ROOT/org.blisslabs.ag.zlib.ng/lib64"
mkdir -p "$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev/include"
mkdir -p "$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev/lib64/pkgconfig"
mkdir -p "$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev.dev/lib64/pkgconfig"
mkdir -p "$TEST10_PKG"

touch "$TEST10_ROOT/org.blisslabs.ag.zlib.ng/lib64/libz.so"
touch "$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev/include/zlib.h"
cat > "$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev/lib64/pkgconfig/zlib.pc" << 'EOF'
Name: zlib
Description: zlib compression library
Version: 1.3.1
Libs: -lz
Cflags: -I${pcfiledir}/../../include
EOF
cat > "$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev.dev/lib64/pkgconfig/trap.pc" << 'EOF'
Name: trap
Description: trap
Version: 9.9.9
EOF

TEST10_CONF="$TEST_TMPDIR/test10_makeapex.conf"
cat "$BUILD_DIR/makeapex.conf" > "$TEST10_CONF"
echo "PACMAN_AUTH=(false)" >> "$TEST10_CONF"

cat > "$TEST10_PKG/APEXBUILD" << 'EOF'
pkgname=com.test.pczlib
pkgver=1.0.0
pkgrel=1
arch=('x86_64')
payload_fs=erofs
options=('!buildflags')
depends=('libz.so')
makedepends=('pc:zlib')

build() {
	echo "BUILD_PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
	echo "BUILD_CFLAGS=$CFLAGS"
	echo "BUILD_LDFLAGS=$LDFLAGS"
	if command -v pkg-config >/dev/null 2>&1; then
		echo "BUILD_PC_ZLIB_VER=$(pkg-config --modversion zlib)"
	fi
}

package() {
	mkdir -p "$pkgdir/usr"
}
EOF

TEST10_BIN="$TEST_TMPDIR/test10_bin"
mkdir -p "$TEST10_BIN"
if [[ -n "${APEXM_BIN:-}" && -x "$APEXM_BIN" ]]; then
    ln -sf "$APEXM_BIN" "$TEST10_BIN/apexm"
elif [[ -x "$BUILD_DIR/../../../apexm/build/apexm" ]]; then
    ln -sf "$BUILD_DIR/../../../apexm/build/apexm" "$TEST10_BIN/apexm"
else
    cat > "$TEST10_BIN/apexm" << 'EOF'
#!/bin/bash
if [[ "$1" == "local" && "$2" == "--name" ]]; then
    q="$3"
    IFS=: read -r -a roots <<< "${APEX_SEARCH_PATH:-}"
    if [[ "$q" == pc:* ]]; then
        pc="${q#pc:}.pc"
        for r in "${roots[@]}"; do
            for f in "$r"/*/lib*/pkgconfig/"$pc" "$r"/*/share/pkgconfig/"$pc"; do
                if [[ -e "$f" ]]; then
                    rel="${f#"$r"/}"
                    echo "${rel%%/*}"
                    exit 0
                fi
            done
        done
    elif [[ "$q" == *.so* ]]; then
        for r in "${roots[@]}"; do
            for f in "$r"/*/lib*/"$q"; do
                if [[ -e "$f" ]]; then
                    rel="${f#"$r"/}"
                    echo "${rel%%/*}"
                    exit 0
                fi
            done
        done
    fi
fi
exit 1
EOF
    chmod +x "$TEST10_BIN/apexm"
fi

cd "$TEST10_PKG"
TEST10_OUT=$(PATH="$TEST10_BIN:$PATH" APEX_SEARCH_PATH="$TEST10_ROOT" PKG_CONFIG_PATH="" "$MAKEAPEX_BIN" --config "$TEST10_CONF" --noarchive -f 2>&1)
echo "$TEST10_OUT"

if echo "$TEST10_OUT" | grep -q "Unmet make dependencies:"; then
    echo "FAILED: pc:zlib should be detected as satisfied in APEX_SEARCH_PATH"
    exit 1
fi
if ! echo "$TEST10_OUT" | grep "^BUILD_PKG_CONFIG_PATH=" | grep -q "$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev/lib64/pkgconfig"; then
    echo "FAILED: PKG_CONFIG_PATH inside build() did not contain org.blisslabs.ag.zlib.ng.dev/lib64/pkgconfig"
    exit 1
fi
if echo "$TEST10_OUT" | grep "^BUILD_PKG_CONFIG_PATH=" | grep -q "org.blisslabs.ag.zlib.ng.dev.dev"; then
    echo "FAILED: PKG_CONFIG_PATH inside build() should never include org.blisslabs.ag.zlib.ng.dev.dev"
    exit 1
fi
if ! echo "$TEST10_OUT" | grep "^BUILD_CFLAGS=" | grep -q -- "-I$TEST10_ROOT/org.blisslabs.ag.zlib.ng.dev/include"; then
    echo "FAILED: CFLAGS inside build() did not contain org.blisslabs.ag.zlib.ng.dev/include"
    exit 1
fi
if ! echo "$TEST10_OUT" | grep "^BUILD_LDFLAGS=" | grep -q -- "-L$TEST10_ROOT/org.blisslabs.ag.zlib.ng/lib64"; then
    echo "FAILED: LDFLAGS inside build() did not contain org.blisslabs.ag.zlib.ng/lib64 from depends=libz.so"
    exit 1
fi
if command -v pkg-config >/dev/null 2>&1 && ! echo "$TEST10_OUT" | grep -q "^BUILD_PC_ZLIB_VER=1.3.1$"; then
    echo "FAILED: pkg-config --modversion zlib inside build() did not resolve 1.3.1"
    exit 1
fi
echo "PASSED: End-to-end PKG_CONFIG_PATH, CFLAGS, and LDFLAGS reached build() for depends=libz.so and makedepends=pc:zlib"

# Test 11: Partial unresolvable deps still export PKG_CONFIG_PATH, head -n 1 picks first provider, cmake dir not matched, BUILDENV=(apex_install) lints cleanly, and apexm -S splits -l vs pkg targets
echo "[Test 11] Partial PKG_CONFIG_PATH export, head -n 1 provider selection, cmake dir guard, BUILDENV lint, apexm -S flag split"
TEST11_ROOT="$TEST_TMPDIR/test11_apex"
TEST11_PKG="$TEST_TMPDIR/test11_pkg"
TEST11_BIN="$TEST_TMPDIR/test11_bin"
mkdir -p "$TEST11_ROOT/org.blisslabs.ag.zlib.ng.dev/lib64/pkgconfig"
mkdir -p "$TEST11_ROOT/org.blisslabs.ag.ext.zlib.dev/lib64/pkgconfig"
mkdir -p "$TEST11_ROOT/org.blisslabs.ag.fmtlib.dev/lib/cmake"
mkdir -p "$TEST11_ROOT/org.blisslabs.ag.fmtlib.dev/lib64/pkgconfig"
mkdir -p "$TEST11_PKG" "$TEST11_BIN"

cat > "$TEST11_ROOT/org.blisslabs.ag.zlib.ng.dev/lib64/pkgconfig/zlib.pc" << 'EOF'
Name: zlib
Description: zlib
Version: 1.3.1
EOF
cat > "$TEST11_ROOT/org.blisslabs.ag.fmtlib.dev/lib64/pkgconfig/fmt.pc" << 'EOF'
Name: fmt
Description: fmt
Version: 10.0.0
EOF

TEST11_APEXM_LOG="$TEST_TMPDIR/test11_apexm.log"
cat > "$TEST11_BIN/apexm" << EOF
#!/bin/bash
echo "CALL:\$*" >> "$TEST11_APEXM_LOG"
if [[ "\$1" == "local" && "\$2" == "--name" ]]; then
    if [[ "\$3" == "pc:zlib" ]]; then
        echo "org.blisslabs.ag.zlib.ng.dev"
        echo "org.blisslabs.ag.ext.zlib.dev"
        exit 0
    fi
    exit 1
elif [[ "\$1" == "-Ss" ]]; then
    last="\${@: -1}"
    has_l=0
    for a in "\$@"; do
        [[ "\$a" == "-l" ]] && has_l=1
    done
    if ((has_l)) && [[ "\$last" == "libmockfoo.so" ]]; then
        exit 0
    elif ((!has_l)) && [[ "\$last" == "mockpkg.dev" ]]; then
        exit 0
    fi
    exit 1
elif [[ "\$1" == "-S" ]]; then
    exit 0
fi
exit 1
EOF
chmod +x "$TEST11_BIN/apexm"

TEST11_CONF="$TEST_TMPDIR/test11_makeapex.conf"
sed 's/^BUILDENV=(.*)$/BUILDENV=(apex_install color check !sign)/' "$BUILD_DIR/makeapex.conf" > "$TEST11_CONF"
echo "PACMAN_AUTH=()" >> "$TEST11_CONF"

cat > "$TEST11_PKG/APEXBUILD" << 'EOF'
pkgname=com.test.partial
pkgver=1.0.0
pkgrel=1
arch=('x86_64')
payload_fs=erofs
options=('!buildflags')
makedepends=('cmake' 'pc:zlib' 'pc:doesnotexist' 'unresolvable.pkg' 'libmockfoo.so' 'mockpkg.dev')

build() {
	echo "TEST11_PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
}

package() {
	mkdir -p "$pkgdir/usr"
}
EOF

cd "$TEST11_PKG"
TEST11_OUT=$(PATH="$TEST11_BIN:$PATH" APEX_SEARCH_PATH="$TEST11_ROOT" PKG_CONFIG_PATH="" "$MAKEAPEX_BIN" --config "$TEST11_CONF" -s --noarchive -f 2>&1)
echo "$TEST11_OUT"

if echo "$TEST11_OUT" | grep -q "unknown option 'apex_install'"; then
    echo "FAILED: BUILDENV=(apex_install ...) rejected by lint_buildenv"
    exit 1
fi
TEST11_PCP=$(echo "$TEST11_OUT" | grep "^TEST11_PKG_CONFIG_PATH=")
if ! echo "$TEST11_PCP" | grep -q "$TEST11_ROOT/org.blisslabs.ag.zlib.ng.dev/lib64/pkgconfig"; then
    echo "FAILED: Resolvable pc:zlib should still be exported when other makedepends are unresolvable"
    exit 1
fi
if echo "$TEST11_PCP" | grep -q "org.blisslabs.ag.ext.zlib.dev"; then
    echo "FAILED: apexm | head -n 1 should select only the first provider"
    exit 1
fi
if echo "$TEST11_PCP" | grep -q "org.blisslabs.ag.fmtlib.dev"; then
    echo "FAILED: cmake dep should not match lib/cmake directory in org.blisslabs.ag.fmtlib.dev"
    exit 1
fi
if ! grep -q "^CALL:-S -l .*libmockfoo\.so" "$TEST11_APEXM_LOG"; then
    echo "FAILED: Expected apexm -S -l for libmockfoo.so"
    exit 1
fi
PKG_CALL=$(grep "^CALL:-S " "$TEST11_APEXM_LOG" | grep "mockpkg\.dev" | head -n 1 || true)
if [[ -z "$PKG_CALL" ]] || echo "$PKG_CALL" | grep -q " -l "; then
    echo "FAILED: Expected apexm -S without -l for mockpkg.dev, got: $PKG_CALL"
    exit 1
fi
echo "PASSED: Partial PKG_CONFIG_PATH export, head -n 1 provider selection, cmake dir guard, BUILDENV lint, apexm -S flag split"

# Test 12: 60-linkerconfig keeps libdummy_<pkgname> only and removes libdummy_<type>
echo "[Test 12] 60-linkerconfig emits libdummy_<pkgname> only (no libdummy_<type>)"
TEST12_DIR="$TEST_TMPDIR/test12_linker"
mkdir -p "$TEST12_DIR/pkg/bin" "$TEST12_DIR/pkg/share/terminfo" "$TEST12_DIR/pkg/include" "$TEST12_DIR/pkg/lib/pkgconfig" "$TEST12_DIR/pkg/etc"
printf '#!/bin/sh\necho hi\n' > "$TEST12_DIR/pkg/bin/mytool"
chmod +x "$TEST12_DIR/pkg/bin/mytool"
touch "$TEST12_DIR/pkg/include/foo.h" "$TEST12_DIR/pkg/lib/pkgconfig/foo.pc"

TEST12_OUT=$(bash -c "
export MAKEAPEX_LIBRARY='$LIBMAKEAPEX_DIR'
source '$LIBMAKEAPEX_DIR/tidy/60-linkerconfig.sh'
pkgdir='$TEST12_DIR/pkg'
pkgdirprefix='$TEST12_DIR/pkg'
package_name='my-test-pkg'
pkgbase='my-test-pkg'
depends=()
provides=()
req_libs=()
prov_libs=()
parse_depends
parse_dump_object
gen_provides
printf 'PROV=%s\n' \"\${prov_libs[@]}\"
" 2>&1)
echo "$TEST12_OUT"

if ! echo "$TEST12_OUT" | grep -q "^PROV=libdummy_my_test_pkg\.so$"; then
    echo "FAILED: Expected libdummy_my_test_pkg.so in prov_libs"
    exit 1
fi
for forbidden in libdummy_binary_ libdummy_shared_ libdummy_headers_ libdummy_pkgconfig_ libdummy_linux_ libdummy_linuxheaders_ libdummy_firmware_; do
    if echo "$TEST12_OUT" | grep -q "^PROV=$forbidden"; then
        echo "FAILED: Unexpected libdummy_<type> entry emitted: $forbidden"
        exit 1
    fi
done
echo "PASSED: 60-linkerconfig emits libdummy_<pkgname> only"

echo "=== All tests PASSED successfully ==="

if [[ -n "$1" ]]; then
    touch "$1"
fi
