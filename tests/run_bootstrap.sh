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

test -x "$bcc_executable"
test -x "$bmk_executable"
"$bcc_executable" --version
"$bmk_executable" -v

echo "bmk2 clean-system bootstrap test passed"
