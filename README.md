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

## Pico PIO sources

For the `pico` target, quoted `.pio` imports are part of the application source
graph. bmk asks the Pico SDK to assemble each imported file, generates a compact
program registry, and makes its named programs available through
`Pico.Hardware.PIO`. Changes to a `.pio` file are tracked by the CMake/Ninja
build rather than producing checked-in generated headers.

An installed pioasm is resolved through `pico.pioasm`, `PICO_PIOASM_DIR`, the
host `PATH`, or `~/.pico-sdk/tools`, in that order. When its CMake package
metadata is available, bmk passes that directory to the Pico SDK; otherwise the
SDK can build its matching pioasm itself.

## Pico application sources

Quoted `.bmx` imports are compiled as application-owned source units for Pico,
just as they are for desktop applications. bmk walks transitive imports in
dependency order, publishes each private compiler interface, and links every
generated C unit into the firmware. The application's `Framework` module is
available to every quoted source file. Nested sources, repeated basenames in
different directories, module imports, Incbin resources, and specialization
units retain their canonical application source identity.

Quoted C and C++ imports are also part of the Pico application and module
graphs. bmk passes `.c`, `.cc`, `.cpp`, and `.cxx` units to the Pico SDK CMake
target, validates explicitly imported headers, and preserves module `CC_OPTS`,
`C_OPTS`, `CPP_OPTS`, `LD_OPTS`, and lexical import options. Compiler options
remain attached to their owning translation unit. Ninja's
compiler dependency files provide included-header freshness. Module-owned
Incbin resources are packaged by their BlitzMax source unit and linked into XIP
flash in the same way as application resources.

Pico module discovery uses the normal installed-module catalogue and is not
restricted to the `BRL` or `Pico` namespaces. Bundled namespaces and modules
installed by a user therefore follow the same target-specific interface,
source, native-input, and initialization pipeline. A wildcard header import
such as `Import "src/*.h"` contributes `src` as a native include directory; it
does not expand the matching headers into build inputs.

## Pico runtime and deployment

Pico tooling is resolved in this order: a `custom.bmk` option, the corresponding
environment variable, the host `PATH` where applicable, and finally the newest
matching tool in the Raspberry Pi managed installation under `.pico-sdk` in the
user's home directory. This works on macOS, Linux, and Windows; the managed
CMake lookup understands both the macOS application bundle and ordinary
`bin/cmake` layouts.

The available `custom.bmk` keys and their existing environment equivalents are:

| `custom.bmk` key | Environment variable |
| --- | --- |
| `pico.sdk` | `PICO_SDK_PATH` |
| `pico.toolchain` | `PICO_TOOLCHAIN_PATH` |
| `pico.cmake` | `PICO_CMAKE` |
| `pico.ninja` | `PICO_NINJA` |
| `pico.picotool` | `PICOTOOL_DIR` |
| `pico.pioasm` | `PICO_PIOASM_DIR` |
| `pico.board.header.dirs` | `PICO_BOARD_HEADER_DIRS` |
| `pico.board.cmake.dirs` | `PICO_BOARD_CMAKE_DIRS` |

For example, `#addoption pico.sdk "/opt/pico-sdk"` selects a non-default SDK.
Executable options may name either the executable or its containing directory.
The SDK and toolchain options name their respective roots.

`-board` accepts any board definition available to the selected Pico SDK. The
board definition selects its RP2040 or ARM RP2350 platform, flash configuration,
default pins, and other board-level settings. Custom board definitions can be
made available through `pico.board.header.dirs` and
`pico.board.cmake.dirs` (or their Pico SDK environment equivalents).

Pico applications use a platform-aware managed heap by default: `-heap auto`
selects 192 KiB for RP2040 boards and 384 KiB for ARM RP2350 boards. External
PSRAM is not included automatically. `-heap` accepts an explicit byte count or
a `k`, `KiB`, `m`, or `MiB` suffix. The selected arena is a compile definition
owned by the Pico CMake target, so it is included in linker capacity checks.
After linking, bmk reports the board's configured flash capacity, the managed
arena actually retained by the image, application/SDK RAM, the C heap reserve,
and remaining internal-RAM headroom.

For Pico, `makeapp -x` means build, upload, verify, and start. bmk invokes the
installed picotool with automatic USB reset enabled. If the running firmware
does not expose a compatible reset interface, connect the Pico's own USB port
while holding BOOTSEL and rerun the same command. This workflow does not need a
debug probe. The generated UF2 can still be copied to the BOOTSEL volume
manually.

`makeapp -d -l pico` selects the normal BlitzMax debug configuration for a
Pico application. bcc2 enables `?debug` source blocks and emits GDB line
information referring to the original `.bmx` files, while omitting the desktop
console-debugger instrumentation. The Pico SDK builds the native image with
debug information and `PICO_DEOPTIMIZED_DEBUG=1`, retaining source parameters
and locals at `-O0`. `-r` remains the optimised deployment configuration.

`DebugStop` is emitted as a stable native marker. It is a no-op when firmware
runs without a debugger; the Pico GDB helper installs a hardware breakpoint on
that marker, with its BlitzMax caller directly beneath it in the call stack.
Probe launching is still a
separate OpenOCD/GDB step; `-x` currently retains its documented picotool
upload behaviour for both build modes.

## Tests

The `tests` directory contains focused unit and integration runners. Most
integration scripts expect paths to an isolated BlitzMax SDK and the freshly
built bmk/bcc executables; run a script without arguments to see its required
environment and usage.
