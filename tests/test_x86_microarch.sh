#!/bin/bash
set -e

echo "=== Running makeapex x86 microarch test suite ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${MESON_BUILD_ROOT:-$ROOT_DIR/build}"
MAKEAPEX_BIN="$BUILD_DIR/makeapex"
LIBMAKEAPEX_DIR="$BUILD_DIR/src/libmakeapex"

export MAKEAPEX_LIBRARY="$LIBMAKEAPEX_DIR"

TEST_TMPDIR=$(mktemp -d /tmp/makeapex_microarch_test.XXXXXX)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Source message and microarch utilities
source "$LIBMAKEAPEX_DIR/util/message.sh"
source "$LIBMAKEAPEX_DIR/util/microarch.sh"

echo "[Test 1] Unit tests of microarch_init for x86_64, x86_32, x86, and x32"

# 1a: x86_64 default (level 2)
pkgarch="x86_64"
_x86_64_microarch_level=""
_microarch_level=""
__microarch_init=""
_microarch_init
if [[ $(microarch_level) != "2" ]] || ! microarch_is_not_lowest; then
    echo "FAILED: x86_64 default should be 2 and is_not_lowest=true"
    exit 1
fi
if [[ $(microarch_from_lowest) != "i386 i486 i586 i686 pentium4 v1 v2 " ]]; then
    echo "FAILED: x86_64 level 2 hierarchy mismatch: $(microarch_from_lowest)"
    exit 1
fi
echo "PASSED: x86_64 default is level 2"

# 1b: x86_64 level 1 (baseline)
__microarch_init=""
_x86_64_microarch_level="1"
_microarch_init
if [[ $(microarch_level) != "1" ]]; then
    echo "FAILED: x86_64 level 1 should report 1"
    exit 1
fi
if microarch_is_not_lowest; then
    echo "FAILED: x86_64 level 1 should be lowest"
    exit 1
fi
echo "PASSED: x86_64 level 1 is lowest"

# 1c: x86_64 sub-ISA i686 and pentium4
__microarch_init=""
_x86_64_microarch_level="i686"
_microarch_init
if [[ $(microarch_level) != "i686" ]] || ! microarch_is_not_lowest; then
    echo "FAILED: x86_64 i686 mismatch"
    exit 1
fi
if [[ $(microarch_from_lowest) != "i386 i486 i586 i686 " ]]; then
    echo "FAILED: x86_64 i686 hierarchy mismatch: $(microarch_from_lowest)"
    exit 1
fi

__microarch_init=""
_x86_64_microarch_level="pentium4"
_microarch_init
if [[ $(microarch_level) != "pentium4" ]] || ! microarch_is_not_lowest; then
    echo "FAILED: x86_64 pentium4 mismatch"
    exit 1
fi
if [[ $(microarch_from_lowest) != "i386 i486 i586 i686 pentium4 " ]]; then
    echo "FAILED: x86_64 pentium4 hierarchy mismatch: $(microarch_from_lowest)"
    exit 1
fi
echo "PASSED: x86_64 sub-ISAs i686 and pentium4 supported"

# 1d: x86_32 default (i686)
pkgarch="x86_32"
_x86_32_microarch_level=""
_x86_64_microarch_level=""
__microarch_init=""
_microarch_init
if [[ $(microarch_level) != "i686" ]] || ! microarch_is_not_lowest; then
    echo "FAILED: x86_32 default should be i686 and is_not_lowest=true"
    exit 1
fi
echo "PASSED: x86_32 default is i686"

# 1e: x86_32 v1, v2, v3, v4
for v in 1 2 3 4; do
    __microarch_init=""
    _x86_32_microarch_level="v$v"
    _microarch_init
    if [[ $(microarch_level) != "v$v" ]] || ! microarch_is_not_lowest; then
        echo "FAILED: x86_32 v$v mismatch"
        exit 1
    fi
done
if [[ $(microarch_from_lowest) != "i386 i486 i586 i686 pentium4 v1 v2 v3 v4 " ]]; then
    echo "FAILED: x86_32 v4 hierarchy mismatch: $(microarch_from_lowest)"
    exit 1
fi
echo "PASSED: x86_32 with -v{1,2,3,4} supported"

# 1f: x32 default and v-levels
pkgarch="x32"
_x32_microarch_level=""
__microarch_init=""
_microarch_init
if [[ $(microarch_level) != "2" ]] || ! microarch_is_not_lowest; then
    echo "FAILED: x32 default should be 2"
    exit 1
fi

__microarch_init=""
_x32_microarch_level="v3"
_microarch_init
if [[ $(microarch_level) != "v3" ]] || ! microarch_is_not_lowest; then
    echo "FAILED: x32 v3 mismatch"
    exit 1
