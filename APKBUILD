# Contributor: Shadichy <shadichy@example.com>
# Maintainer: Shadichy <shadichy@example.com>
pkgname=makeapex
pkgver=1.0.0
pkgrel=1
pkgdesc="Autonomous Android APEX build system modeled after makepkg"
url="https://github.com/shadichy/makeapex"
arch="noarch"
license="GPL"
depends="bash coreutils awk sed e2fsprogs erofs-utils zip unzip openssl python3"
makedepends=""
source="local://."

build() {
	return 0
}

package() {
	mkdir -p "$pkgdir"/vendor/makeapex
	mkdir -p "$pkgdir"/vendor/bin
	
	cp -r "$srcdir"/* "$pkgdir"/vendor/makeapex/
	
	chmod +x "$pkgdir"/vendor/makeapex/makeapex.sh
	if [ -f "$pkgdir"/vendor/makeapex/avbtool ]; then
		chmod +x "$pkgdir"/vendor/makeapex/avbtool
	fi
	
	ln -s /vendor/makeapex/makeapex.sh "$pkgdir"/vendor/bin/makeapex
}
