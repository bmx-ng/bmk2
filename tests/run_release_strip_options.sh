#!/bin/sh
set -eu

if test "$#" -ne 2
then
	echo "usage: $0 <bmk> <output-root>" >&2
	exit 1
fi

bmk=$1
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)

test ! -e "$output_root"
mkdir -p "$output_root"
cp "$fixture_dir/release_strip_app.bmx" "$output_root/app.bmx"

build_output=$("$bmk" makeapp -a -bcc2 -v -single -r -o "$output_root/release-strip-app" "$output_root/app.bmx" 2>&1)

if printf '%s' "$build_output" | grep -Eq -- '(^|[[:space:]])-c[[:space:]].*[[:space:]]-s([[:space:]]|$)|(^|[[:space:]])-s[[:space:]].*[[:space:]]-c([[:space:]]|$)'
then
	echo "release strip option reached a native compile command" >&2
	exit 1
fi
if printf '%s' "$build_output" | grep -Eq -- "argument unused during compilation: '-s'|ld: warning: -s is obsolete"
then
	echo "release strip option produced a toolchain warning" >&2
	exit 1
fi

case "$(uname -s)" in
	Darwin)
		printf '%s' "$build_output" | grep -q -- '-Wl,-S,-x'
		;;
	*)
		printf '%s' "$build_output" | grep -Eq -- '(^|[[:space:]])-s([[:space:]]|$)'
		;;
esac

test -x "$output_root/release-strip-app" || test -f "$output_root/release-strip-app.exe"

echo "bmk release strip option tests passed"
