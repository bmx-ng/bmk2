#!/bin/sh
set -eu

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
bmk_path="$bmk_dir/$(basename -- "$1")"
sdk_root=$(CDPATH= cd -- "$bmk_dir/.." && pwd)
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)
bcc_name=bcc
if test -f "$bmk_dir/bcc.exe"
then
	bcc_name=bcc.exe
fi

link_sdk_native_toolchains()
{
	target_root=$1
	for toolchain_name in MinGW32x64 MinGW32x86 MinGW32 llvm-mingw
	do
		if test -d "$sdk_root/$toolchain_name"
		then
			ln -s "$sdk_root/$toolchain_name" "$target_root/$toolchain_name"
		fi
	done
}

sdk_nm=
for nm_candidate in \
	"$sdk_root/MinGW32x64/bin/nm.exe" \
	"$sdk_root/MinGW32x64/bin/llvm-nm.exe" \
	"$sdk_root/MinGW32x64/bin/x86_64-w64-mingw32-nm.exe" \
	"$sdk_root/MinGW32x86/bin/nm.exe" \
	"$sdk_root/MinGW32x86/bin/i686-w64-mingw32-nm.exe" \
	"$sdk_root/MinGW32/bin/nm.exe" \
	"$sdk_root/llvm-mingw/bin/llvm-nm.exe" \
	"$sdk_root/llvm-mingw/bin/x86_64-w64-mingw32-nm.exe"
do
	if test -f "$nm_candidate"
	then
		sdk_nm=$nm_candidate
		break
	fi
done
if test -z "$sdk_nm"
then
	sdk_nm=$(command -v nm || true)
fi
if test -z "$sdk_nm"
then
	echo "a native symbol-table reader was not found in the SDK or PATH" >&2
	exit 1
fi

nm()
{
	nm_target=$1
	shift
	if test "$bcc_name" = bcc.exe && test -f "$nm_target.exe"
	then
		nm_target=$nm_target.exe
	fi
	"$sdk_nm" "$nm_target" "$@" | tr -d '\r'
}

mkdir -p "$output_root"
cp "$fixture_dir"/generic_*.bmx "$output_root/"

canonical_sdk="$output_root/canonical-sdk"
mkdir -p "$canonical_sdk/bin"
cp "$bmk_path" "$canonical_sdk/bin/bmk"
ln -s "$bmk_dir/$bcc_name" "$canonical_sdk/bin/$bcc_name"
ln -s "$sdk_root/mod" "$canonical_sdk/mod"
link_sdk_native_toolchains "$canonical_sdk"
for config_path in "$bmk_dir"/*.bmk
do
	ln -s "$config_path" "$canonical_sdk/bin/$(basename -- "$config_path")"
done
test ! -e "$canonical_sdk/bin/bcc2"
default_root="$output_root/default-canonical"
mkdir -p "$default_root"
cp "$fixture_dir"/generic_*.bmx "$default_root/"
default_app="$default_root/default-canonical-app"
"$canonical_sdk/bin/bmk" makeapp -single -r -o "$default_app" "$default_root/generic_app.bmx"
"$default_app"
default_manifest=$(find "$default_root/.bmx" -name 'generic_app*.bmxbuild' -type f)
test -f "$default_manifest"
default_generated_c=$(find "$default_root/.bmx" -name 'generic_app*.c' -type f | head -n 1)
test -f "$default_generated_c"
printf '\n/* deliberate manifest digest mismatch */\n' >> "$default_generated_c"
default_repair_output=$("$canonical_sdk/bin/bmk" makeapp -single -r -o "$default_app" "$default_root/generic_app.bmx")
printf '%s' "$default_repair_output" | grep -q 'Processing:generic_app.bmx'
default_stable_output=$("$canonical_sdk/bin/bmk" makeapp -single -r -o "$default_app" "$default_root/generic_app.bmx")
if printf '%s' "$default_stable_output" | grep -Eq 'Processing:|Compiling:|Linking:'
then
	echo "manifest digest repair did not converge to a no-op build" >&2
	exit 1
fi

# A forced build must recover from valid manifests in separate application
# output roots that publish different C for the same cache key. This models a
# compiler upgrade interrupted after only part of a large application graph was
# regenerated. A normal build remains strict, while -a treats only manifests it
# is about to republish as provisional and preserves unrelated cache contents.
forced_root="$output_root/forced-conflict"
mkdir -p "$forced_root/forced_conflict"
cp "$fixture_dir/forced_conflict_app.bmx" "$forced_root/app.bmx"
cp "$fixture_dir/forced_conflict/shared.bmx" "$forced_root/forced_conflict/shared.bmx"
cp -R "$fixture_dir/forced_conflict/left" "$forced_root/forced_conflict/left"
cp -R "$fixture_dir/forced_conflict/right" "$forced_root/forced_conflict/right"
forced_app="$forced_root/application"
"$bmk_path" makeapp -single -r -o "$forced_app" "$forced_root/app.bmx"
test "$("$forced_app" | tr -d '\r\n')" = "forced-specialization-conflict-ok"

