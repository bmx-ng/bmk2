#!/bin/sh
set -eu

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
bmk_path="$bmk_dir/$(basename -- "$1")"
sdk_root=$(CDPATH= cd -- "$bmk_dir/.." && pwd)
output_root=$2
bcc_path=${3:-"$bmk_dir/bcc"}
fixture_root=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures/nested_modules" && pwd)

mkdir -p "$output_root/sdk/bin" "$output_root/sdk/mod" "$output_root/apps"
cp "$bmk_path" "$output_root/sdk/bin/bmk"
ln -s "$bcc_path" "$output_root/sdk/bin/bcc"
for config_path in "$bmk_dir"/*.bmk
do
	ln -s "$config_path" "$output_root/sdk/bin/$(basename -- "$config_path")"
done
for module_family in "$sdk_root/mod"/*
do
	ln -s "$module_family" "$output_root/sdk/mod/$(basename -- "$module_family")"
done
cp -R "$fixture_root/nestedaudit.mod" "$output_root/sdk/mod/"
cp "$fixture_root"/*_app.bmx "$fixture_root"/*_child.bmx "$fixture_root"/*_parent.bmx "$output_root/apps/"

bmk="$output_root/sdk/bin/bmk"

# Targeted and filtered all-module discovery must both reach arbitrary depth.
"$bmk" makemods -a -r NestedAudit.Parent
"$bmk" makemods -a -r NestedAudit.Parent.Child
"$bmk" makemods -a -r NestedAudit.Space.Only.Leaf
"$bmk" makemods -a -r NestedAudit.Very.Deep.Module.Tree.Leaf
"$bmk" makemods -a -r nestedaudit.

# Build both modes and both threading configurations across the nested boundary.
"$bmk" makemods -a NestedAudit.Parent.Child
"$bmk" makemods -a -single -r NestedAudit.Parent.Child
"$bmk" makemods -a -single NestedAudit.Parent.Child

# Logical namespaces participate in ABI identity, while archive and interface
# filenames remain based on the concrete module's leaf name.
child_release_archive=$(find "$output_root/sdk/mod/nestedaudit.mod/parent.mod/child.mod" -maxdepth 1 -name 'child.release.*.a' -type f | head -n 1)
deep_release_archive=$(find "$output_root/sdk/mod/nestedaudit.mod/very.mod/deep.mod/module.mod/tree.mod/leaf.mod" -maxdepth 1 -name 'leaf.release.*.a' -type f | head -n 1)
test -f "$child_release_archive"
test -f "$deep_release_archive"
nm "$child_release_archive" | grep -q 'nestedaudit_parent_child_ChildValue'
nm "$deep_release_archive" | grep -q 'nestedaudit_very_deep_module_tree_leaf_TMyDeepType'

parent_app="$output_root/apps/parent-app"
child_app="$output_root/apps/child-app"
siblings_app="$output_root/apps/siblings-app"
"$bmk" makeapp -single -r -o "$parent_app" "$output_root/apps/parent_app.bmx"
"$bmk" makeapp -r -o "$child_app" "$output_root/apps/child_app.bmx"
"$bmk" makeapp -single -o "$siblings_app" "$output_root/apps/siblings_app.bmx"
test "$("$parent_app" | tr -d '\r\n')" = "10"
test "$("$child_app" | tr -d '\r\n')" = "42:nestednested!"
test "$("$siblings_app" | tr -d '\r\n')" = "16"

# Namespace hierarchy alone neither exposes nor links the other module.
if "$bmk" makeapp -single -r -o "$output_root/apps/invalid-parent" "$output_root/apps/parent_cannot_see_child.bmx" >"$output_root/parent-visibility.log" 2>&1
then
	echo "parent import unexpectedly exposed its child module" >&2
	exit 1
fi
if "$bmk" makeapp -single -r -o "$output_root/apps/invalid-child" "$output_root/apps/child_cannot_see_parent.bmx" >"$output_root/child-visibility.log" 2>&1
then
	echo "child import unexpectedly exposed its parent module" >&2
	exit 1
fi
grep -q 'ChildValue' "$output_root/parent-visibility.log"
grep -q 'ParentValue' "$output_root/child-visibility.log"
if nm "$parent_app" | grep -q 'nestedaudit_parent_child'
then
	echo "parent-only application linked child module symbols" >&2
	exit 1
fi
if nm "$child_app" | grep -q 'nestedaudit_parent_ParentValue'
then
	echo "child-only application linked parent module symbols" >&2
	exit 1
fi

# An unchanged graph is a no-op. Editing the child rebuilds its dependant but
# does not invalidate the independent parent archive.
parent_archive=$(find "$output_root/sdk/mod/nestedaudit.mod/parent.mod" -maxdepth 1 -name 'parent.release.*.a' -type f | head -n 1)
child_archive=$child_release_archive
test -f "$parent_archive"
test -f "$child_archive"
noop_marker="$output_root/noop-marker"
touch "$noop_marker"
noop_output=$("$bmk" makeapp -r -o "$child_app" "$output_root/apps/child_app.bmx")
if printf '%s' "$noop_output" | grep -Eq '(Processing|Compiling):(child|helper)\.bmx|Archiving:child\.'
then
	echo "unchanged nested module rebuilt" >&2
	exit 1
fi
test ! "$child_archive" -nt "$noop_marker"
freshness_marker="$output_root/freshness-marker"
touch "$freshness_marker"
sleep 1
printf "\n' incremental nested child edit\n" >> "$output_root/sdk/mod/nestedaudit.mod/parent.mod/child.mod/helper.bmx"
incremental_output=$("$bmk" makeapp -r -o "$child_app" "$output_root/apps/child_app.bmx")
printf '%s' "$incremental_output" | grep -q 'Processing:helper.bmx'
test ! "$parent_archive" -nt "$freshness_marker"
test "$child_archive" -nt "$freshness_marker"

# Mismatched declarations report both identities.
mkdir -p "$output_root/sdk/mod/mismatch.mod/path.mod/leaf.mod"
printf 'SuperStrict\nModule Mismatch.Path.Wrong\n' > "$output_root/sdk/mod/mismatch.mod/path.mod/leaf.mod/leaf.bmx"
if "$bmk" makemods -a -r Mismatch.Path.Leaf >"$output_root/mismatch.log" 2>&1
then
	echo "mismatched nested module declaration unexpectedly built" >&2
	exit 1
fi
grep -q "Module declaration 'mismatch.path.wrong' does not match path-derived module name 'mismatch.path.leaf'" "$output_root/mismatch.log"

# Packaging an exact parent module must not bundle its descendant modules.
parent_package="$output_root/nested-parent.zap"
parent_release_interface=$(find "$output_root/sdk/mod/nestedaudit.mod/parent.mod" -maxdepth 1 -name 'parent.release.*.i' -type f | head -n 1)
parent_target=$(basename "$parent_release_interface")
parent_target=${parent_target#parent.release.}
parent_target=${parent_target%.i}
parent_platform=${parent_target%%.*}
parent_architecture=${parent_target#*.}
"$bmk" zapmod -l "$parent_platform" -g "$parent_architecture" NestedAudit.Parent "$parent_package"
"$bmk" unzapmod "$parent_package"
test -f "$output_root/sdk/mod/nestedaudit.mod/parent.mod/parent.bmx"
test ! -e "$output_root/sdk/mod/nestedaudit.mod/parent.mod/child.mod"

# Case variants remain one logical identity. Filesystems which permit both
# physical spellings must report an ambiguity instead of choosing either one.
mkdir -p "$output_root/sdk/mod/caseclash.mod/leaf.mod" "$output_root/sdk/mod/CaseClash.mod/Leaf.mod"
printf 'SuperStrict\nModule CaseClash.Leaf\n' > "$output_root/sdk/mod/caseclash.mod/leaf.mod/leaf.bmx"
printf 'SuperStrict\nModule CaseClash.Leaf\n' > "$output_root/sdk/mod/CaseClash.mod/Leaf.mod/Leaf.bmx"
case_directory_count=$(find "$output_root/sdk/mod" -maxdepth 1 -type d -iname 'caseclash.mod' | wc -l | tr -d ' ')
if test "$case_directory_count" -gt 1
then
	if "$bmk" makemods -a -r CaseClash.Leaf >"$output_root/case-ambiguous.log" 2>&1
	then
		echo "case-insensitive duplicate module identity unexpectedly built" >&2
		exit 1
	fi
	grep -qi "Ambiguous module 'caseclash.leaf'" "$output_root/case-ambiguous.log"
fi

# A physical directory level represents one identifier. Dotted legacy-style
# basenames are rejected rather than treated as alternate namespace layouts.
mkdir -p "$output_root/sdk/mod/legacy.name.mod/leaf.mod"
printf 'SuperStrict\nModule Legacy.Name.Leaf\n' > "$output_root/sdk/mod/legacy.name.mod/leaf.mod/leaf.bmx"
if "$bmk" makemods -a -r Legacy.Name.Leaf >"$output_root/invalid-directory.log" 2>&1
then
	echo "dotted .mod directory basename unexpectedly accepted" >&2
	exit 1
fi
grep -q "basename 'legacy.name' must be a single BlitzMax identifier" "$output_root/invalid-directory.log"

printf 'nested module integration passed\n'
