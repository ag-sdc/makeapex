# Contributing to Makeapex

Thank you for your interest in contributing to `makeapex`! As an autonomous Android APEX build system modeled closely after Arch Linux's `makepkg`, we strive to maintain clean, POSIX-compliant code that is reliable and easily auditable.

## Getting Started

1. **Fork the Repository:** Create a fork of the main `makeapex` repository.
2. **Clone:** Clone your fork locally and create a new feature branch.
3. **Dependencies:** Ensure you have `bash`, `coreutils`, `e2fsprogs`, `erofs-utils`, `zip`, `binutils`, and `gcc` installed on your system to test builds locally.

## Code Style

- **Bash Standards:** We follow standard `bash` best practices. Code should be clean, modular, and use well-defined variables.
- **Indentation:** Use tabs for indentation in `.sh` files to maintain consistency with the existing `makepkg`-derived codebase.
- **Error Handling:** Always use the built-in `error`, `warning`, `msg`, and `msg2` functions from `util/message.sh` rather than raw `echo` or `printf`.
- **Tidy Hooks:** If you are adding a new packaging mutation phase, place it into `src/libmakeapex/tidy/` and prefix the script logically (e.g., `70-newfeature.sh`).

## Submitting a Pull Request

- Keep PRs focused on a single feature or bug fix.
- Ensure all commit messages are clear, concise, and ideally signed (`git commit -S`).
- Detail your changes in the PR description, explicitly stating how they affect the build lifecycle.

## Reporting Bugs

When submitting a bug report, please provide:
1. The `makeapex` version you are running.
2. The exact `APEXBUILD` file you used.
3. The environment you are running on (e.g., Arch Linux, Alpine, GitHub Actions).
4. The full console output.

## License

By contributing to `makeapex`, you agree that your contributions will be licensed under the GNU General Public License v2.0 (GPL-2.0), the same license governing `makepkg`.
