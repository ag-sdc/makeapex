# MAKEAPEX(8)

## NAME
makeapex - Android APEX build utility

## SYNOPSIS
**makeapex** [options]

## DESCRIPTION
`makeapex` is a script designed to automate the building of Android APEX (Android Pony EXpress) packages. It is heavily modeled after Arch Linux's `makepkg` utility, providing a familiar environment for packaging system binaries, scripts, and libraries into a self-contained, cryptographically signed, and dynamically linked APEX payload.

When invoked, `makeapex` reads the `APEXBUILD` file in the current directory, executes its lifecycle functions (`build()`, `package()`), automatically introspects generated ELF files to map linker namespace dependencies, and bundles the result into an `ext4` or `erofs` filesystem image.

## OPTIONS

**-d, --nodeps**
: Do not perform any dependency checks. This will skip validating whether the host system possesses the required utilities to build the package.

**-c, --clean**
: Clean up leftover work files and directories after a successful build.

**-f, --force**
: `makeapex` will not build a package if a built package already exists in the `PKGDEST` directory. This allows the built package to be overwritten.

**-s, --syncdeps**
: Not strictly enforced for APEX dependencies, but serves as a compatibility hook with `makepkg`.

**--noconfirm**
: Assumes default answers to all confirmation prompts. Useful for automated CI/CD pipelines.

## FILES

**APEXBUILD**
: The default configuration file read by `makeapex` in the directory from which it is called. See **apexbuild(5)** for comprehensive syntax and structural details.

**makeapex.conf**
: Global configuration variables for the build environment (e.g., standard payload formats, signing key paths).

## ARCHITECTURE AND LINKER INJECTION
Unlike standard Linux packages, APEX payloads are isolated by the Android Bionic dynamic linker. 

`makeapex` features an advanced **Tidy Hook System** that automatically runs `readelf` against all packaged ELF binaries and shared libraries during the build. It extracts `SONAME` and `NEEDED` properties, dynamically synthesizing an `etc/linker.config.json` and injecting `requireNativeLibs`/`provideNativeLibs` into the boot `apex_manifest.json` right before creating the filesystem image.

## SEE ALSO
**apexbuild(5)**
