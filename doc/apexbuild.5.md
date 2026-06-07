# APEXBUILD(5)

## NAME
APEXBUILD - Package build description file for makeapex

## SYNOPSIS
APEXBUILD

## DESCRIPTION
The `APEXBUILD` file dictates how a software package is compiled and bundled into an Android APEX image by `makeapex`. It is a bash shell script containing variables and functions required to define the package properties, compile source code, and assemble the file tree structure.

Because `APEXBUILD` files are sourced natively by `makeapex.sh`, standard bash syntax applies.

## VARIABLES

**pkgname** (required)
: The canonical name of the package. It should strictly consist of alphanumeric characters, hyphens, and periods (e.g., `com.example.bash`).

**pkgver** (required)
: The version of the software.

**pkgrel** (required)
: The release number specific to the `makeapex` package versioning (usually defaults to `1`).

**arch** (required)
: An array defining the target architectures (e.g., `('aarch64' 'armv7h' 'x86_64')`). 

**payload_fs** (required)
: Specifies the underlying filesystem to use inside the APEX image. Typically `ext4` or `erofs`.

**source** (optional)
: An array of source files, URLs, or Git repositories required to build the package. If a local directory named `src/` is present alongside the `APEXBUILD`, it is automatically detected and mapped into the build directory without needing to declare it.

**depends** (optional)
: An array of dependencies required for the package to execute at runtime.
: **Virtual Binaries:** Because APEX strictly links via `.so` libraries, depending on binaries directly requires our virtual package standard. Declare dependencies on binaries by using the `_` prefix, such as `_binary_bash` or `_script_makeapex`. `makeapex` will automatically translate this to `libdummy-binary-bash.so` and inject it into the Android linker configuration!

**provides** (optional)
: An array of additional provisions. Similar to `depends`, you can broadcast the availability of a non-library binary using the `_` prefix (e.g., `_script_makeapex`). `makeapex` will dynamically synthesize a valid, empty `libdummy-script-makeapex.so` library into `/vendor/lib/` to fulfill dependency resolution natively inside Android!

## FUNCTIONS

**prepare()**
: Optional. Used to prepare the source code for building (e.g., applying patches, extracting tarballs manually).

**build()**
: Optional. Used to compile the software (e.g., running `./configure` and `make`). The working directory defaults to `$srcdir`.

**package()**
: **Required.** Used to install the compiled files into the packaging directory, represented by the `$pkgdir` variable.
: *Note:* The `$pkgdir` variable intrinsically represents the APEX mount structure. The root of `$pkgdir` maps strictly to `/vendor` within the final Android system unless patched. Therefore, running `mkdir -p "$pkgdir/bin"` translates to `/vendor/bin/` upon boot!

## SEE ALSO
**makeapex(8)**
