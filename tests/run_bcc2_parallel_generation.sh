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
source_root="$output_root/source"
application="$output_root/parallel-bmx-app"

cores=$("$bmk" -v | sed -n 's/.*(cpu x\([0-9][0-9]*\)).*/\1/p')
test -n "$cores"
maximum_workers=$((cores - 1))
if test "$maximum_workers" -lt 1
then
	maximum_workers=1
fi
default_workers=$maximum_workers
if test "$default_workers" -gt 4
then
	default_workers=4
fi

test ! -e "$output_root"
mkdir -p "$source_root"
cp "$fixture_dir/parallel_bmx_left.bmx" "$source_root/left.bmx"
cp "$fixture_dir/parallel_bmx_right.bmx" "$source_root/right.bmx"
cp "$fixture_dir/parallel_bmx_app.bmx" "$source_root/app.bmx"

BMK_TRACE_BUILD=1 BMK_BMX_WORKERS= "$bmk" makeapp -a -r -v -o "$application" "$source_root/app.bmx" > "$output_root/build.out"
grep -q "bmk: bmx compiler scheduling: $default_workers worker" "$output_root/build.out"
if test "$default_workers" -gt 1
then
	grep -Eq 'bmk: bmx compiler scheduling: [2-4] workers .*parallel batches, maximum width [2-9]' "$output_root/build.out"
fi
staging_leaves=$(sed -n 's|.*compiler staging root: .*/\([^/]*\)$|\1|p' "$output_root/build.out")
test -n "$staging_leaves"
for staging_leaf in $staging_leaves
do
	case "$staging_leaf" in
		.s-*-*) ;;
		*) echo "unexpected compiler staging leaf: $staging_leaf" >&2; exit 1 ;;
	esac
	test "${#staging_leaf}" -le 20
done
test "$("$application" | tr -d '\r\n')" = "42"

# A failing peer in the same parallel batch must not publish the successful
# peer's new bundle. Otherwise later quick builds can consume a mixture of old
# and new application interfaces even though the batch itself failed.
left_c=$(find "$source_root/.bmx" -maxdepth 1 -name 'left.bmx.release.*.c' -type f)
left_manifest=$(find "$source_root/.bmx" -maxdepth 1 -name 'left.bmx.release.*.bmxbuild' -type f)
test -f "$left_c"
test -f "$left_manifest"
left_c_before=$(cksum "$left_c")
left_manifest_before=$(cksum "$left_manifest")
sleep 1
cp "$fixture_dir/parallel_bmx_left_changed.bmx" "$source_root/left.bmx"
cp "$fixture_dir/parallel_bmx_right_invalid.bmx" "$source_root/right.bmx"
if BMK_BMX_WORKERS=4 BMK_BMX_DIAGNOSE_FAILURES=1 "$bmk" makeapp -r -o "$application" "$source_root/app.bmx" > "$output_root/failed-batch.out" 2>&1
then
	echo "parallel BMX batch unexpectedly accepted an invalid peer" >&2
	exit 1
fi
grep -q 'parallel bcc failure replay reproduced in a fresh compiler process' "$output_root/failed-batch.out"
test "$(cksum "$left_c")" = "$left_c_before"
test "$(cksum "$left_manifest")" = "$left_manifest_before"
test "$("$application" | tr -d '\r\n')" = "42"
test -z "$(find "$source_root" -name '.s-*' -type d -print)"
test -z "$(find "$source_root/.bmx" -name '*.bmxbuild.bmk-tmp-*.stage' -type d -print)"
test -z "$(find "$source_root/.bmx" -name '*.replay.stage' -type d -print)"
cp "$fixture_dir/parallel_bmx_right.bmx" "$source_root/right.bmx"

# A quick build must rediscover and compile a changed leaf after the parallel
# engines have populated their independent caches. The unchanged public
# signature also exercises the ordinary "implementation changed" path.
sleep 1
BMK_BMX_WORKERS=4 "$bmk" makeapp -r -v -o "$application" "$source_root/app.bmx" > "$output_root/quick-build.out"
grep -q 'Processing:left.bmx' "$output_root/quick-build.out"
test "$("$application" | tr -d '\r\n')" = "43"

unchanged_output=$(BMK_BMX_WORKERS=4 "$bmk" makeapp -r -o "$application" "$source_root/app.bmx")
if printf '%s' "$unchanged_output" | grep -Eq 'Processing:|Compiling:|Linking:'
then
	printf '%s\n' "$unchanged_output" >&2
	echo "unchanged parallel BMX application was rebuilt" >&2
	exit 1
fi

default_output=$(BMK_BMX_WORKERS= "$bmk" makeapp -r -v -o "$application" "$source_root/app.bmx")
printf '%s' "$default_output" | grep -q "bmk: bmx compiler scheduling: $default_workers worker"

one_output=$(BMK_BMX_WORKERS=1 "$bmk" makeapp -r -v -o "$application" "$source_root/app.bmx")
printf '%s' "$one_output" | grep -q 'bmk: bmx compiler scheduling: 1 worker '

maximum_output=$(BMK_BMX_WORKERS=999 "$bmk" makeapp -r -v -o "$application" "$source_root/app.bmx")
printf '%s' "$maximum_output" | grep -q "bmk: bmx compiler scheduling: $maximum_workers worker"

single_output=$(BMK_BMX_WORKERS=4 "$bmk" makeapp -single -r -v -o "$application" "$source_root/app.bmx")
printf '%s' "$single_output" | grep -q 'bmk: bmx compiler scheduling: 1 worker '

echo "bmk parallel BMX generation regression passed"
