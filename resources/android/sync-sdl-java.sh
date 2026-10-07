#!/bin/sh
set -eu

if [ "$#" -ne 2 ] || { [ "$1" != "check" ] && [ "$1" != "update" ]; }; then
	echo "usage: $0 check|update /path/to/SDL3" >&2
	exit 2
fi

mode=$1
sdl_root=$2
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_dir=$sdl_root/android-project/app/src/main/java/org/libsdl/app
target_dir=$script_dir/android-project/app/src/main/java/org/libsdl/app

if [ ! -d "$source_dir" ]; then
	echo "SDL Android Java directory not found: $source_dir" >&2
	exit 2
fi

if [ "$mode" = "update" ]; then
	cp "$source_dir"/*.java "$target_dir"/
fi

if ! diff -qr "$source_dir" "$target_dir"; then
	echo "SDL Android Java baseline differs; run the update command and review the result." >&2
	exit 1
fi

echo "SDL Android Java baseline matches $sdl_root"