forced_left_manifest=$(find "$forced_root/forced_conflict/left/.bmx" -name '*.bmxbuild' -type f)
forced_right_manifest=$(find "$forced_root/forced_conflict/right/.bmx" -name '*.bmxbuild' -type f)
forced_common_pair=$(awk '$1=="link" { print $2, $3 }' "$forced_left_manifest" "$forced_right_manifest" | sort | uniq -d)
test -n "$forced_common_pair"
forced_target_cache=${forced_common_pair%% *}
forced_other_pair=$(awk -v target="$forced_target_cache" '$1=="link" && $2!=target { print $2, $3; exit }' "$forced_left_manifest")
test -n "$forced_other_pair"
forced_other_cache=${forced_other_pair%% *}
forced_target_digest=$(awk -v key="$forced_target_cache" '$1=="file" && $2=="generic-specialization-c" && $4==key { print $3; exit }' "$forced_left_manifest")
forced_other_digest=$(awk -v key="$forced_other_cache" '$1=="file" && $2=="generic-specialization-c" && $4==key { print $3; exit }' "$forced_left_manifest")
test -n "$forced_target_digest"
test -n "$forced_other_digest"
cp "$forced_root/forced_conflict/left/.bmx/.generics/units/$forced_other_cache.c" "$forced_root/forced_conflict/left/.bmx/.generics/units/$forced_target_cache.c"
sed "s/file generic-specialization-c $forced_target_digest $forced_target_cache /file generic-specialization-c $forced_other_digest $forced_target_cache /" "$forced_left_manifest" > "$forced_left_manifest.tmp"
mv "$forced_left_manifest.tmp" "$forced_left_manifest"
touch "$forced_root/forced_conflict/left/.bmx/preserve-forced"

forced_conflict_output="$forced_root/conflict.log"
if "$bmk_path" makeapp -single -r -o "$forced_app" "$forced_root/app.bmx" >"$forced_conflict_output" 2>&1
then
	echo "ordinary build unexpectedly accepted conflicting generated implementations" >&2
	exit 1
fi
grep -q 'BMKGEN038 conflicting generated implementations' "$forced_conflict_output"
grep -q "$forced_left_manifest" "$forced_conflict_output"
grep -q "$forced_right_manifest" "$forced_conflict_output"

forced_repair_output=$("$bmk_path" makeapp -a -single -r -o "$forced_app" "$forced_root/app.bmx")
printf '%s\n' "$forced_repair_output"
test -e "$forced_root/forced_conflict/left/.bmx/preserve-forced"
test "$("$forced_app" | tr -d '\r\n')" = "forced-specialization-conflict-ok"

