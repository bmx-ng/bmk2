#!/bin/sh
set -eu

if test "$#" -ne 3
then
	echo "usage: $0 <sdk-root> <platform> <arch>" >&2
	exit 1
fi

sdk_root=$(CDPATH= cd -- "$1" && pwd)
platform=$2
arch=$3
bmk="$sdk_root/bin/bmk"
bootstrap_root="$sdk_root/dist/bootstrap"

run_build_script() {
	build_dir=$1
	build_script=$2
	old_dir=$(pwd)
	cd "$build_dir"
	sh "./$build_script"
	cd "$old_dir"
}

test -x "$bmk"
mkdir -p "$bootstrap_root"
touch "$bootstrap_root/stale-bootstrap-marker"
"$bmk" makebootstrap

test ! -e "$bootstrap_root/stale-bootstrap-marker"
test -f "$bootstrap_root/mod/blitzmax.mod/compiler.mod/build_output_publish.c"
test -f "$bootstrap_root/mod/brl.mod/reflection.mod/reflection.h"
test -f "$bootstrap_root/mod/image.mod/png.mod/libpng/arm/arm_init.c"
test -f "$bootstrap_root/mod/text.mod/jansson.mod/jansson/src/load.c"
test -f "$bootstrap_root/mod/text.mod/json.mod/glue.c"
test -f "$bootstrap_root/mod/text.mod/mpack.mod/glue.c"
test -f "$bootstrap_root/mod/text.mod/mpack.mod/mpack/src/mpack/mpack-reader.c"
test -f "$bootstrap_root/mod/text.mod/mxml.mod/mxml/mxml.h"
test -f "$bootstrap_root/mod/text.mod/xml.mod/glue.c"

case "$platform" in
	win32)
		suffix="console.release.${platform}.${arch}.build.bat"
		bcc_script="$bootstrap_root/src/bcc/bcc.${suffix}"
		bmk_script="$bootstrap_root/src/bmk/bmk.${suffix}"
		grep -q ':BuildFailed' "$bcc_script"
		grep -q ':BuildFailed' "$bmk_script"
		cmd.exe /C "cd /D $(cygpath -w "$bootstrap_root/src/bcc") && bcc.${suffix}"
		cmd.exe /C "cd /D $(cygpath -w "$bootstrap_root/src/bmk") && bmk.${suffix}"
		bcc_executable="$bootstrap_root/src/bcc/bcc.exe"
		bmk_executable="$bootstrap_root/src/bmk/bmk.exe"
		;;
	*)
		suffix="console.release.${platform}.${arch}.build"
		bcc_script="$bootstrap_root/src/bcc/bcc.${suffix}"
		bmk_script="$bootstrap_root/src/bmk/bmk.${suffix}"
		grep -q '^set -e$' "$bcc_script"
		grep -q '^set -e$' "$bmk_script"
		if test "$platform" = "macos"
		then
			grep -Fq '$(xcrun --sdk macosx --show-sdk-path)' "$bcc_script"
			grep -Fq '$(xcrun --sdk macosx --show-sdk-path)' "$bmk_script"
			if grep -E -- '-isysroot[[:space:]]+/?(Applications|Users|Library)/' "$bcc_script" "$bmk_script"
			then
				echo "generation-machine macOS SDK path leaked into bootstrap script" >&2
				exit 1
			fi
		fi
		run_build_script "$bootstrap_root/src/bcc" "bcc.${suffix}"
		run_build_script "$bootstrap_root/src/bmk" "bmk.${suffix}"
		bcc_executable="$bootstrap_root/src/bcc/bcc"
		bmk_executable="$bootstrap_root/src/bmk/bmk"
		;;
esac

if grep -E 'bmxbuild\.stamp\.bmk-tmp|\.bcc2key\.bmk-tmp' "$bcc_script" "$bmk_script"
then
	echo "generation-time bcc2 metadata command leaked into bootstrap script" >&2
	exit 1
fi

if test "$platform" = "macos"
then
	bmk_incbin="$bootstrap_root/src/bmk/.bmx/bmk.bmx.release.${platform}.${arch}.incbin.c"
	test -f "$bmk_incbin"
	grep -Fq '../../src/bmk/macos.icns' "$bmk_incbin"
	if grep -Fq "$sdk_root/" "$bmk_incbin"
	then
		echo "generation SDK path leaked into bootstrap Incbin source" >&2
		exit 1
	fi
fi

test -x "$bcc_executable"
test -x "$bmk_executable"
"$bcc_executable" --version
"$bmk_executable" -v

echo "bmk2 clean-system bootstrap test passed"
