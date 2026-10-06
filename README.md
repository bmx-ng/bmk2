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

### Android

Android builds use the LLVM toolchain from a modern side-by-side NDK and the
Gradle project in `resources/android/android-project`. Keep the Android tools
outside the BlitzMax installation; bmk only needs their locations. The current
baseline is JDK 17, Android SDK 35, NDK r28c (`28.2.13676358`), Gradle 8.12 and
Android Gradle Plugin 8.7.3. Applications target API 35 and support API 21 or
newer.

The recommended setup is to configure the SDK installation's `bin/custom.bmk`.
This keeps the Android toolchain selection with BlitzMax and works consistently
on macOS, Linux, and Windows. Use forward slashes in Windows paths:

```text
addoption android.java.home "/path/to/jdk-17"
addoption android.sdk "/path/to/Android/sdk"
addoption android.ndk.version "28.2.13676358"
addoption android.platform "21"
addoption android.sdk.target "35"
# Optional; select a device when more than one is connected.
addoption android.device "DEVICE_SERIAL"
```

`android.ndk.version`, `android.platform`, and `android.sdk.target` are optional.
bmk otherwise chooses the newest side-by-side NDK and SDK platform, with API 21
as the native minimum. If the NDK is installed outside the SDK, use its full
path instead:

```text
addoption android.ndk "/path/to/android-ndk"
```

The same configuration can be supplied through environment variables, which is
useful for CI or temporary overrides:

```sh
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=/path/to/Android/sdk
export ANDROID_NDK_VERSION=28.2.13676358  # optional; newest installed NDK otherwise
export ANDROID_PLATFORM=21               # optional; native minimum API
export ANDROID_SDK_TARGET=35              # optional; newest installed platform otherwise
export ANDROID_SERIAL=DEVICE_SERIAL       # optional; select among multiple devices
```

`ANDROID_SDK_ROOT` is also accepted for the SDK. For an NDK outside the SDK,
set `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT`. Configuration keys take precedence
over environment variables. Keep machine-specific paths in the installed SDK's
`bin/custom.bmk`, rather than a project file intended for source control.

Build an ARM64 debug APK with:

```sh
bmk makeapp -l android -g arm64v8a -o build/myapp app.bmx
```

The result is `build/myapp.apk`. Supported ABI selectors are `arm64v8a`,
`armeabiv7a`, `x86`, and `x64`. The generated Gradle project is placed beside
the output temporarily and contains the native library under the matching
`jniLibs` ABI directory. A full build with `-a` recreates this project from the
template so changes to application settings, such as `app.package`, are applied.

Inspect the connected device with:

```sh
bmk deviceinfo -l android
```

With one authorized device connected, build, install, and launch a debug APK in
one step by adding `-x`:

```sh
bmk makeapp -x -l android -g arm64v8a -o build/myapp app.bmx
```

bmk uses `adb install -r` so an existing copy is updated, then starts the
configured package's `.BlitzMaxApp` activity. If several authorized devices are
connected, select one persistently with `android.device` in `bin/custom.bmk`, or
temporarily with `ANDROID_SERIAL`. Unauthorized and offline devices are reported
but are never selected. An unsigned release APK is not installed automatically.

Release signing is optional. For per-application configuration, create
`<application>.signing.properties` beside the main `.bmx` source and keep it out
of source control:

```properties
storeFile=/path/to/upload-keystore.jks
storePassword=keystore-password
keyAlias=upload
keyPassword=key-password
```

A relative `storeFile` is resolved from the directory containing the signing
properties file. When all four values are available, Gradle produces a signed
release APK and `-x` may install it:

```sh
bmk makeapp -a -r -x -l android -g arm64v8a -o build/myapp app.bmx
```

Machine-local `custom.bmk` options can provide or override individual values:

```text
addoption android.signing.keystore "/path/to/upload-keystore.jks"
addoption android.signing.key.alias "upload"
addoption android.signing.store.password "keystore-password"
addoption android.signing.key.password "key-password"
```

