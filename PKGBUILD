pkgname=makeapex
pkgver=1.0.0
pkgrel=1
pkgdesc="Autonomous Android APEX build system modeled after makepkg"
arch=('any')
url="https://github.com/shadichy/makeapex"
license=('GPL')
depends=('bash' 'coreutils' 'awk' 'sed' 'e2fsprogs' 'erofs-utils' 'zip' 'unzip' 'openssl' 'python')
optdepends=('android-tools: Android SDK tools for aapt2, zipalign, apksigner')
source=("local://.")
md5sums=('SKIP')

package() {
  # Create directories
  install -d "$pkgdir/vendor/makeapex"
  install -d "$pkgdir/vendor/bin"
  
  # Copy files
  cp -r "$srcdir/"* "$pkgdir/vendor/makeapex/"
  
  # Ensure makeapex script is executable
  chmod +x "$pkgdir/vendor/makeapex/makeapex.sh"
  if [ -f "$pkgdir/vendor/makeapex/avbtool" ]; then
      chmod +x "$pkgdir/vendor/makeapex/avbtool"
  fi
  
  # Create symlink
  ln -s /vendor/makeapex/makeapex.sh "$pkgdir/vendor/bin/makeapex"
}
