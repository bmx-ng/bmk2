#!/bin/sh
set -eu

bmk=$1
temporary=$2
sdk=$3
mkdir -p "$temporary"

test_sdk="$temporary/sdk"
mkdir -p "$test_sdk/bin"
cp "$bmk" "$test_sdk/bin/bmk"
ln -s "$sdk/mod" "$test_sdk/mod"
for config in "$sdk/bin"/*.bmk
do
	ln -s "$config" "$test_sdk/bin/$(basename "$config")"
done
bmk="$test_sdk/bin/bmk"

desktop_log="$temporary/deviceinfo-desktop.log"
if "$bmk" deviceinfo >"$desktop_log" 2>&1
then
	echo "deviceinfo unexpectedly accepted a desktop target" >&2
	exit 1
fi
grep -q 'deviceinfo is available only for embedded device targets' "$desktop_log"

source_log="$temporary/deviceinfo-source.log"
if "$bmk" deviceinfo -l esp32 unwanted.bmx >"$source_log" 2>&1
then
	echo "deviceinfo unexpectedly accepted a source file" >&2
	exit 1
fi
grep -q 'deviceinfo does not accept a source file' "$source_log"

board_desktop_log="$temporary/boardinfo-desktop.log"
if "$bmk" boardinfo >"$board_desktop_log" 2>&1
then
	echo "boardinfo unexpectedly accepted a desktop target" >&2
	exit 1
fi
grep -q 'boardinfo is currently available only for the esp32 target' "$board_desktop_log"

board_log="$temporary/boardinfo-baguette-s3.log"
"$bmk" boardinfo -l esp32 -board baguette_s3 >"$board_log"
grep -q 'Baguette S3 (baguette_s3)' "$board_log"
grep -q 'SDA (GPIO47)' "$board_log"
grep -q 'LED (GPIO8)' "$board_log"

manual_idf="$temporary/manual/esp-idf-v6.1"
manual_home="$temporary/manual-home"
manual_tools="$manual_home/.espressif"
manual_python="$manual_tools/python_env/idf6.1_py3.10_env"
mkdir -p "$manual_idf/tools/cmake" "$manual_tools/tools" "$manual_python/bin"
touch "$manual_idf/tools/idf.py"
printf '%s\n' 'set(IDF_VERSION_MAJOR 6)' 'set(IDF_VERSION_MINOR 1)' 'set(IDF_VERSION_PATCH 0)' >"$manual_idf/tools/cmake/version.cmake"
cp "$(dirname "$0")/fixtures/fake_esp32_python.sh" "$manual_python/bin/python"
chmod +x "$manual_python/bin/python"
printf '%s\n' '6.1' >"$manual_python/idf_version.txt"

manual_log="$temporary/deviceinfo-manual-layout.log"
HOME="$manual_home" IDF_PATH="$manual_idf" IDF_TOOLS_PATH= IDF_PYTHON_ENV_PATH= \
	"$bmk" deviceinfo -l esp32 >"$manual_log"
grep -q 'Port: /dev/ttyACM0' "$manual_log"
grep -q 'Chip: ESP32-S3' "$manual_log"
grep -q 'Flash: 8MB' "$manual_log"

echo "bmk deviceinfo and boardinfo command validation passed"
