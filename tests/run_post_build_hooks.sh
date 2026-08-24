#!/bin/sh
set -eu

if test "$#" -ne 2
then
	echo "usage: $0 <bmk> <output-root>" >&2
	exit 1
fi

bmk=$1
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures/post_build_hooks" && pwd)
source_root="$output_root/source"
application="$output_root/post-hooks-app"

test ! -e "$output_root"
mkdir -p "$source_root"
cp "$fixture_dir/app.bmx" "$source_root/app.bmx"
cp "$fixture_dir/pre.bmk" "$source_root/pre.bmk"
cp "$fixture_dir/post.bmk" "$source_root/post.bmk"
cp "$fixture_dir/post-hooks-app.post.bmk" "$source_root/post-hooks-app.post.bmk"

"$bmk" makeapp -a -r -o "$application" "$source_root/app.bmx"

test "$(grep -c '^pre$' "$source_root/hooks.log" | tr -d ' ')" -eq 1
test "$(grep -c '^post$' "$source_root/hooks.log" | tr -d ' ')" -eq 1
test "$(grep -c '^specific$' "$source_root/hooks.log" | tr -d ' ')" -eq 1
test "$(wc -l < "$source_root/hooks.log" | tr -d ' ')" -eq 3

echo "bmk pre/post build hook regression passed"
