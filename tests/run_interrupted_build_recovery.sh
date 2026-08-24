#!/bin/sh
set -eu

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
bmk_path="$bmk_dir/$(basename -- "$1")"
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)
wrapper="$fixture_dir/interrupting_compiler.sh"

test ! -e "$output_root"
mkdir -p "$output_root/project"

case "$(uname -s):$(uname -m)" in
	Darwin:arm64) build_name=macos.arm64 ;;
	Darwin:x86_64) build_name=macos.x64 ;;
	Linux:aarch64) build_name=linux.arm64 ;;
	Linux:x86_64) build_name=linux.x64 ;;
	*) echo "unsupported interrupted recovery test host" >&2; exit 1 ;;
esac

real_cc=$(command -v cc)
real_cxx=$(command -v c++)
source_path="$output_root/project/interrupted_recovery.bmx"
app_path="$output_root/project/interrupted-recovery"
marker="$output_root/interrupt.marker"
custom_path="$bmk_dir/custom.bmk"
saved_custom_path="$custom_path.interrupted-test-save"
test ! -e "$saved_custom_path"
if test -e "$custom_path" || test -L "$custom_path"
then
	mv "$custom_path" "$saved_custom_path"
fi
trap 'rm -f "$custom_path"; if test -e "$saved_custom_path" || test -L "$saved_custom_path"; then mv "$saved_custom_path" "$custom_path"; fi' EXIT HUP INT TERM

cp "$fixture_dir/interrupted_recovery_v1.bmx" "$source_path"
"$bmk_path" makeapp -r -o "$app_path" "$source_path"
test "$("$app_path" | tr -d '\r')" = "1"
object_path=$(find "$output_root/project/.bmx" -name 'interrupted_recovery*.o' -type f | head -1)
test -f "$object_path"
object_v1=$(cksum "$object_path")
app_v1=$(cksum "$app_path")

printf 'setoption %s.gcc "%s"\n' "$build_name" "$wrapper" > "$custom_path"
sleep 1
cp "$fixture_dir/interrupted_recovery_v2.bmx" "$source_path"
BMK_INTERRUPT_MODE=compile BMK_INTERRUPT_MARKER="$marker" BMK_REAL_COMPILER="$real_cc" \
	"$bmk_path" makeapp -quick -r -o "$app_path" "$source_path" &
build_pid=$!
while test ! -s "$marker"
do
	if ! kill -0 "$build_pid" 2>/dev/null
	then
		echo "build exited before compiler interruption" >&2
		exit 1
	fi
	sleep 0.05
done
compiler_pid=$(cat "$marker")
kill "$compiler_pid" 2>/dev/null || true
kill "$build_pid" 2>/dev/null || true
wait "$build_pid" 2>/dev/null || true
test "$(cksum "$object_path")" = "$object_v1"
test "$(cksum "$app_path")" = "$app_v1"
object_temporary=$(find "$(dirname -- "$object_path")" -name "$(basename -- "$object_path").bmk-tmp-*" -type f)
test -f "$object_temporary"

BMK_REAL_COMPILER="$real_cc" "$bmk_path" makeapp -r -o "$app_path" "$source_path"
test "$("$app_path" | tr -d '\r')" = "2"
test "$(cksum "$object_path")" != "$object_v1"
# A uniquely named output abandoned by a terminated process is inert. It must
# neither replace the published object nor collide with the recovery writer.
test -f "$object_temporary"
rm "$object_temporary"
app_v2=$(cksum "$app_path")

printf 'setoption %s.gpp "%s"\n' "$build_name" "$wrapper" > "$custom_path"
sleep 1
cp "$fixture_dir/interrupted_recovery_v3.bmx" "$source_path"
: > "$marker"
BMK_INTERRUPT_MODE=link BMK_INTERRUPT_MARKER="$marker" BMK_REAL_COMPILER="$real_cxx" \
	"$bmk_path" makeapp -quick -r -o "$app_path" "$source_path" &
build_pid=$!
while test ! -s "$marker"
do
	if ! kill -0 "$build_pid" 2>/dev/null
	then
		echo "build exited before linker interruption" >&2
		exit 1
	fi
	sleep 0.05
done
compiler_pid=$(cat "$marker")
kill "$compiler_pid" 2>/dev/null || true
kill "$build_pid" 2>/dev/null || true
wait "$build_pid" 2>/dev/null || true
test "$(cksum "$app_path")" = "$app_v2"
app_temporary=$(find "$(dirname -- "$app_path")" -name "$(basename -- "$app_path").bmk-tmp-*" -type f)
test -f "$app_temporary"

BMK_REAL_COMPILER="$real_cxx" "$bmk_path" makeapp -r -o "$app_path" "$source_path"
test "$("$app_path" | tr -d '\r')" = "3"
test "$(cksum "$app_path")" != "$app_v2"
test -f "$app_temporary"
rm "$app_temporary"

echo "bmk interrupted build recovery tests passed"
