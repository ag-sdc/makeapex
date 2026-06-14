libmakeapex_module = 'buildenv'

sources = [
  'apex_install.sh.in',
  'buildflags.sh.in',
  'compiler.sh.in',
  'debugflags.sh.in',
  'fortran.sh.in',
  'lto.sh.in',
  'makeflags.sh.in',
  'rust.sh.in',
]

foreach src : sources
  output_dir = join_paths(get_option('datadir'), 'makeapex', libmakeapex_module)

  custom_target(
    libmakeapex_module + '_' + src.underscorify(),
    command : [ SCRIPT_EDITOR, '@INPUT@', '@OUTPUT@' ],
    input : src,
    output : '@BASENAME@',
    install : true,
    install_dir : output_dir)
endforeach