missing_sdk="$output_root/missing-bcc-sdk"
mkdir -p "$missing_sdk/bin"
cp "$bmk_path" "$missing_sdk/bin/bmk"
ln -s "$sdk_root/mod" "$missing_sdk/mod"
link_sdk_native_toolchains "$missing_sdk"
for config_path in "$bmk_dir"/*.bmk
do
	ln -s "$config_path" "$missing_sdk/bin/$(basename -- "$config_path")"
done
missing_output="$output_root/missing-bcc-output.txt"
if "$missing_sdk/bin/bmk" makeapp -single -r -o "$output_root/missing-bcc-app" "$output_root/generic_app.bmx" >"$missing_output" 2>&1
then
	echo "canonical-only bmk unexpectedly built without bin/bcc" >&2
	exit 1
fi
grep -q 'BMKGEN030 bcc compiler was not found' "$missing_output"

variant_root="$output_root/build-variants"
mkdir -p "$variant_root"
cp "$fixture_dir/generic_variant_app.bmx" "$variant_root/"
variant_source="$variant_root/generic_variant_app.bmx"
variant_release_path="$variant_root/generic-variant-release"
variant_debug_path="$variant_root/generic-variant-debug"
"$bmk_path" makeapp -bcc2 -single -r -o "$variant_release_path" "$variant_source"
"$variant_release_path"
"$bmk_path" makeapp -bcc2 -single -o "$variant_debug_path" "$variant_source"
"$variant_debug_path"
variant_release_manifest=$(find "$variant_root/.bmx" -name 'generic_variant_app.bmx.console.release.*.bmxbuild' -type f)
variant_debug_manifest=$(find "$variant_root/.bmx" -name 'generic_variant_app.bmx.console.debug.*.bmxbuild' -type f)
variant_release_cache=$(awk '$1 == "link" { print $2; exit }' "$variant_release_manifest")
variant_debug_cache=$(awk '$1 == "link" { print $2; exit }' "$variant_debug_manifest")
variant_release_identity=$(awk '$1 == "link" { print $3; exit }' "$variant_release_manifest")
variant_debug_identity=$(awk '$1 == "link" { print $3; exit }' "$variant_debug_manifest")
variant_release_source=$(awk '$1 == "link" { print $4; exit }' "$variant_release_manifest")
variant_debug_source=$(awk '$1 == "link" { print $4; exit }' "$variant_debug_manifest")
test "$variant_release_identity" = "$variant_debug_identity"
test "$variant_release_cache" != "$variant_debug_cache"
test "$variant_release_source" != "$variant_debug_source"

configuration_root="$output_root/configuration-transition"
mkdir -p "$configuration_root"
cp "$fixture_dir/configuration_transition.bmx" "$configuration_root/"
configuration_source="$configuration_root/configuration_transition.bmx"
configuration_app="$configuration_root/configuration-transition"
"$bmk_path" makeapp -single -r -o "$configuration_app" "$configuration_source"
test "$("$configuration_app" | tr -d '\r')" = "0"
"$bmk_path" makeapp -single -r -gdb -o "$configuration_app" "$configuration_source"
test "$("$configuration_app" | tr -d '\r')" = "1"
"$bmk_path" makeapp -single -r -o "$configuration_app" "$configuration_source"
test "$("$configuration_app" | tr -d '\r')" = "0"

app_path="$output_root/generic-app"
"$bmk_path" makeapp -bcc2 -single -r -gdb -o "$app_path" "$output_root/generic_app.bmx"
"$app_path"

# Missing specialization objects are repaired as one or more native worker
# batches. Cache sidecars are published only after every object in a batch has
# completed successfully.
parallel_specialization_object_count=$(find "$output_root/.bmx/.generics/objects" -name '*.o' -type f | wc -l | tr -d ' ')
test "$parallel_specialization_object_count" -gt 1
find "$output_root/.bmx/.generics/objects" \( -name '*.o' -o -name '*.bcc2key' \) -type f -delete
parallel_specialization_output=$("$bmk_path" makeapp -v -bcc2 -r -gdb -o "$app_path" "$output_root/generic_app.bmx")
printf '%s\n' "$parallel_specialization_output"
printf '%s\n' "$parallel_specialization_output" | grep -Eq 'bmk: generic specialization compilation: [0-9]+ ms \(([2-9]|[1-9][0-9]+) objects, [1-9][0-9]* parallel batches\)'
test "$(find "$output_root/.bmx/.generics/objects" -name '*.o' -type f | wc -l | tr -d ' ')" -eq "$parallel_specialization_object_count"
"$app_path"

manifest_count=$(find "$output_root/.bmx" -name 'generic_app*.bmxbuild' -type f | wc -l | tr -d ' ')
test "$manifest_count" -eq 1

quoted_root="$output_root/application-quoted"
mkdir -p "$quoted_root"
cp "$fixture_dir"/application_quoted_*.bmx "$quoted_root/"
quoted_app_path="$quoted_root/application-quoted-app"
"$bmk_path" makeapp -bcc2 -single -r -gdb -o "$quoted_app_path" "$quoted_root/application_quoted_app.bmx"
"$quoted_app_path"
quoted_manifest_count=$(find "$quoted_root/.bmx" -name 'application_quoted_*.bmxbuild' -type f | wc -l | tr -d ' ')
test "$quoted_manifest_count" -eq 3
quoted_common_count=$(nm "$quoted_app_path" | grep -Ec ' T _?application_application_quoted_app_ApplicationQuotedBase$')
test "$quoted_common_count" -eq 1
quoted_value_count=$(nm "$quoted_app_path" | grep -Ec ' T _?application_application_quoted_app_ApplicationQuotedValue$')
test "$quoted_value_count" -eq 1

quoted_generic_root="$output_root/application-quoted-generic"
mkdir -p "$quoted_generic_root"
cp "$fixture_dir/application_quoted_generic_app.bmx" "$quoted_generic_root/app.bmx"
cp "$fixture_dir/application_quoted_generic_provider_v1.bmx" "$quoted_generic_root/application_quoted_generic_provider.bmx"
quoted_generic_app="$quoted_generic_root/application-quoted-generic-app"
"$bmk_path" makeapp -bcc2 -single -r -o "$quoted_generic_app" "$quoted_generic_root/app.bmx"
test "$("$quoted_generic_app" | tr -d '\r')" = "seed!"
sleep 1
cp "$fixture_dir/application_quoted_generic_provider_v2.bmx" "$quoted_generic_root/application_quoted_generic_provider.bmx"
quoted_generic_update_output=$("$bmk_path" makeapp -bcc2 -single -r -o "$quoted_generic_app" "$quoted_generic_root/app.bmx")
printf '%s\n' "$quoted_generic_update_output"
printf '%s' "$quoted_generic_update_output" | grep -q 'Processing:app.bmx'
printf '%s' "$quoted_generic_update_output" | grep -q 'Compiling generic specializations:app.bmx'
test "$("$quoted_generic_app" | tr -d '\r')" = "seed!!"

nested_root="$output_root/application-nested"
mkdir -p "$nested_root"
cp "$fixture_dir/application_nested_app.bmx" "$nested_root/"
cp -R "$fixture_dir/nested" "$nested_root/"
nested_app_path="$nested_root/application-nested-app"
"$bmk_path" makeapp -bcc2 -single -r -gdb -o "$nested_app_path" "$nested_root/application_nested_app.bmx"
"$nested_app_path"
nested_manifest_count=$(find "$nested_root" -path '*/.bmx/*.bmxbuild' -type f | wc -l | tr -d ' ')
test "$nested_manifest_count" -eq 3
nested_root_c=$(find "$nested_root/.bmx" -name 'application_nested_app*.c' -type f | head -1)
grep -Eq 'nested/left/.bmx/common\.bmx\.[^" ]+\.h' "$nested_root_c"
grep -Eq 'nested/right/.bmx/common\.bmx\.[^" ]+\.h' "$nested_root_c"
left_value_count=$(nm "$nested_app_path" | grep -Ec ' T _?application_application_nested_app_LeftNestedValue$')
right_value_count=$(nm "$nested_app_path" | grep -Ec ' T _?application_application_nested_app_RightNestedValue$')
test "$left_value_count" -eq 1
test "$right_value_count" -eq 1

incbin_root="$output_root/application-incbin"
mkdir -p "$incbin_root"
cp "$fixture_dir/application_incbin_app.bmx" "$fixture_dir/application_incbin.dat" "$incbin_root/"
incbin_app_path="$incbin_root/application-incbin-app"
"$bmk_path" makeapp -bcc2 -single -r -o "$incbin_app_path" "$incbin_root/application_incbin_app.bmx"
test "$("$incbin_app_path" | tr -d '\r')" = "bcc root incbin application ok"
incbin_noop_output=$("$bmk_path" makeapp -bcc2 -single -r -o "$incbin_app_path" "$incbin_root/application_incbin_app.bmx")
if printf '%s' "$incbin_noop_output" | grep -Eq 'Processing:|Compiling:|Linking:'
then
	echo "unchanged root Incbin application was not a no-op" >&2
	exit 1
fi
sleep 1
touch "$incbin_root/application_incbin.dat"
incbin_touch_output=$("$bmk_path" makeapp -bcc2 -single -r -o "$incbin_app_path" "$incbin_root/application_incbin_app.bmx")
if printf '%s' "$incbin_touch_output" | grep -Eq 'Processing:|Compiling:|Linking:'
then
	echo "content-identical root Incbin touch was not a no-op" >&2
	exit 1
fi
sleep 1
printf 'changed\n' >> "$incbin_root/application_incbin.dat"
incbin_change_output=$("$bmk_path" makeapp -bcc2 -single -r -o "$incbin_app_path" "$incbin_root/application_incbin_app.bmx")
printf '%s' "$incbin_change_output" | grep -q 'Compiling:application_incbin_app.bmx.release.'
printf '%s' "$incbin_change_output" | grep -q 'incbin2.c'
printf '%s' "$incbin_change_output" | grep -q 'Linking:application-incbin-app'
if printf '%s' "$incbin_change_output" | grep -q 'Processing:application_incbin_app.bmx'
then
	echo "root Incbin content change unnecessarily regenerated semantic C" >&2
	exit 1
fi

object_count=$(find "$output_root/.bmx/.generics/objects" -name '*.o' -type f | wc -l | tr -d ' ')
test "$object_count" -eq 92

implementation_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_First$')
test "$implementation_count" -eq 1
holder_implementation_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Get$')
test "$holder_implementation_count" -eq 1
factory_create_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Create$')
test "$factory_create_count" -eq 4
ordinary_constructor_object_new_count=$(nm "$app_path" | grep -Ec ' T _+brl_stringbuilder_TStringBuilder_New__Bstring_ObjectNew$')
test "$ordinary_constructor_object_new_count" -eq 1
factory_read_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Read$')
test "$factory_read_count" -eq 5
base_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_GetBase$')
test "$base_method_count" -eq 2
derived_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_GetDerived$')
test "$derived_method_count" -eq 1
self_virtual_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_VirtualValue$')
test "$self_virtual_method_count" -eq 2
self_invoke_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_InvokeVirtual$')
test "$self_invoke_method_count" -eq 1
interface_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Read$')
test "$interface_method_count" -eq 5
left_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Left$')
test "$left_method_count" -eq 1
right_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Right$')
test "$right_method_count" -eq 1
diamond_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Diamond$')
test "$diamond_method_count" -eq 1
extra_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Extra$')
test "$extra_method_count" -eq 2
struct_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_StructValue$')
test "$struct_method_count" -eq 1
nested_struct_new_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildOuter.*_New$')
test "$nested_struct_new_count" -eq 1
constructor_struct_new_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A(0|1_.*|2)$')
test "$constructor_struct_new_count" -eq 4
constructor_struct_new_zero_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A0$')
test "$constructor_struct_new_zero_count" -eq 1
constructor_struct_new_string_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A1_string_[0-9a-f]{12}$')
test "$constructor_struct_new_string_count" -eq 1
constructor_struct_new_int_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A1_int_[0-9a-f]{12}$')
test "$constructor_struct_new_int_count" -eq 1
constructor_struct_new_delegating_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A2$')
test "$constructor_struct_new_delegating_count" -eq 1
constructor_struct_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_ConstructedValue$')
test "$constructor_struct_method_count" -eq 1
constructor_type_new_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A1_string_[0-9a-f]{12}$')
test "$constructor_type_new_count" -eq 1
constructor_type_zero_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A0_void_[0-9a-f]{12}$')
test "$constructor_type_zero_count" -eq 1
constructor_type_int_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A1_int_[0-9a-f]{12}$')
test "$constructor_type_int_count" -eq 1
constructor_type_delegating_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A2_string_int_[0-9a-f]{12}$')
test "$constructor_type_delegating_count" -eq 1
generic_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildIdentity_.*$')
test "$generic_routine_count" -eq 1
generic_overload_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildOverload_.*$')
test "$generic_overload_count" -eq 2
generic_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildMethodBox_Select_.*$')
test "$generic_method_count" -eq 1
direct_base_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildDirectBase_Pick_.*$')
test "$direct_base_method_count" -eq 1
direct_derived_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildDirectDerived_Pick_.*$')
test "$direct_derived_method_count" -eq 1
direct_forward_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildDirectDerived_Forward_.*$')
test "$direct_forward_method_count" -eq 1
direct_struct_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*SBuildDirect_Read_.*$')
test "$direct_struct_method_count" -eq 1
constrained_type_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildReferenceBox.*_Read$')
test "$constrained_type_method_count" -eq 1
constrained_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildKeepReference_.*$')
test "$constrained_routine_count" -eq 1
transitive_generic_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildForward_.*$')
test "$transitive_generic_routine_count" -eq 1
scalar_expression_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildTransform_.*$')
test "$scalar_expression_routine_count" -eq 1
ordinary_dependency_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildViaPlain_.*$')
test "$ordinary_dependency_routine_count" -eq 1
sequential_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildAccumulate_.*$')
test "$sequential_body_routine_count" -eq 1
compound_assignment_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildCompound_.*$')
test "$compound_assignment_routine_count" -eq 2
managed_array_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildArrayRoundTrip_.*$')
test "$managed_array_routine_count" -eq 2
managed_array_slice_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildArraySlice_.*$')
test "$managed_array_slice_routine_count" -eq 2
expression_statement_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildStatement_.*$')
test "$expression_statement_routine_count" -eq 2
expression_statement_callee_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildObserve_.*$')
test "$expression_statement_callee_count" -eq 2
throw_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildThrow_.*$')
test "$throw_routine_count" -eq 2
initialized_type_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildInitialized.*_Index$')
test "$initialized_type_method_count" -eq 1
index_getter_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildIndexBox.*_+_$')
test "$index_getter_count" -eq 2
index_read_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildIndexRead_.*$')
test "$index_read_routine_count" -eq 1
index_write_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildIndexWrite_.*$')
test "$index_write_routine_count" -eq 1
branch_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildChoose_.*$')
test "$branch_body_routine_count" -eq 1
while_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildLoop_.*$')
test "$while_body_routine_count" -eq 1
repeat_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildRepeat_.*$')
test "$repeat_body_routine_count" -eq 1
for_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildFor_.*$')
test "$for_body_routine_count" -eq 1
loop_control_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildControl_.*$')
test "$loop_control_routine_count" -eq 1
for_existing_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildForExisting_.*$')
test "$for_existing_routine_count" -eq 1
eachin_string_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInString_.*$')
test "$eachin_string_routine_count" -eq 1
eachin_array_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInArray_.*$')
test "$eachin_array_routine_count" -eq 1
eachin_static_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInStatic_.*$')
test "$eachin_static_routine_count" -eq 1
eachin_iterator_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInIterator_.*$')
test "$eachin_iterator_routine_count" -eq 1
eachin_iterable_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInIterable_.*$')
test "$eachin_iterable_routine_count" -eq 1
eachin_legacy_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInLegacy_.*$')
test "$eachin_legacy_routine_count" -eq 1
eachin_inherited_legacy_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInInheritedLegacy_.*$')
test "$eachin_inherited_legacy_routine_count" -eq 1
eachin_legacy_type_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInLegacyType_.*$')
test "$eachin_legacy_type_routine_count" -eq 1
eachin_legacy_interface_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInLegacyInterface_.*$')
test "$eachin_legacy_interface_routine_count" -eq 1
eachin_legacy_ordinary_type_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInLegacyOrdinaryType_.*$')
test "$eachin_legacy_ordinary_type_routine_count" -eq 1
eachin_legacy_ordinary_interface_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInLegacyOrdinaryInterface_.*$')
test "$eachin_legacy_ordinary_interface_routine_count" -eq 1
eachin_legacy_ordinary_receivers_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInLegacyOrdinaryReceivers_.*$')
test "$eachin_legacy_ordinary_receivers_routine_count" -eq 1
interface_call_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildInterfaceCall_.*$')
test "$interface_call_routine_count" -eq 1
inherited_interface_call_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildInheritedInterfaceCall_.*$')
test "$inherited_interface_call_routine_count" -eq 1
returned_interface_call_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildReturnedInterfaceCall_.*$')
test "$returned_interface_call_routine_count" -eq 1

second_output=$("$bmk_path" makeapp -bcc2 -single -r -gdb -o "$app_path" "$output_root/generic_app.bmx")
if printf '%s' "$second_output" | grep -q 'Processing:generic_app'
then
	echo "unchanged bcc2 application regenerated compiler output" >&2
	exit 1
fi
# A clean legacy-to-canonical dependency migration, or this test's deliberate
# switch between equivalent SDK path aliases, may compile native application or
# specialization objects and relink once while cache ownership converges. The
# compiler output must remain unchanged, and the following identical invocation
# must then be completely stable.
third_output=$("$bmk_path" makeapp -bcc2 -single -r -gdb -o "$app_path" "$output_root/generic_app.bmx")
if printf '%s' "$third_output" | grep -Eq 'Processing:generic_app|Compiling generic specialization|Compiling:generic_app|Linking:generic-app'
then
	echo "stabilized bcc2 application was rebuilt" >&2
	exit 1
fi

sleep 1
printf '\n' >> "$output_root/generic_file3.bmx"
include_output=$("$bmk_path" makeapp -bcc2 -single -r -gdb -o "$app_path" "$output_root/generic_app.bmx")
printf '%s' "$include_output" | grep -q 'Processing:generic_app'
printf '%s' "$include_output" | grep -q 'Linking:generic-app'
"$app_path"

object_path=$(find "$output_root/.bmx/.generics/objects" -name '*.o' -type f | head -n 1)
mv "$object_path" "$object_path.missing"
"$bmk_path" makeapp -bcc2 -single -r -gdb -o "$app_path" "$output_root/generic_app.bmx"
test -f "$object_path"
"$app_path"

implementation_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_First$')
test "$implementation_count" -eq 1
holder_implementation_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Get$')
test "$holder_implementation_count" -eq 1
factory_create_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Create$')
test "$factory_create_count" -eq 4
ordinary_constructor_object_new_count=$(nm "$app_path" | grep -Ec ' T _+brl_stringbuilder_TStringBuilder_New__Bstring_ObjectNew$')
test "$ordinary_constructor_object_new_count" -eq 1
factory_read_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Read$')
test "$factory_read_count" -eq 5
base_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_GetBase$')
test "$base_method_count" -eq 2
derived_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_GetDerived$')
test "$derived_method_count" -eq 1
self_virtual_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_VirtualValue$')
test "$self_virtual_method_count" -eq 2
self_invoke_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_InvokeVirtual$')
test "$self_invoke_method_count" -eq 1
interface_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Read$')
test "$interface_method_count" -eq 5
left_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Left$')
test "$left_method_count" -eq 1
right_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Right$')
test "$right_method_count" -eq 1
diamond_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Diamond$')
test "$diamond_method_count" -eq 1
extra_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_Extra$')
test "$extra_method_count" -eq 2
struct_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_StructValue$')
test "$struct_method_count" -eq 1
nested_struct_new_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildOuter.*_New$')
test "$nested_struct_new_count" -eq 1
constructor_struct_new_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A(0|1_.*|2)$')
test "$constructor_struct_new_count" -eq 4
constructor_struct_new_zero_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A0$')
test "$constructor_struct_new_zero_count" -eq 1
constructor_struct_new_string_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A1_string_[0-9a-f]{12}$')
test "$constructor_struct_new_string_count" -eq 1
constructor_struct_new_int_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A1_int_[0-9a-f]{12}$')
test "$constructor_struct_new_int_count" -eq 1
constructor_struct_new_delegating_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructed_string_.*_New__A2$')
test "$constructor_struct_new_delegating_count" -eq 1
constructor_struct_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_ConstructedValue$')
test "$constructor_struct_method_count" -eq 1
constructor_type_new_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A1_string_[0-9a-f]{12}$')
test "$constructor_type_new_count" -eq 1
constructor_type_zero_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A0_void_[0-9a-f]{12}$')
test "$constructor_type_zero_count" -eq 1
constructor_type_int_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A1_int_[0-9a-f]{12}$')
test "$constructor_type_int_count" -eq 1
constructor_type_delegating_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildConstructedType.*_New__A2_string_int_[0-9a-f]{12}$')
test "$constructor_type_delegating_count" -eq 1
generic_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildIdentity_.*$')
test "$generic_routine_count" -eq 1
generic_overload_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildOverload_.*$')
test "$generic_overload_count" -eq 2
generic_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildMethodBox_Select_.*$')
test "$generic_method_count" -eq 1
constrained_type_method_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*TBuildReferenceBox.*_Read$')
test "$constrained_type_method_count" -eq 1
constrained_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildKeepReference_.*$')
test "$constrained_routine_count" -eq 1
transitive_generic_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildForward_.*$')
test "$transitive_generic_routine_count" -eq 1
scalar_expression_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildTransform_.*$')
test "$scalar_expression_routine_count" -eq 1
ordinary_dependency_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildViaPlain_.*$')
test "$ordinary_dependency_routine_count" -eq 1
sequential_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildAccumulate_.*$')
test "$sequential_body_routine_count" -eq 1
compound_assignment_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildCompound_.*$')
test "$compound_assignment_routine_count" -eq 2
managed_array_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildArrayRoundTrip_.*$')
test "$managed_array_routine_count" -eq 2
branch_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildChoose_.*$')
test "$branch_body_routine_count" -eq 1
while_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildLoop_.*$')
test "$while_body_routine_count" -eq 1
repeat_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildRepeat_.*$')
test "$repeat_body_routine_count" -eq 1
for_body_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildFor_.*$')
test "$for_body_routine_count" -eq 1
loop_control_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildControl_.*$')
test "$loop_control_routine_count" -eq 1
for_existing_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildForExisting_.*$')
test "$for_existing_routine_count" -eq 1
eachin_string_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInString_.*$')
test "$eachin_string_routine_count" -eq 1
eachin_array_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInArray_.*$')
test "$eachin_array_routine_count" -eq 1
eachin_static_routine_count=$(nm "$app_path" | grep -Ec ' T _?bmx_gen_.*_BuildEachInStatic_.*$')
test "$eachin_static_routine_count" -eq 1

sdk_root=$(CDPATH= cd -- "$(dirname -- "$bmk_path")/.." && pwd)
module_test_root="$sdk_root/mod/bcc2manifesttest.mod"
if test -e "$module_test_root"
then
	echo "temporary bcc2 manifest-test module already exists: $module_test_root" >&2
	exit 1
fi
cleanup_module_test()
{
	rm -rf "$module_test_root"
}
trap cleanup_module_test 0 HUP INT TERM
mkdir -p "$module_test_root/owner.mod"
cp "$fixture_dir/module_specialization_owner.bmx" "$module_test_root/owner.mod/owner.bmx"
mkdir -p "$module_test_root/multisource.mod"
cp "$fixture_dir/module_multisource.bmx" "$module_test_root/multisource.mod/multisource.bmx"
cp "$fixture_dir/module_multisource_common.bmx" "$module_test_root/multisource.mod/module_multisource_common.bmx"
mkdir -p "$module_test_root/transitiveleaf.mod"
cp "$fixture_dir/module_transitive_leaf.bmx" "$module_test_root/transitiveleaf.mod/transitiveleaf.bmx"
mkdir -p "$module_test_root/transitiveconsumer.mod"
cp "$fixture_dir/module_transitive_consumer.bmx" "$module_test_root/transitiveconsumer.mod/transitiveconsumer.bmx"
mkdir -p "$module_test_root/applicationdependency.mod"
cp "$fixture_dir/module_application_dependency.bmx" "$module_test_root/applicationdependency.mod/applicationdependency.bmx"
mkdir -p "$module_test_root/closureowner.mod"
cp "$fixture_dir/module_closure_owner.bmx" "$module_test_root/closureowner.mod/closureowner.bmx"

application_dependency_source="$output_root/module_application_dependency_app.bmx"
application_dependency_path="$output_root/module-application-dependency-app"
cp "$fixture_dir/module_application_dependency_app.bmx" "$application_dependency_source"
"$bmk_path" makeapp -bcc2 -single -r -o "$application_dependency_path" "$application_dependency_source"
application_dependency_manifest=$(find "$module_test_root/applicationdependency.mod" -maxdepth 1 -name 'applicationdependency.release.*.bmxbuild' -type f)
test -f "$application_dependency_manifest"
"$application_dependency_path"

transitive_module_output=$("$bmk_path" makemods -v -bcc2 -a -r BCC2ManifestTest.TransitiveConsumer)
printf '%s\n' "$transitive_module_output"
archive_announcement_count=$(printf '%s\n' "$transitive_module_output" | grep -c 'Archiving:')
test "$archive_announcement_count" -ge 2
last_archive_announcement=$(printf '%s\n' "$transitive_module_output" | awk '/Archiving:/{line=NR} END{print line+0}')
first_archive_completion=$(printf '%s\n' "$transitive_module_output" | awk '/bmk: archive timing/{print NR; exit}')
test "$first_archive_completion" -gt "$last_archive_announcement"
transitive_leaf_manifest=$(find "$module_test_root/transitiveleaf.mod" -maxdepth 1 -name 'transitiveleaf.release.*.bmxbuild' -type f)
transitive_consumer_manifest=$(find "$module_test_root/transitiveconsumer.mod" -maxdepth 1 -name 'transitiveconsumer.release.*.bmxbuild' -type f)
test -f "$transitive_leaf_manifest"
test -f "$transitive_consumer_manifest"

owner_module_build_output=$("$bmk_path" makemods -v -bcc2 -a -r -gdb bcc2manifesttest.owner)
printf '%s\n' "$owner_module_build_output"
owner_module_archive_identity=$(printf '%s\n' "$owner_module_build_output" | sed -n 's/.*bmk: archive timing owner\.release\..* input=\([0-9a-f][0-9a-f]*\).*/\1/p')
test "${#owner_module_archive_identity}" -eq 64
if test "$bcc_name" = bcc.exe
then
	printf '%s\n' "$owner_module_build_output" | grep -Eq 'ar(\.exe)?"? -rc .* @.*\.objects\.rsp'
	printf '%s\n' "$owner_module_build_output" | grep -Eq 'bmk: archive timing owner\.release\..* commands=1 '