For CI and secret injection, the equivalent environment variables are
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD`. Precedence is environment, then the per-application
properties file, then `custom.bmk` as a machine-wide default. Avoid placing passwords in a tracked file;
bmk passes resolved credentials to Gradle through the build process environment
and does not copy them into the generated project.

The equivalent manual commands, substituting the configured package if changed,
are:

```sh
adb install -r build/myapp.apk
adb shell am start -n com.blitzmax.app/.BlitzMaxApp
```

### Module-local configuration

Since BMK2 4.04, a module may ship a `module.bmk` beside its main `.bmx` file. BMK executes it
before discovering that module's conditional imports, including when compiled
module artifacts already exist. No second module-local override file is needed.
Existing SDK `bin/custom.bmk` and application `pre.bmk` settings are visible to it.

For example, `module.bmk` can read an existing setting and default it locally:

```text
@define configurebackend
	local backend = globals.Get("example.backend")
	if backend == "" then backend = "both" end
	if backend ~= "both" and backend ~= "x11" and backend ~= "wayland" then
		error("Unsupported example.backend: " .. backend)
	end
	if backend ~= "wayland" then globals.AddC("user_defs", "example_x11") end
	if backend ~= "x11" then globals.AddC("user_defs", "example_wayland") end
@end
configurebackend
```

An application's `pre.bmk`, or the SDK's existing `custom.bmk`, can select:

```text
setoption example.backend x11
```

The module can use `?example_x11` / `?example_wayland` in its source imports and
ModuleInfo dependency options. Module-local `adddef`, `addccopt`, `addasmopt` and `addldopt` settings apply to
its compilation units; Lua can also set the `c_opts` and `cpp_opts` option lists.
Link options accompany the module into the final application. They do not change
the options of separately imported modules. Native options are additive to the
SDK's toolchain settings, not a replacement for them.

The script runs in the module directory and `%MODPATH%` identifies that directory.
Settings, option stacks and BMK command definitions are restored afterward.
Use configuration scripts to select build inputs; do not change the target
architecture, compiler toolchain or process environment, or perform compilation
side effects there. This is configuration scoping, not a security sandbox for Lua.
Module-local definitions also apply to quoted source files inside the module tree.

BMK fingerprints the script and its effective compiler/link/conditional options.
Changing or removing it rebuilds the module's sources. Application link tracking
also handles a module rebuilt separately through `makemods`, even when filesystem
timestamps fall in the same second. Successful builds publish `.module-config`
sidecars; keep those out of version control. A module without configuration keeps
its existing build behaviour. Switching a shared module's configuration affects
that SDK's cached module; concurrently building different configurations into the
same module directory is not supported.

Run `sh tests/run_module_config.sh /path/to/bin/bmk /new/test/output` for the
isolated integration fixtures.

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
| `pico.float.abi` | `PICO_FLOAT_ABI` |

For example, `#addoption pico.sdk "/opt/pico-sdk"` selects a non-default SDK.
Executable options may name either the executable or its containing directory.
The SDK and toolchain options name their respective roots.

`-board` accepts any board definition available to the selected Pico SDK. When
the named definition can be found, `bmk` infers the `pico` target and its
currently supported `arm` architecture, so `-l pico -g arm` may be omitted. The
board definition selects its RP2040 or ARM RP2350 platform, flash configuration,
default pins, and other board-level settings. Custom board definitions can be
made available through `pico.board.header.dirs` and
`pico.board.cmake.dirs` (or their Pico SDK environment equivalents).

`-float-abi auto` is the default: RP2040 uses the software floating-point ABI,
while ARM RP2350 uses the softfp ABI and its hardware FPU. `-float-abi hard`
selects the hard-float calling convention and is supported only by ARM RP2350
boards. The same setting can be supplied as `pico.float.abi` or
`PICO_FLOAT_ABI`.

