#!/bin/sh
set -eu

if test "$#" -ne 2
then
	echo "usage: $0 <bmk> <output-root>" >&2
	exit 1
fi

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
bmk="$bmk_dir/$(basename -- "$1")"
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)
application="$output_root/bmk-pragma"

test ! -e "$output_root"
mkdir -p "$output_root"
cp "$fixture_dir/application_bmk_pragma.bmx" "$output_root/app.bmx"
cp "$fixture_dir/pragma_import_app.bmx" "$output_root/import_app.bmx"
cp "$fixture_dir/pragma_import_child.bmx" "$output_root/pragma_import_child.bmx"
cp "$fixture_dir/pragma_import_grandchild.bmx" "$output_root/pragma_import_grandchild.bmx"
cp "$fixture_dir/pragma_import_native.c" "$output_root/pragma_import_native.c"
cp "$fixture_dir/pragma_import_sibling.c" "$output_root/pragma_import_sibling.c"

build_output=$("$bmk" makeapp -bcc2 -v -single -r -o "$application" "$output_root/app.bmx")
printf '%s' "$build_output" | grep -q -- '-DBMK_PRAGMA_ACTIVE'
printf '%s' "$build_output" | grep -q -- '-DBMK_NESTED_PRAGMA_ACTIVE'
if printf '%s' "$build_output" | grep -Eq -- 'DBMK_(EMBEDDED|REM)_PRAGMA_MUST_NOT_RUN'
then
	echo "non-comment pragma text reached the native compiler" >&2
	exit 1
fi

executable=$application
if test -f "$application.exe"
then
	executable="$application.exe"
fi
test "$("$executable" | tail -n 1 | tr -d '\r')" = "pragma-ok"

import_application="$output_root/bmk-pragma-import"
"$bmk" makeapp -bcc2 -single -r -o "$import_application" "$output_root/import_app.bmx"
import_executable=$import_application
if test -f "$import_application.exe"
then
	import_executable="$import_application.exe"
fi
test "$("$import_executable" | tail -n 1 | tr -d '\r')" = "pragma-import-ok"

quiet_output=$("$bmk" makeapp -bcc2 -v -single -r -o "$application" "$output_root/app.bmx")
if printf '%s' "$quiet_output" | grep -Eq 'Processing:app|Compiling:app|Linking:bmk-pragma'
then
	printf '%s\n' "$quiet_output" >&2
	echo "unchanged pragma application was rebuilt" >&2
	exit 1
fi

echo "bmk source pragma tests passed"