fi
module_manifest_count=$(find "$module_test_root/owner.mod" -maxdepth 1 -name 'owner.release.*.bmxbuild' -type f | wc -l | tr -d ' ')
test "$module_manifest_count" -eq 1
module_object_count=$(find "$module_test_root/owner.mod/.generics/objects" -name '*.o' -type f | wc -l | tr -d ' ')
test "$module_object_count" -eq 1

"$bmk_path" makemods -bcc2 -a -r bcc2manifesttest.closureowner
closure_owner_interface=$(find "$module_test_root/closureowner.mod" -maxdepth 1 -name 'closureowner.release.*.i' -type f)
test -f "$closure_owner_interface"
grep -q 'Remember<T>:Closure<T()>(value:T)' "$closure_owner_interface"
grep -q 'Apply<T,R>:R(value:T,operation:Closure<R(value:T)>)' "$closure_owner_interface"
grep -q 'MakeAdder:Closure<Int(value:Int)>(amount%)' "$closure_owner_interface"
grep -q 'Invoke%(value%,operation:Closure<Int(value:Int)>)' "$closure_owner_interface"
grep -q 'OwnedReader:Closure<String()>&=mem:p(' "$closure_owner_interface"
closure_template_count=$(find "$module_test_root/closureowner.mod/.generics/templates" -name '*.bmxgt' -type f | wc -l | tr -d ' ')
test "$closure_template_count" -eq 2
closure_module_object_count=$(find "$module_test_root/closureowner.mod/.generics/objects" -name '*.o' -type f | wc -l | tr -d ' ')
test "$closure_module_object_count" -eq 1

