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
  install -d "$pkgdir/opt/makeapex"
  install -d "$pkgdir/usr/bin"
  
  # Copy files
  cp -r "$srcdir/"* "$pkgdir/opt/makeapex/"
  
  # Ensure makeapex script is executable
  chmod +x "$pkgdir/opt/makeapex/makeapex.sh"
  if [ -f "$pkgdir/opt/makeapex/avbtool" ]; then
      chmod +x "$pkgdir/opt/makeapex/avbtool"
  fi
  
  # Create symlink
  ln -s /opt/makeapex/makeapex.sh "$pkgdir/usr/bin/makeapex"
}