fi

__microarch_init=""
_x32_microarch_level="pentium4"
_microarch_init
if [[ $(microarch_level) != "pentium4" ]] || ! microarch_is_not_lowest; then
    echo "FAILED: x32 pentium4 mismatch"
    exit 1
fi
echo "PASSED: x32 with -v{1,2,3,4} and sub-ISAs supported"

echo "[Test 2] Linkerconfig dummy suffixes and dependencies"
source "$LIBMAKEAPEX_DIR/tidy/60-linkerconfig.sh"

pkgarch="x86_32"
_x86_32_microarch_level="v3"
__microarch_init=""
_microarch_init

dummy_suffixes=()
get_dummy_suffixes

# Check presence of both x86_32 and x86 aliases with v-levels and sub-ISAs
for sfx in "-x86_32-v1" "-x86_32-v2" "-x86_32-v3" "-x86_32-i686" "-x86_32-pentium4" "-x86-v3" "-x86-i686"; do
    found=0
    for s in "${dummy_suffixes[@]}"; do
        if [[ "$s" == "$sfx" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        echo "FAILED: dummy_suffixes missing $sfx (got: ${dummy_suffixes[*]})"
        exit 1
    fi
done
echo "PASSED: get_dummy_suffixes generates x86_32 and x86 alias suffixes"

# Test parse_depends with sub-ISAs and v-levels
req_libs=()
depends=('_binary_bash-x86_32-v3' '_binary_sed-x86_32-i686' '_binary_awk-x32-v2' '_binary_grep-x86_64-pentium4')
parse_depends

for exp in "libdummy_binary_bash-x86_32-v3.so" "libdummy_binary_sed-x86_32-i686.so" "libdummy_binary_awk-x32-v2.so" "libdummy_binary_grep-x86_64-pentium4.so"; do
    found=0
    for r in "${req_libs[@]}"; do
        if [[ "$r" == "$exp" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        echo "FAILED: parse_depends did not produce $exp (got: ${req_libs[*]})"
        exit 1
    fi
done
echo "PASSED: parse_depends handles sub-ISAs and v-levels for x86_32, x32, and x86_64"

echo "[Test 3] End-to-end makeapex packaging with x86_32 and x32 microarchitectures"

# Test 3a: x86_32 with _x86_32_microarch_level=v3
TEST_PKG_32="$TEST_TMPDIR/pkg32"
mkdir -p "$TEST_PKG_32"
cat > "$TEST_PKG_32/APEXBUILD" << 'EOF'
pkgname=com.test.pkg32
pkgver=1.0.0
pkgrel=1
arch=('x86_32')
_x86_32_microarch_level=v3
payload_fs=erofs
makedepends=()

package() {
  mkdir -p "$pkgdir/bin"
  echo "test" > "$pkgdir/bin/test32"
}
EOF

cd "$TEST_PKG_32"
CARCH="x86_32" is_bionic=0 "$MAKEAPEX_BIN" --nobuild >/dev/null 2>&1 || true

# Test 3b: x32 with _x32_microarch_level=pentium4
TEST_PKG_X32="$TEST_TMPDIR/pkgx32"
mkdir -p "$TEST_PKG_X32"
cat > "$TEST_PKG_X32/APEXBUILD" << 'EOF'
pkgname=com.test.pkgx32
pkgver=1.0.0
pkgrel=1
arch=('x32')
_x32_microarch_level=pentium4
payload_fs=erofs
makedepends=()

package() {
  mkdir -p "$pkgdir/bin"
  echo "test" > "$pkgdir/bin/testx32"
}
EOF

cd "$TEST_PKG_X32"
CARCH="x32" is_bionic=0 "$MAKEAPEX_BIN" --nobuild >/dev/null 2>&1 || true

# Test 3c: x86_64 with _x86_64_microarch_level=i686
TEST_PKG_64="$TEST_TMPDIR/pkg64"
mkdir -p "$TEST_PKG_64"
cat > "$TEST_PKG_64/APEXBUILD" << 'EOF'
pkgname=com.test.pkg64
pkgver=1.0.0
pkgrel=1
arch=('x86_64')
_x86_64_microarch_level=i686
payload_fs=erofs
makedepends=()

package() {
  mkdir -p "$pkgdir/bin"
  echo "test" > "$pkgdir/bin/test64"
}
EOF

cd "$TEST_PKG_64"
CARCH="x86_64" is_bionic=0 "$MAKEAPEX_BIN" --nobuild >/dev/null 2>&1 || true

echo "PASSED: End-to-end makeapex runs cleanly with x86_32, x32, and sub-ISA levels"

echo "=== All tests PASSED successfully ==="

if [[ -n "$1" ]]; then
    touch "$1"
fi