closure_app_source="$output_root/module_closure_app.bmx"
closure_app_path="$output_root/module-closure-app"
cp "$fixture_dir/module_closure_app.bmx" "$closure_app_source"
closure_app_first_output=$("$bmk_path" makeapp -bcc2 -single -r -o "$closure_app_path" "$closure_app_source")
printf '%s\n' "$closure_app_first_output"
closure_app_compile_count=$(printf '%s' "$closure_app_first_output" | grep -c 'Compiling generic specialization')
test "$closure_app_compile_count" -eq 1
test "$("$closure_app_path" | tr -d '\r\n')" = "module-closure-owner-ok"

closure_app_second_output=$("$bmk_path" makeapp -bcc2 -single -r -o "$closure_app_path" "$closure_app_source")
if printf '%s' "$closure_app_second_output" | grep -Eq 'Processing:module_closure_app|Compiling generic specialization|Compiling:module_closure_app|Linking:module-closure-app'
then
	echo "unchanged Closure module consumer was rebuilt" >&2
	exit 1
fi

closure_module_object=$(find "$module_test_root/closureowner.mod/.generics/objects" -name '*.o' -type f)
test -n "$closure_module_object"
rm "$closure_module_object" "$closure_module_object.bcc2key"
closure_app_repair_output=$("$bmk_path" makeapp -bcc2 -single -r -o "$closure_app_path" "$closure_app_source")
printf '%s\n' "$closure_app_repair_output"
closure_app_repair_count=$(printf '%s' "$closure_app_repair_output" | grep -c 'Compiling generic specialization')
test "$closure_app_repair_count" -eq 1
test "$("$closure_app_path" | tr -d '\r\n')" = "module-closure-owner-ok"

