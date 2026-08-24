#!/bin/sh
set -eu

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
bmk_path="$bmk_dir/$(basename -- "$1")"
sdk_root=$(CDPATH= cd -- "$bmk_dir/.." && pwd)
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)

if test -e "$output_root"
then
	echo "interface freshness test output already exists: $output_root" >&2
	exit 1
fi

test_sdk="$output_root/sdk"
mkdir -p "$test_sdk/bin" "$test_sdk/mod/bcc2manifesttest.mod"
ln -s "$bmk_path" "$test_sdk/bin/bmk"
ln -s "$bmk_dir/bcc" "$test_sdk/bin/bcc"
for config_path in "$bmk_dir"/*.bmk
do
	ln -s "$config_path" "$test_sdk/bin/$(basename -- "$config_path")"
done
ln -s "$sdk_root/mod/brl.mod" "$test_sdk/mod/brl.mod"
ln -s "$sdk_root/mod/pub.mod" "$test_sdk/mod/pub.mod"

provider_root="$test_sdk/mod/bcc2manifesttest.mod/interfacefreshness.mod"
consumer_root="$test_sdk/mod/bcc2manifesttest.mod/interfacefreshnessconsumer.mod"
mkdir -p "$provider_root" "$consumer_root"
cp "$fixture_dir/module_interface_freshness.bmx" "$provider_root/interfacefreshness.bmx"
cp "$fixture_dir/module_interface_freshness_consumer.bmx" "$consumer_root/interfacefreshnessconsumer.bmx"

"$test_sdk/bin/bmk" makemods -a -r BCC2ManifestTest.InterfaceFreshnessConsumer
freshness_interface=$(find "$provider_root" -maxdepth 1 -name 'interfacefreshness.release.*.i2' -type f)
test -f "$freshness_interface"
freshness_snapshot="$output_root/interfacefreshness.i2.snapshot"
cp -p "$freshness_interface" "$freshness_snapshot"

# A forced provider rebuild may regenerate compiler output, but a byte-identical
# compatibility interface must retain its timestamp.
"$test_sdk/bin/bmk" makemods -a -r BCC2ManifestTest.InterfaceFreshness
cmp "$freshness_interface" "$freshness_snapshot"
test ! "$freshness_interface" -nt "$freshness_snapshot"
test ! "$freshness_snapshot" -nt "$freshness_interface"

# An implementation-only change rebuilds the provider without invalidating the
# consumer's semantic compilation.
sleep 1
cp "$fixture_dir/module_interface_freshness_implementation.bmx" "$provider_root/interfacefreshness.bmx"
"$test_sdk/bin/bmk" makemods -r BCC2ManifestTest.InterfaceFreshness
cmp "$freshness_interface" "$freshness_snapshot"
implementation_consumer_output=$("$test_sdk/bin/bmk" makemods -r BCC2ManifestTest.InterfaceFreshnessConsumer)
if printf '%s' "$implementation_consumer_output" | grep -q 'Processing:interfacefreshnessconsumer.bmx'
then
	echo "implementation-only module change invalidated its consumer" >&2
	exit 1
fi

# A public API change must publish a new compatibility interface and invalidate
# the consumer. Native compilation may still be skipped when generated C is
# byte-identical because the new API is not used.
sleep 1
cp "$fixture_dir/module_interface_freshness_public.bmx" "$provider_root/interfacefreshness.bmx"
"$test_sdk/bin/bmk" makemods -r BCC2ManifestTest.InterfaceFreshness
if cmp -s "$freshness_interface" "$freshness_snapshot"
then
	echo "public module change did not update its compatibility interface" >&2
	exit 1
fi
test "$freshness_interface" -nt "$freshness_snapshot"
public_consumer_output=$("$test_sdk/bin/bmk" makemods -r BCC2ManifestTest.InterfaceFreshnessConsumer)
printf '%s' "$public_consumer_output" | grep -q 'Processing:interfacefreshnessconsumer.bmx'

echo "bmk bcc interface freshness tests passed"
