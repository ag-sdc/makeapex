project('makeapex',
        version : '1.0.0',
        license : 'GPL-2.0-or-later',
        meson_version : '>= 0.60.0',
        default_options : [
          'sysconfdir=/etc',
          'localstatedir=/var',
        ])

BASH = find_program('bash', required : true)
FILECMD = find_program('file', required : true)
AAPT2 = find_program('aapt2', required : true)
AVBTOOL = find_program('avbtool', required : true)
ZIPALIGN = find_program('zipalign', required : true)
APKSIGNER = find_program('apksigner', required : true)
MKE2FS = find_program('mke2fs', required : true)
MKFSEROFS = find_program('mkfs.erofs', required : true)
OPENSSL = find_program('openssl', required : true)
ZIP = find_program('zip', required : true)
UNZIP = find_program('unzip', required : true)
AWK = find_program('awk', required : true)

PREFIX = get_option('prefix')
SYSCONFDIR = join_paths(PREFIX, get_option('sysconfdir'))

substs = configuration_data()
substs.set('PACKAGE_VERSION', meson.project_version())
substs.set('PACKAGE_NAME', meson.project_name())
substs.set('PREFIX', PREFIX)
substs.set('sysconfdir', SYSCONFDIR)
substs.set('LIBMAKEAPEXDIR', join_paths(PREFIX, get_option('datadir'), 'makeapex'))
substs.set('BASH', BASH.full_path())
substs.set('FILECMD', FILECMD.full_path())
substs.set('AAPT2', AAPT2.full_path())
substs.set('AVBTOOL', AVBTOOL.full_path())
substs.set('ZIPALIGN', ZIPALIGN.full_path())
substs.set('APKSIGNER', APKSIGNER.full_path())
substs.set('MKE2FS', MKE2FS.full_path())
substs.set('MKFSEROFS', MKFSEROFS.full_path())
substs.set('OPENSSL', OPENSSL.full_path())
substs.set('ZIP', ZIP.full_path())
substs.set('UNZIP', UNZIP.full_path())
substs.set('AWK', AWK.full_path())
substs.set('BUILDSCRIPT', 'APEXBUILD')
substs.set('BSDTAR_NO_READ_SPARSE', '')
substs.set('SEDINPLACE', 'sed --follow-symlinks -i')

SCRIPT_EDITOR = find_program(configure_file(
  input : join_paths(meson.project_source_root(), 'build-aux/edit-script.sh.in'),
  output : 'edit-script.sh',
  configuration : substs))

custom_target(
  'makeapex',
  input : 'src/makeapex.sh.in',
  command : [ SCRIPT_EDITOR, '@INPUT@', '@OUTPUT@', '0755'],
  output : 'makeapex',
  install : true,
  install_dir : get_option('bindir'))

custom_target(
  'makeapex.conf',
  input : 'src/makeapex.conf.in',
  command : [ SCRIPT_EDITOR, '@INPUT@', '@OUTPUT@', '0644'],
  output : 'makeapex.conf',
  install : true,
  install_dir : get_option('sysconfdir'))

subdir('src/libmakeapex')