Pico applications use a platform-aware managed heap by default: `-heap auto`
selects 192 KiB for RP2040 boards and 384 KiB for ARM RP2350 boards. External
PSRAM is not included automatically. `-heap` accepts an explicit byte count or
a `k`, `KiB`, `m`, or `MiB` suffix. The selected arena is a compile definition
owned by the Pico CMake target, so it is included in linker capacity checks.
After linking, bmk reports the board's configured flash capacity, the managed
arena actually retained by the image, application/SDK RAM, the C heap reserve,
and remaining internal-RAM headroom.

For ESP32 profiles with `-heap-region psram`, `-heap auto` keeps one eighth of
the declared PSRAM capacity available to ESP-IDF and native services, with a
minimum reserve of 256 KiB. The remaining PSRAM is used for the BlitzMax
managed arena.

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

## Embedded device inspection

`bmk boardinfo -l esp32 -board <profile>` reports the static information bmk
uses for a board: its ESP-IDF target and architecture, build settings, default
buses, onboard resources, pin constraints, and named GPIO map. The supplied
profiles live under `esp32.mod/boards`, one directory per board. Additional
profile roots can be supplied through `esp32.board.dirs` in `custom.bmk` or
`ESP32_BOARD_DIRS`, so a local or vendor profile does not require changing bmk.

An explicit recognised board is sufficient for normal embedded builds. For
example, `bmk makeapp -board baguette_s3 app.bmx` infers both `-l esp32` and
`-g xtensa`. If a name exists in both catalogues, `bmk` asks for `-l pico` or
`-l esp32`; if it exists in neither, an explicit platform supplies the missing
context for a custom Pico definition while ESP32 continues to require a loaded
profile.

`bmk deviceinfo -l esp32` uses the installed ESP-IDF `esptool` to report facts
read from one connected ESP32 device, including its chip, revision, features,
flash capacity and interface, crystal, USB mode, and MAC address. Set `ESPPORT`
or `esp32.port` when more than one serial device is available. The operation
does not erase or program flash and restarts the installed application after
inspection.

ESP32 tooling supports both Espressif's installer-managed layout and a manual
checkout stored independently from its downloaded tools. `IDF_PATH` identifies
the checkout, `IDF_TOOLS_PATH` identifies the tools root, and
`IDF_PYTHON_ENV_PATH` identifies the matching Python virtual environment. If
the latter two are unset, bmk checks the standard `.espressif` manual-install
layout and the installer-managed layout, using ESP-IDF's version metadata to
select a compatible Python environment.

The equivalent persistent `custom.bmk` options are `esp32.idf`, `esp32.tools`,
and `esp32.python`. A configured Python value may name either its virtual
environment directory or the Python executable itself. Configuration options
take precedence over their corresponding environment variables.

For ESP32, `makeapp -x` also uses the selected board profile's console
transport. Profiles declaring native USB Serial/JTAG use esptool's USB reset
sequence; conventional UART profiles retain ESP-IDF's default DTR/RTS reset.
This keeps upload and restart board-driven rather than hardcoding individual
board names.

ESP32 applications which import `Embedded.Network.BLE` automatically enable
the ESP-IDF Bluetooth controller and NimBLE host through generated build
defaults. Applications which do not import BLE keep those components disabled.

`bmk deviceinfo -l pico` similarly uses the installed `picotool` to report the
RP-series chip, revision, physical flash capacity, and identifiers that the
device exposes. It can temporarily request BOOTSEL mode from compatible running
firmware and returns the device to application mode afterward.

The detected silicon does not identify a retail development board. If `-board`
is supplied, bmk displays it separately as selected build configuration; it
never infers a board profile from a matching chip and flash combination. On
ESP32, bmk warns when that profile's configured firmware flash size differs
from the capacity reported by the device. `deviceinfo` fails for non-embedded
targets.

Board selection remains explicit: `-board baguette_s3` selects build defaults,
while `deviceinfo` describes attached silicon and flash. bmk compares the two
when both are available, but deliberately does not guess a retail board from
chip characteristics shared by many products.

## Tests

The `tests` directory contains focused unit and integration runners. Most
integration scripts expect paths to an isolated BlitzMax SDK and the freshly
built bmk/bcc executables; run a script without arguments to see its required
environment and usage.
