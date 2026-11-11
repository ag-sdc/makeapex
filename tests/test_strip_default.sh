#!/bin/bash
set -e

echo "=== Running makeapex default strip test suite ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${MESON_BUILD_ROOT:-$ROOT_DIR/build}"
MAKEAPEX_CONF_OUT="$BUILD_DIR/makeapex.conf"
LIBMAKEAPEX_DIR="$BUILD_DIR/src/libmakeapex"

export MAKEAPEX_LIBRARY="$LIBMAKEAPEX_DIR"

TEST_TMPDIR=$(mktemp -d /tmp/makeapex_strip_test.XXXXXX)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

CC="${CC:-$(command -v clang || command -v gcc || true)}"
if [[ -z $CC ]]; then
    echo "FAILED: Need clang or gcc to build test ELF fixtures"
    exit 1
fi

echo "[Test 1] Verify shipped makeapex.conf declares strip and staticlibs defaults"
if ! grep -q '^OPTIONS=(strip .*staticlibs' "$MAKEAPEX_CONF_OUT"; then
    echo "FAILED: Built makeapex.conf does not default to OPTIONS=(strip ... staticlibs ...)"
    exit 1
fi
echo "PASSED: Built makeapex.conf sets strip + staticlibs defaults"

echo "[Test 2] Verify fallback defaults when makeapex.conf omits OPTIONS and STRIP_*"
MINIMAL_CONF="$TEST_TMPDIR/minimal.conf"
cat > "$MINIMAL_CONF" << 'EOF'
CARCH="x86_64"
CHOST="x86_64-pc-linux-gnu"
PKGEXT=".apex"
SRCEXT=".src.tar.gz"
EOF

