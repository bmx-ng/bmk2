#!/bin/sh
set -eu

bmk_path=$1
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)

test ! -e "$output_root"
mkdir -p "$output_root"
cp "$fixture_dir/application_header_freshness_app.bmx" "$output_root/"
cp "$fixture_dir/application_header_freshness_mid.bmx" "$output_root/"
cp "$fixture_dir/application_header_freshness_common_v1.bmx" "$output_root/application_header_freshness_common.bmx"

app_path="$output_root/application-header-freshness"
app_source="$output_root/application_header_freshness_app.bmx"
"$bmk_path" makeapp -r -o "$app_path" "$app_source"
test "$("$app_path" | tr -d '\r')" = "1"
app_object=$(find "$output_root/.bmx" -name 'application_header_freshness_app*.o' -type f | head -1)
test -f "$app_object"
old_object=$(cksum "$app_object")

sleep 1
cp "$fixture_dir/application_header_freshness_common_v2.bmx" "$output_root/application_header_freshness_common.bmx"
rebuild_output=$("$bmk_path" makeapp -r -o "$app_path" "$app_source")
printf '%s' "$rebuild_output" | grep -q 'Compiling:application_header_freshness_common.bmx.release.'
printf '%s' "$rebuild_output" | grep -q 'Compiling:application_header_freshness_mid.bmx.release.'
printf '%s' "$rebuild_output" | grep -q 'Compiling:application_header_freshness_app.bmx.console.release.'
test "$("$app_path" | tr -d '\r')" = "2"
test "$(cksum "$app_object")" != "$old_object"

no_op_output=$("$bmk_path" makeapp -r -o "$app_path" "$app_source")
test -z "$no_op_output"

echo "bmk generated header freshness tests passed"
