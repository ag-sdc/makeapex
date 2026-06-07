# makeapex

`makeapex` is a lightweight, declarative build automation tool designed to securely and efficiently package software into Android APEX (Android Pony EXpress) images. Modeled heavily after Arch Linux's renowned `makepkg` system, `makeapex` allows developers to write clean, `bash`-based build scripts (`APEXBUILD`) to handle downloading, compiling, and packaging source code for the Android ecosystem.

## Features

- **Declarative `APEXBUILD` Scripts**: Define sources, dependencies, build instructions, and package metadata in a clean `bash` syntax.
- **Android Bionic Linker Integration**: Automatically introspects ELF binaries (using `readelf`) to dynamically generate `apex_manifest.json` dependencies and `linker.config.json` specifications for the Android dynamic linker.
- **Microarchitecture Isolation**: Native support for preventing ABI conflicts using `_x86_64_microarch_level` and `_aarch64_microarch_level`. Older devices are safely protected from mathematically-optimized binaries built for newer instruction sets (e.g. `x86_64-v3`).
- **Virtual Dependencies**: Safely declare dependencies on non-library binaries (like `bash` or `coreutils`) using the `_` prefix syntax (e.g. `_binary_bash`). The system automatically stubs virtual `.so` libraries to satisfy the Bionic linker without polluting the filesystem.
- **Cross-Compilation Ready**: By overriding `CARCH`, `CHOST`, and standard build flags in your `makeapex.conf`, you can effortlessly cross-compile APEX payloads from an `x86_64` host directly to `aarch64` Android targets.

## Documentation

Full documentation is provided via manual pages in the `doc/` directory.

- [makeapex(8)](doc/makeapex.8.asciidoc) - Usage instructions and command-line arguments for the `makeapex` executable.
- [APEXBUILD(5)](doc/APEXBUILD.5.asciidoc) - Comprehensive syntax and variable reference for writing your own APEX packages.
- [makeapex.conf(5)](doc/makeapex.conf.5.asciidoc) - Configuration guide for setting up cross-compilers, global build flags, and environment variables.

## Project Layout

- `src/` - Contains the `makeapex` script and its internal library functions (`libmakeapex`).
- `doc/` - Asciidoc manuals detailing how to use and configure the tool.
- `.ci/dist/` - Continuous integration test suites and dogfooding files.

## Contributing

We welcome patches, bug reports, and pull requests! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for our contribution guidelines.

## License

`makeapex` is licensed under the **GPL-2.0** License. See the [LICENSE](LICENSE) file for the full text.