bash -c "
export MAKEAPEX_LIBRARY='$LIBMAKEAPEX_DIR'
for lib in '$LIBMAKEAPEX_DIR'/*.sh; do
    source \"\$lib\"
done
source '$LIBMAKEAPEX_DIR/util/config.sh'
source '$LIBMAKEAPEX_DIR/util/option.sh'

load_makeapex_config '$MINIMAL_CONF'
check_option 'strip' 'y' || { echo 'FAILED: strip not enabled by default'; exit 1; }
check_option 'staticlibs' 'y' || { echo 'FAILED: staticlibs not enabled by default'; exit 1; }
check_option 'debug' 'n' || { echo 'FAILED: debug should be disabled by default'; exit 1; }
[[ \"\$STRIP_BINARIES\" == '--strip-all' ]] || { echo 'FAILED: STRIP_BINARIES default mismatch'; exit 1; }
[[ \"\$STRIP_SHARED\" == '--strip-unneeded' ]] || { echo 'FAILED: STRIP_SHARED default mismatch'; exit 1; }
[[ \"\$STRIP_STATIC\" == '--strip-debug' ]] || { echo 'FAILED: STRIP_STATIC default mismatch'; exit 1; }
"
echo "PASSED: config.sh initializes strip, staticlibs, and STRIP_* defaults"

echo "[Test 3] Verify tidy_install strips binaries, hardlinks, .so, and static .a debug info by default"
SRC_DIR="$TEST_TMPDIR/src"
PKG_DEFAULT="$TEST_TMPDIR/pkg_default"
mkdir -p "$SRC_DIR" "$PKG_DEFAULT/bin" "$PKG_DEFAULT/lib64"

cat > "$SRC_DIR/foo.c" << 'EOF'
int foo_fn(int x) { return x + 42; }
EOF
cat > "$SRC_DIR/main.c" << 'EOF'
int foo_fn(int x);
int main(void) { return foo_fn(1) - 43; }
EOF

"$CC" -g -fPIC -shared "$SRC_DIR/foo.c" -o "$PKG_DEFAULT/lib64/libfoo.so"
"$CC" -g -fPIE -pie "$SRC_DIR/main.c" "$SRC_DIR/foo.c" -o "$PKG_DEFAULT/bin/foo_bin"
ln "$PKG_DEFAULT/bin/foo_bin" "$PKG_DEFAULT/bin/foo_hardlink"
"$CC" -g -c "$SRC_DIR/foo.c" -o "$SRC_DIR/foo.o"
ar rcs "$PKG_DEFAULT/lib64/libfoo.a" "$SRC_DIR/foo.o"

# Sanity: ensure pre-strip fixture has debug info
file "$PKG_DEFAULT/bin/foo_bin" | grep -q "with debug_info"
file "$PKG_DEFAULT/lib64/libfoo.so" | grep -q "with debug_info"

bash -c "
export MAKEAPEX_LIBRARY='$LIBMAKEAPEX_DIR'
for lib in '$LIBMAKEAPEX_DIR'/*.sh; do
    source \"\$lib\"
done
source '$LIBMAKEAPEX_DIR/util/util.sh'
source '$LIBMAKEAPEX_DIR/util/config.sh'

pkgbase='com.test.striptest'
pkgname=('com.test.striptest')
pkgdirbase='$TEST_TMPDIR'
pkgnamedir='$TEST_TMPDIR/pkgnamedir_default'
pkgdir='$PKG_DEFAULT'
pkgdirprefix='$PKG_DEFAULT'
srcdir='$SRC_DIR'
options=()
mkdir -p \"\$pkgnamedir\"

load_makeapex_config '$MINIMAL_CONF'
tidy_install || exit 1
"

file "$PKG_DEFAULT/bin/foo_bin" | grep -q "stripped"
! file "$PKG_DEFAULT/bin/foo_bin" | grep -qE "not stripped|with debug_info"
file "$PKG_DEFAULT/bin/foo_hardlink" | grep -q "stripped"
file "$PKG_DEFAULT/lib64/libfoo.so" | grep -q "stripped"
! file "$PKG_DEFAULT/lib64/libfoo.so" | grep -qE "not stripped|with debug_info"
[[ -f "$PKG_DEFAULT/lib64/libfoo.a" ]]
! readelf -S "$PKG_DEFAULT/lib64/libfoo.a" | grep -q '\.debug_info'
echo "PASSED: Default tidy_install stripped binaries, hardlinks, .so, and .a debug info while keeping .a"

echo "[Test 4] Verify APEX options=('!strip') opts out cleanly"
PKG_NOSTRIP="$TEST_TMPDIR/pkg_nostrip"
mkdir -p "$PKG_NOSTRIP/bin"
"$CC" -g -fPIE -pie "$SRC_DIR/main.c" "$SRC_DIR/foo.c" -o "$PKG_NOSTRIP/bin/foo_bin"

bash -c "
export MAKEAPEX_LIBRARY='$LIBMAKEAPEX_DIR'
for lib in '$LIBMAKEAPEX_DIR'/*.sh; do
    source \"\$lib\"
done
source '$LIBMAKEAPEX_DIR/util/util.sh'
source '$LIBMAKEAPEX_DIR/util/config.sh'

pkgbase='com.test.nostrip'
pkgname=('com.test.nostrip')
pkgdirbase='$TEST_TMPDIR'
pkgnamedir='$TEST_TMPDIR/pkgnamedir_nostrip'
pkgdir='$PKG_NOSTRIP'
pkgdirprefix='$PKG_NOSTRIP'
srcdir='$SRC_DIR'
options=('!strip')
mkdir -p \"\$pkgnamedir\"

load_makeapex_config '$MINIMAL_CONF'
tidy_install || exit 1
"

file "$PKG_NOSTRIP/bin/foo_bin" | grep -q "not stripped"
echo "PASSED: options=('!strip') preserves debug symbols"

echo "[Test 5] Verify end-to-end makeapex packaging strips ELFs inside \$pkgdirprefix APEX payload"
E2E_DESTDIR="$TEST_TMPDIR/destdir"
E2E_DIR="$TEST_TMPDIR/e2e_pkg"
E2E_EXT="$TEST_TMPDIR/e2e_extract"
mkdir -p "$E2E_DIR" "$E2E_EXT/payload"
DESTDIR="$E2E_DESTDIR" meson install -C "$BUILD_DIR" --no-rebuild --quiet
cp "$SRC_DIR/foo.c" "$SRC_DIR/main.c" "$E2E_DIR/"

cat > "$E2E_DIR/APEXBUILD" << 'EOF'
pkgname=com.test.strip.e2e
pkgver=1.0.0
pkgrel=1
arch=('x86_64')
payload_fs=erofs

build() {
  local cc="${CC:-clang}"
  "$cc" -g -fPIC -shared "$startdir/foo.c" -o libfoo.so
  "$cc" -g -fPIE -pie "$startdir/main.c" "$startdir/foo.c" -o foo_bin
  "$cc" -g -c "$startdir/foo.c" -o foo.o
  ar rcs libfoo.a foo.o
}

package() {
  install -Dm755 foo_bin "$pkgdirprefix/bin/foo_bin"
  install -Dm755 libfoo.so "$pkgdirprefix/lib/libfoo.so"
  install -Dm644 libfoo.a "$pkgdirprefix/lib/libfoo.a"
}
EOF

(cd "$E2E_DIR" && CC="$CC" MAKEAPEX_LIBRARY="$E2E_DESTDIR/usr/share/makeapex" "$E2E_DESTDIR/usr/bin/makeapex" -d --config "$MINIMAL_CONF" -f)
APEX_OUT="$E2E_DIR/com.test.strip.e2e.apex"
[[ -f "$APEX_OUT" ]] || { echo "FAILED: Missing $APEX_OUT"; exit 1; }
unzip -q "$APEX_OUT" apex_payload.img -d "$E2E_EXT"
fsck.erofs --extract="$E2E_EXT/payload" "$E2E_EXT/apex_payload.img" >/dev/null

file "$E2E_EXT/payload/bin/foo_bin" | grep -q "stripped"
! file "$E2E_EXT/payload/bin/foo_bin" | grep -qE "not stripped|with debug_info"
file "$E2E_EXT/payload/lib/libfoo.so" | grep -q "stripped"
! file "$E2E_EXT/payload/lib/libfoo.so" | grep -qE "not stripped|with debug_info"
[[ -f "$E2E_EXT/payload/lib/libfoo.a" ]]
! readelf -S "$E2E_EXT/payload/lib/libfoo.a" | grep -q '\.debug_info'
echo "PASSED: End-to-end makeapex .apex payload has stripped bin/so and preserved/debug-stripped .a"

echo "=== All default strip tests PASSED successfully ==="