"$bmk_path" makemods -bcc2 -a -r bcc2manifesttest.multisource
multisource_manifest_count=$(find "$module_test_root/multisource.mod" -name '*.bmxbuild' -type f | wc -l | tr -d ' ')
test "$multisource_manifest_count" -eq 2
multisource_common_interface=$(find "$module_test_root/multisource.mod/.bmx" -name 'module_multisource_common.bmx.release.*.i' -type f)
test -f "$multisource_common_interface"
grep -q 'MultiSourceCommonValue%()="bcc2manifesttest_multisource_MultiSourceCommonValue"' "$multisource_common_interface"
multisource_archive=$(find "$module_test_root/multisource.mod" -maxdepth 1 -name 'multisource.release.*.a' -type f)
nm "$multisource_archive" | grep -Eq ' T _?__bb_bcc2manifesttest_multisource_module_multisource_common$'

# A content-stable edit to a quoted module unit must refresh its owner once,
# then settle. Module manifests live beside their interfaces rather than the
# generated root C file; consulting the latter path rebuilt the owner forever.
sleep 1
touch "$module_test_root/multisource.mod/module_multisource_common.bmx"
multisource_refresh_output=$("$bmk_path" makemods -bcc2 -r bcc2manifesttest.multisource)
printf '%s\n' "$multisource_refresh_output"
printf '%s' "$multisource_refresh_output" | grep -q 'Processing:module_multisource.bmx'
multisource_noop_output=$("$bmk_path" makemods -bcc2 -r bcc2manifesttest.multisource)
if printf '%s' "$multisource_noop_output" | grep -Eq 'Processing:module_multisource|Compiling:module_multisource|Archiving:multisource'
then
	echo "unchanged multisource module owner was rebuilt after its quoted source stamp settled" >&2
	exit 1
