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
	mkdir -p "$pkgdir"/opt/makeapex
	mkdir -p "$pkgdir"/usr/bin
	
	cp -r "$srcdir"/* "$pkgdir"/opt/makeapex/
	
	chmod +x "$pkgdir"/opt/makeapex/makeapex.sh
	if [ -f "$pkgdir"/opt/makeapex/avbtool ]; then
		chmod +x "$pkgdir"/opt/makeapex/avbtool
	fi
	
	ln -s /opt/makeapex/makeapex.sh "$pkgdir"/usr/bin/makeapex
}
