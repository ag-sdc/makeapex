#!/bin/bash
set -e

echo "=== Running makeapex android_toolchain buildenv test suite ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${MESON_BUILD_ROOT:-$ROOT_DIR/build}"
LIBMAKEAPEX_DIR="$BUILD_DIR/src/libmakeapex"

TEST_TMPDIR=$(mktemp -d /tmp/makeapex_toolchain_test.XXXXXX)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

MOCK_NDK="$TEST_TMPDIR/ndk"
MOCK_NDK_BIN="$MOCK_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
MOCK_APEX_ROOT="$TEST_TMPDIR/apex"
mkdir -p "$MOCK_NDK_BIN" "$MOCK_APEX_ROOT/com.android.runtime.dev/include"

for tool in x86_64-linux-android32-clang x86_64-linux-android32-clang++ aarch64-linux-android34-clang aarch64-linux-android34-clang++ llvm-ar llvm-ranlib llvm-strip; do
    printf '#!/bin/sh\nexit 0\n' > "$MOCK_NDK_BIN/$tool"
    chmod +x "$MOCK_NDK_BIN/$tool"
done

run_buildenv_probe() {
    local extra_env="$1"
    env -i PATH="/usr/bin:/bin" HOME="$TEST_TMPDIR" \
        MAKEAPEX_LIBRARY="$LIBMAKEAPEX_DIR" \
        NDK="$MOCK_NDK" \
        APEX_SEARCH_PATH="$MOCK_APEX_ROOT" \
        bash -c "
            set -e
            $extra_env
            source '$LIBMAKEAPEX_DIR/buildenv.sh'
            prepare_buildenv
            printf 'CC=%s\nCXX=%s\nAR=%s\nCFLAGS=%s\nCXXFLAGS=%s\nLDFLAGS=%s\nPATH=%s\n' \
                \"\${CC:-}\" \"\${CXX:-}\" \"\${AR:-}\" \"\${CFLAGS:-}\" \"\${CXXFLAGS:-}\" \"\${LDFLAGS:-}\" \"\$PATH\"
        "
}

echo "[Test 1] Default skip-abi-level=3 configures NDK CC/CXX without platform sysroot"
OUT1=$(run_buildenv_probe "arch=('x86_64'); api_level=32; BUILDENV=('android_toolchain'); OPTIONS=(); APEX_INSTALL_SKIP_ABI_LEVEL=3; depends=(); makedepends=()")
echo "$OUT1"
grep -q '^CC=x86_64-linux-android32-clang$' <<< "$OUT1"
grep -q '^CXX=x86_64-linux-android32-clang++$' <<< "$OUT1"
grep -q '^AR=llvm-ar$' <<< "$OUT1"
if grep -q -- '--sysroot=' <<< "$OUT1"; then
    echo "FAILED: sysroot should not be injected when skip-abi-level > 0"
    exit 1
fi

echo "[Test 2] --disable-skip-abis (skip-abi-level=0) injects platform sysroot"
OUT2=$(run_buildenv_probe "arch=('aarch64'); api_level=34; BUILDENV=('android_toolchain'); OPTIONS=(); APEX_INSTALL_SKIP_ABI_LEVEL=0; depends=(); makedepends=()")
echo "$OUT2"
grep -q '^CC=aarch64-linux-android34-clang$' <<< "$OUT2"
grep -q "^CFLAGS=.*--sysroot=$MOCK_APEX_ROOT/com.android.runtime.dev" <<< "$OUT2"
grep -q "^CXXFLAGS=.*--sysroot=$MOCK_APEX_ROOT/com.android.runtime.dev" <<< "$OUT2"
grep -q "^LDFLAGS=.*--sysroot=$MOCK_APEX_ROOT/com.android.runtime.dev" <<< "$OUT2"

echo "[Test 3] com.android.runtime.dev in makedepends injects platform sysroot even at skip-abi-level=3"
OUT3=$(run_buildenv_probe "arch=('x86_64'); api_level=32; BUILDENV=('android_toolchain'); OPTIONS=(); APEX_INSTALL_SKIP_ABI_LEVEL=3; depends=(); makedepends=('com.android.runtime.dev')")
grep -q "^CFLAGS=.*--sysroot=$MOCK_APEX_ROOT/com.android.runtime.dev" <<< "$OUT3"

echo "[Test 4] Explicit CFLAGS/CXXFLAGS --sysroot and CC overrides win"
OUT4=$(run_buildenv_probe "arch=('x86_64'); api_level=32; BUILDENV=('android_toolchain'); OPTIONS=(); APEX_INSTALL_SKIP_ABI_LEVEL=0; depends=(); makedepends=(); CC=my-cc; CFLAGS='--sysroot=/custom/sysroot'; CXXFLAGS='--sysroot=/custom/cxx'")
grep -q '^CC=my-cc$' <<< "$OUT4"
grep -q '^CFLAGS=--sysroot=/custom/sysroot$' <<< "$OUT4"
grep -q '^CXXFLAGS=--sysroot=/custom/cxx$' <<< "$OUT4"

echo "[Test 5] arch=('any') skips target compiler and sysroot injection"
OUT5=$(run_buildenv_probe "arch=('any'); api_level=34; BUILDENV=('android_toolchain'); OPTIONS=(); APEX_INSTALL_SKIP_ABI_LEVEL=0; depends=(); makedepends=()")
grep -q '^CC=$' <<< "$OUT5"
if grep -q -- '--sysroot=' <<< "$OUT5"; then
    echo "FAILED: arch=('any') should not receive --sysroot"
    exit 1
fi

echo "PASSED: all android_toolchain buildenv checks succeeded"
