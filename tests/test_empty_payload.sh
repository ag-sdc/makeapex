#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

DESTDIR="$TMPDIR/destdir"
DESTDIR="$DESTDIR" ninja -C "$BUILD_DIR" install >/dev/null

CONF="$TMPDIR/makeapex.conf"
cat > "$CONF" << 'EOF'
CARCH="x86_64"
OPTIONS=(strip docs libtool staticlibs emptydirs zipman purge !debug !lto !autodeps)
INTEGRITY_CHECK=(sha256)
PKGEXT='.apex'
SRCEXT='.src.tar.gz'
EOF

EMPTY_DIR="$TMPDIR/empty_pkg"
mkdir -p "$EMPTY_DIR"
cat > "$EMPTY_DIR/APEXBUILD" << 'EOF'
org="com.android"
pkgname="empty.test"
pkgver=1.0.0
pkgrel=1
arch=('x86_64')
payload_fs=erofs

package() {
  mkdir -p "$pkgdirprefix/bin" "$pkgdirprefix/lib"
}
EOF

echo "[Test] makeapex refuses to package stub-only empty payload"
set +e
OUT=$(cd "$EMPTY_DIR" && CC="${CC:-gcc}" MAKEAPEX_LIBRARY="$DESTDIR/usr/share/makeapex" \
  "$DESTDIR/usr/bin/makeapex" -d --config "$CONF" -f 2>&1)
RC=$?
set -e

if [[ $RC -eq 0 ]]; then
  echo "FAILED: Expected makeapex to fail on empty payload, but exited 0"
  echo "$OUT"
  exit 1
fi
if ! echo "$OUT" | grep -q "APEX payload for .* is empty"; then
  echo "FAILED: Missing expected empty-payload error message"
  echo "$OUT"
  exit 1
fi
if [[ -f "$EMPTY_DIR/com.android.empty.test.apex" ]]; then
  echo "FAILED: Stub-only empty APEX archive should not be created"
  exit 1
fi

echo "PASSED: Empty-payload guard rejected stub-only APEX cleanly"