fi

multisource_app_source="$output_root/module_multisource_app.bmx"
multisource_app_path="$output_root/module-multisource-app"
cp "$fixture_dir/module_multisource_app.bmx" "$multisource_app_source"
"$bmk_path" makeapp -bcc2 -single -r -o "$multisource_app_path" "$multisource_app_source"
multisource_result=$("$multisource_app_path" | tr -d '\r\n')
test "$multisource_result" = "42"

# -quick remains accepted for MaxIDE and script compatibility, but canonical
# builds must still scan quoted module source units for their dependencies.
sleep 1
touch "$multisource_app_source"
"$bmk_path" makeapp -quick -bcc2 -single -r -o "$multisource_app_path" "$multisource_app_source"
multisource_quick_result=$("$multisource_app_path" | tr -d '\r\n')
test "$multisource_quick_result" = "42"

module_app_source="$output_root/module_specialization_app.bmx"
module_app_path="$output_root/module-specialization-app"
cp "$fixture_dir/module_specialization_app.bmx" "$module_app_source"
module_app_object_count_before=$(find "$output_root/.bmx/.generics/objects" -name '*.o' -type f | wc -l | tr -d ' ')
module_first_output=$("$bmk_path" makeapp -bcc2 -single -r -gdb -o "$module_app_path" "$module_app_source")
printf '%s\n' "$module_first_output"
if printf '%s' "$module_first_output" | grep -q 'Compiling generic specialization'
then
	echo "application recompiled a module-owned specialization" >&2
	exit 1
