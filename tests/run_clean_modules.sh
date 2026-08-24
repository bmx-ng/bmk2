#!/bin/sh
set -eu

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
bmk_path="$bmk_dir/$(basename -- "$1")"
test_root=$2
config_dir=${3:-$bmk_dir}
sdk_root="$test_root/sdk"

make_cache()
{
	module_path=$1
	module_name=$(basename "$module_path" .mod)
	mkdir -p "$module_path/.bmx/nested" "$module_path/.generics/objects" "$module_path/generics"
	touch "$module_path/$module_name.bmx"
	touch "$module_path/.bmx/nested/generated.c"
	touch "$module_path/.generics/objects/generated.o"
	touch "$module_path/generics/keep.bmx"
	touch "$module_path/$module_name.release.macos.x64.a"
	touch "$module_path/$module_name.release.macos.x64.i"
	touch "$module_path/$module_name.release.macos.x64.i2"
	touch "$module_path/$module_name.release.macos.x64.bmxbuild"
	touch "$module_path/$module_name.release.macos.x64.bmxbuild.stamp"
	touch "$module_path/$module_name.release.macos.x64.bmxbuild.stamp.bmk-tmp-123-4"
	touch "$module_path/$module_name.release.notes.a"
	touch "$module_path/thirdparty.a"
}

assert_cache_present()
{
	module_name=$(basename "$1" .mod)
	test -f "$1/.bmx/nested/generated.c"
	test -f "$1/.generics/objects/generated.o"
	test -f "$1/generics/keep.bmx"
	test -f "$1/$module_name.release.macos.x64.a"
	test -f "$1/$module_name.release.macos.x64.i"
	test -f "$1/$module_name.release.macos.x64.i2"
	test -f "$1/$module_name.release.macos.x64.bmxbuild"
	test -f "$1/$module_name.release.macos.x64.bmxbuild.stamp"
	test -f "$1/$module_name.release.macos.x64.bmxbuild.stamp.bmk-tmp-123-4"
	test -f "$1/$module_name.release.notes.a"
	test -f "$1/thirdparty.a"
}

assert_cache_cleaned()
{
	module_name=$(basename "$1" .mod)
	test ! -e "$1/.bmx"
	test ! -e "$1/.generics"
	test -f "$1/generics/keep.bmx"
	test ! -e "$1/$module_name.release.macos.x64.a"
	test ! -e "$1/$module_name.release.macos.x64.i"
	test ! -e "$1/$module_name.release.macos.x64.i2"
	test ! -e "$1/$module_name.release.macos.x64.bmxbuild"
	test ! -e "$1/$module_name.release.macos.x64.bmxbuild.stamp"
	test ! -e "$1/$module_name.release.macos.x64.bmxbuild.stamp.bmk-tmp-123-4"
	test -f "$1/$module_name.release.notes.a"
	test -f "$1/thirdparty.a"
}

mkdir -p "$sdk_root/bin"
cp "$bmk_path" "$sdk_root/bin/bmk"
for config_path in "$config_dir"/*.bmk
do
	cp "$config_path" "$sdk_root/bin/$(basename -- "$config_path")"
done

range_module="$sdk_root/mod/brl.mod/range.mod"
rangeextra_module="$sdk_root/mod/brl.mod/rangeextra.mod"
optional_module="$sdk_root/mod/brl.mod/optional.mod"
stdc_module="$sdk_root/mod/pub.mod/stdc.mod"

make_cache "$range_module"
make_cache "$rangeextra_module"
make_cache "$optional_module"
make_cache "$stdc_module"

# A full module name is exact, not a raw prefix.
"$sdk_root/bin/bmk" cleanmods brl.range
assert_cache_cleaned "$range_module"
assert_cache_present "$rangeextra_module"
assert_cache_present "$optional_module"
assert_cache_present "$stdc_module"

# Refuse links within a module cache before deleting any selected cache.
make_cache "$range_module"
outside_target="$test_root/outside-target"
mkdir -p "$outside_target"
touch "$outside_target/keep"
if ln -s "$outside_target" "$range_module/.bmx/outside-link" 2>/dev/null
then
	if "$sdk_root/bin/bmk" cleanmods brl.range >"$test_root/link-guard.log" 2>&1
	then
		echo "cleanmods unexpectedly accepted a link inside a module cache" >&2
		exit 1
	fi
	grep -q 'BMKCLEAN002 refusing symbolic link inside module cache' "$test_root/link-guard.log"
	test -f "$outside_target/keep"
	assert_cache_present "$range_module"
	rm "$range_module/.bmx/outside-link"
fi

# A namespace selects every module within it and no other namespace.
"$sdk_root/bin/bmk" cleanmods brl
assert_cache_cleaned "$range_module"
assert_cache_cleaned "$rangeextra_module"
assert_cache_cleaned "$optional_module"
assert_cache_present "$stdc_module"

# With no selector, every installed module cache is selected.
make_cache "$range_module"
make_cache "$rangeextra_module"
make_cache "$optional_module"
"$sdk_root/bin/bmk" cleanmods
assert_cache_cleaned "$range_module"
assert_cache_cleaned "$rangeextra_module"
assert_cache_cleaned "$optional_module"
assert_cache_cleaned "$stdc_module"

echo "bmk cleanmods tests passed"
