#!/bin/sh
set -eu

bmk_path=$1
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)

mkdir -p "$output_root"
app_root="$output_root/application"
mkdir -p "$app_root"
cp "$fixture_dir/application_nested_app.bmx" "$app_root/app.bmx"
cp -R "$fixture_dir/nested" "$app_root/nested"

app_path="$app_root/application"
"$bmk_path" makeapp -single -r -o "$app_path" "$app_root/app.bmx"
test "$("$app_path" | tr -d '\r')" = "bcc2 nested quoted application ok"

touch "$app_root/.bmx/root-stale"
touch "$app_root/nested/left/.bmx/left-stale"
touch "$app_root/nested/right/.bmx/right-stale"
mkdir -p "$app_root/unrelated/.bmx" "$app_root/.generics" "$app_root/generics"
touch "$app_root/unrelated/.bmx/preserve"
touch "$app_root/.generics/preserve"
touch "$app_root/generics/preserve"

clean_output=$("$bmk_path" makeapp -clean -single -r -v -o "$app_path" "$app_root/app.bmx")
printf '%s\n' "$clean_output"
test ! -e "$app_root/.bmx/root-stale"
test ! -e "$app_root/nested/left/.bmx/left-stale"
test ! -e "$app_root/nested/right/.bmx/right-stale"
test -e "$app_root/unrelated/.bmx/preserve"
test -e "$app_root/.generics/preserve"
test -e "$app_root/generics/preserve"
test "$("$app_path" | tr -d '\r')" = "bcc2 nested quoted application ok"

stable_output=$("$bmk_path" makeapp -single -r -o "$app_path" "$app_root/app.bmx")
if printf '%s' "$stable_output" | grep -Eq 'Processing:|Compiling:|Linking:'
then
	echo "clean application build did not converge to a no-op build" >&2
	exit 1
fi

touch "$app_root/.bmx/preserve-output-guard"
if "$bmk_path" makeapp -clean -single -r -o "$app_root/.bmx/application" "$app_root/app.bmx" >"$output_root/output-guard.log" 2>&1
then
	echo "clean application unexpectedly removed a cache containing its requested output" >&2
	exit 1
fi
grep -q 'BMKCLEAN009 refusing to clean an application cache containing the requested output' "$output_root/output-guard.log"
test -e "$app_root/.bmx/preserve-output-guard"

link_root="$output_root/root-link"
external_root="$output_root/root-link-external"
mkdir -p "$link_root" "$external_root"
cp "$fixture_dir/application_nested_app.bmx" "$link_root/app.bmx"
cp -R "$fixture_dir/nested" "$link_root/nested"
touch "$external_root/preserve"
if ln -s "$external_root" "$link_root/.bmx" 2>/dev/null
then
	if "$bmk_path" makeapp -clean -single -r -o "$link_root/application" "$link_root/app.bmx" >"$output_root/root-link.log" 2>&1
	then
		echo "clean application unexpectedly followed a cache-directory link" >&2
		exit 1
	fi
	grep -q 'BMKCLEAN002 refusing symbolic application cache directory' "$output_root/root-link.log"
	test -L "$link_root/.bmx"
	test -e "$external_root/preserve"
	test ! -e "$link_root/application"
fi

inner_root="$output_root/inner-link"
inner_external_root="$output_root/inner-link-external"
mkdir -p "$inner_root/.bmx" "$inner_external_root"
cp "$fixture_dir/application_nested_app.bmx" "$inner_root/app.bmx"
cp -R "$fixture_dir/nested" "$inner_root/nested"
touch "$inner_root/.bmx/would-delete"
touch "$inner_external_root/preserve"
if ln -s "$inner_external_root" "$inner_root/.bmx/linked" 2>/dev/null
then
	if "$bmk_path" makeapp -clean -single -r -o "$inner_root/application" "$inner_root/app.bmx" >"$output_root/inner-link.log" 2>&1
	then
		echo "clean application unexpectedly accepted a link inside a cache" >&2
		exit 1
	fi
	grep -q 'BMKCLEAN002 refusing symbolic link inside application cache' "$output_root/inner-link.log"
	test -e "$inner_root/.bmx/would-delete"
	test -L "$inner_root/.bmx/linked"
	test -e "$inner_external_root/preserve"
	test ! -e "$inner_root/application"
fi

echo "bmk clean application tests passed"