fi
module_app_object_count_after=$(find "$output_root/.bmx/.generics/objects" -name '*.o' -type f | wc -l | tr -d ' ')
test "$module_app_object_count_after" -eq "$module_app_object_count_before"
"$module_app_path"
module_second_output=$("$bmk_path" makeapp -bcc2 -single -r -gdb -o "$module_app_path" "$module_app_source")
if printf '%s' "$module_second_output" | grep -Eq 'Processing:module_specialization_app|Compiling generic specialization|Compiling:module_specialization_app|Linking:module-specialization-app'
then
	echo "unchanged module-owned specialization application was rebuilt" >&2
	exit 1
fi

module_owned_object=$(find "$module_test_root/owner.mod/.generics/objects" -name '*.o' -type f)
test -n "$module_owned_object"
rm "$module_owned_object" "$module_owned_object.bcc2key"
module_repair_output=$("$bmk_path" makeapp -v -bcc2 -single -r -gdb -o "$module_app_path" "$module_app_source")
printf '%s\n' "$module_repair_output"
module_repair_compile_count=$(printf '%s' "$module_repair_output" | grep -c 'Compiling generic specialization')
test "$module_repair_compile_count" -eq 1
module_app_archive_identity=$(printf '%s\n' "$module_repair_output" | sed -n 's/.*bmk: archive timing owner\.release\..* input=\([0-9a-f][0-9a-f]*\).*/\1/p')
test "$module_app_archive_identity" = "$owner_module_archive_identity"
"$module_app_path"

module_specialization_count=$(nm "$module_app_path" | grep -Ec ' T _?bmx_gen_bcc2manifesttest_owner_TArchiveBox_string_.*_Set$')
test "$module_specialization_count" -eq 1
module_specialization_register_count=$(nm "$module_app_path" | grep -Ec ' T _?bmx_gen_bcc2manifesttest_owner_TArchiveBox_string_.*_register$')
test "$module_specialization_register_count" -eq 1

# cleanmods owns the hidden compiler-output directory but must not infer that a
# visible source directory named generics is disposable.
mkdir -p "$module_test_root/owner.mod/generics"
touch "$module_test_root/owner.mod/generics/keep.bmx"
"$bmk_path" cleanmods bcc2manifesttest.owner
test ! -e "$module_test_root/owner.mod/.generics"
test -f "$module_test_root/owner.mod/generics/keep.bmx"
test "$(find "$module_test_root/owner.mod" -maxdepth 1 -name 'owner.release.*.a' -type f | wc -l | tr -d ' ')" -eq 0
test "$(find "$module_test_root/owner.mod" -maxdepth 1 -name 'owner.release.*.i' -type f | wc -l | tr -d ' ')" -eq 0
test "$(find "$module_test_root/owner.mod" -maxdepth 1 -name 'owner.release.*.i2' -type f | wc -l | tr -d ' ')" -eq 0
module_rebuild_output=$("$bmk_path" makemods -v -bcc2 -r bcc2manifesttest.owner)
printf '%s\n' "$module_rebuild_output"
printf '%s' "$module_rebuild_output" | grep -q 'Processing:owner.bmx'
printf '%s' "$module_rebuild_output" | grep -Eq 'bmk: archive timing owner\.release\..* prepare=[0-9]+ ms wait=[0-9]+ ms command=[0-9]+ ms publish=[0-9]+ ms worker=[0-9]+ ms elapsed=[0-9]+ ms objects=[0-9]+ bytes=[0-9]+ commands=[0-9]+ input=[0-9a-f]{64}'
find "$module_test_root/owner.mod" -maxdepth 1 -name 'owner.release.*.a' -type f | grep -q .
find "$module_test_root/owner.mod" -maxdepth 1 -name 'owner.release.*.i2' -type f | grep -q .

cleanup_module_test
trap - 0 HUP INT TERM

echo "bmk bcc2 integration tests passed"
