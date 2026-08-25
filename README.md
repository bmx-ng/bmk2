# bmk2

`bmk2` is the BlitzMax NG build manager for the `bcc2` compiler. It discovers
source dependencies, invokes the compiler and native toolchain, builds modules,
and links applications.

Version 4 is developed separately from the production `bmk` 3.x series. It
requires a matching `bcc2` installation; an older `bmk` cannot discover or
build nested module namespaces introduced by bmk2.

## Building

`bmk.bmx` is the main source file. Build it as a non-GUI release application
using an existing BlitzMax NG installation:

```sh
mkdir -p build
/path/to/bmk makeapp -a -r -h -o ./build/bmk ./bmk.bmx
```

To build for a specific target, add the platform and CPU options:

```sh
/path/to/bmk makeapp -a -r -h -l macos -g arm64 -o ./build/bmk ./bmk.bmx
```

A threaded build of bmk2 can compile independent native and BlitzMax units in
parallel. The resulting executable may have an `.mt` suffix, which should be
removed when it is installed as `bin/bmk`.

## Installing

Back up the existing SDK tools before replacing them. Install the built
executable together with `core.bmk` and `make.bmk` in the BlitzMax `bin`
directory. Install the matching bcc2 executable as `bin/bcc`.

Check the installed version with:

```sh
bmk -v
```

## Common commands

```sh
# Build a debug application
bmk makeapp -o app app.bmx

# Build a release application from clean generated output
bmk makeapp -clean -r -o app app.bmx

# Build all installed modules in release mode
bmk makemods -r

# Force a particular module and stale dependencies to rebuild
bmk makemods -a -r brl.collections

# Remove generated output for all installed modules
bmk cleanmods

# Remove generated output beneath one namespace
bmk cleanmods brl
```

Run `bmk` without arguments for the complete command-line usage guide.

## Nested module namespaces

bmk2 supports module names of arbitrary practical depth. Each directory ending
in `.mod` contributes one component, while the primary source retains the last
component's basename:

```text
one.mod/two.mod/three.mod/three.bmx  ->  One.Two.Three
```

Each component is a single BlitzMax identifier. Names are case-insensitive, and
two paths which differ only by case are an error. A `.mod` directory may be a
namespace-only container, and parent and child modules may coexist. Imports
always resolve one exact module; importing a parent does not import descendants.

## Configuration

An optional `bin/custom.bmk` can override compiler options. Its general form is:

```text
addccopt <name> <value>
```

Platform-specific forms include `addlinuxccopt`, `addwin32ccopt`, and
`addmacccopt`. Quote values containing spaces. The same commands can be placed
in BlitzMax line-comment pragmas, for example:

```blitzmax
'@bmk addccopt exceptions -fexceptions
```

On Linux and macOS, an optional `bin/config.bmk` supplies toolchain settings for
cross-compilation.

## Bootstrap sources

`bmk makebootstrap` creates a clean source snapshot in `dist/bootstrap`, with
standalone native build scripts for bcc2 and bmk2. bmk2 requires
`bin/bootstrap2.cfg`; it does not fall back to the legacy configuration because
that would produce an incomplete bootstrap. An SDK can ship both configurations:
production bmk continues using `bootstrap.cfg`, while bmk2 uses its additional
compiler sources and dependencies from `bootstrap2.cfg`.

The generated scripts expect to be run from their respective `src/bcc` and
`src/bmk` directories. A clean-system integration check is available as:

```sh
tests/run_bootstrap.sh /path/to/sdk macos arm64
```

## Tests

The `tests` directory contains focused unit and integration runners. Most
integration scripts expect paths to an isolated BlitzMax SDK and the freshly
built bmk/bcc executables; run a script without arguments to see its required
environment and usage.
