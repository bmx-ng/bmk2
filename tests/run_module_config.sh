#!/bin/sh
set -eu
bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
sdk_root=$(CDPATH= cd -- "$bmk_dir/.." && pwd)
out=$2
fixtures=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures/module_config" && pwd)
test ! -e "$out"
mkdir -p "$out/sdk/bin" "$out/sdk/mod" "$out/apps"
for file in "$bmk_dir"/*; do ln -s "$file" "$out/sdk/bin/$(basename -- "$file")"; done
# Use the test binary as this isolated SDK's bmk.
rm "$out/sdk/bin/bmk"
cp "$1" "$out/sdk/bin/bmk"
for module in "$sdk_root/mod"/*; do ln -s "$module" "$out/sdk/mod/$(basename -- "$module")"; done
cp -R "$fixtures/configaudit.mod" "$out/sdk/mod/"
cp "$fixtures/app.bmx" "$out/apps/"
bmk="$out/sdk/bin/bmk"
module="$out/sdk/mod/configaudit.mod/choice.mod"
run_build() {
	"$bmk" makeapp -r -o "$out/app" "$out/apps/app.bmx" > "$out/$1.log" 2>&1
	test "$("$out/app" | tr -d '\r')" = "$2"
}
run_build default 118
run_build cached 118
if grep -E 'Processing:|Compiling:|Linking:' "$out/cached.log"; then echo 'Unchanged build was not cached'; exit 1; fi
printf 'setoption backend two\nadddef config_two=0\n' > "$out/apps/pre.bmk"
run_build override 229
run_build override_cached 229
if grep -E 'Processing:|Compiling:|Linking:' "$out/override_cached.log"; then exit 1; fi
rm "$out/apps/pre.bmk"
run_build override_removed 118
printf 'setoption backend two\nadddef config_two=0\n' > "$out/apps/pre.bmk"
# makemods has no application pre.bmk, so change the module's default itself.
sed 's/backend = "one"/backend = "two"/' "$fixtures/configaudit.mod/choice.mod/module.bmk" > "$module/module.bmk"
"$bmk" makemods -r configaudit.choice > "$out/makemods.log" 2>&1
run_build after_makemods 229
rm "$out/apps/pre.bmk" "$module/module.bmk"
run_build all_removed 118
printf 'setoption backend broken\n' > "$out/apps/pre.bmk"
cp "$fixtures/configaudit.mod/choice.mod/module.bmk" "$module/module.bmk"
if "$bmk" makeapp -r -o "$out/app" "$out/apps/app.bmx" > "$out/invalid.log" 2>&1; then echo 'Invalid config succeeded'; exit 1; fi
grep -q "Invalid backend: broken" "$out/invalid.log"
rm "$out/apps/pre.bmk"
run_build recovered 118
# Syntax errors and unknown commands must fail before compilation.
printf '@define broken\n local value = )\n@end\n' > "$module/module.bmk"
if "$bmk" makeapp -r -o "$out/app" "$out/apps/app.bmx" > "$out/syntax.log" 2>&1; then exit 1; fi
printf 'unknownmodulecommand\n' > "$module/module.bmk"
if "$bmk" makeapp -r -o "$out/app" "$out/apps/app.bmx" > "$out/unknown.log" 2>&1; then exit 1; fi
cp "$fixtures/configaudit.mod/choice.mod/module.bmk" "$module/module.bmk"
run_build final_recovery 118
# Debug and release builds use independent configuration stamps.
"$bmk" makeapp -o "$out/debug-app" "$out/apps/app.bmx" > "$out/debug.log" 2>&1
test "$("$out/debug-app" | tr -d '\r')" = 118
mkdir -p "$module/examples"
cp "$fixtures/app.bmx" "$module/examples/app.bmx"
"$bmk" makeapp -r -o "$out/example-app" "$module/examples/app.bmx" > "$out/example.log" 2>&1
test "$("$out/example-app" | tr -d '\r')" = 118
echo 'Module configuration integration tests passed'
