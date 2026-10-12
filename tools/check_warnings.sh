#!/bin/bash
# Lists GDScript warnings (unused variables, shadowing, integer division, ...) for every script.
# Owned by code-quality (docs/team/code-quality.md).
#
# Godot only shows these warnings in the editor, so this copies the project (minus .git) to a temp
# folder, promotes every default warning to an error in the copy's project.godot, and runs
# tools/check_scripts.gd there. The real project is never modified.
#
# Usage (Git Bash, from anywhere):   tools/check_warnings.sh [extra_warning ...]
#   e.g. tools/check_warnings.sh untyped_declaration     # also flag untyped variables
# Output: one "message @ res://file.gd:line" per warning, sorted. Exit code 1 if any were found.

set -u
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/c/Users/buunn/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
WORK="${TMPDIR:-${TEMP:-/tmp}}/demoncore_warncheck"

# Warnings that Godot reports at level 1 (warn) by default.
WARNINGS="unassigned_variable unassigned_variable_op_assign unused_variable unused_local_constant
unused_private_class_variable unused_parameter unused_signal shadowed_variable
shadowed_variable_base_class shadowed_global_identifier unreachable_code unreachable_pattern
standalone_expression standalone_ternary incompatible_ternary unsafe_void_return
static_called_on_instance redundant_static_unload redundant_await assert_always_true
assert_always_false integer_division narrowing_conversion int_as_enum_without_cast
int_as_enum_without_match enum_variable_without_default empty_file deprecated_keyword
confusable_identifier confusable_local_declaration confusable_local_usage
confusable_capture_reassignment confusable_temporary_modification property_used_as_function
constant_used_as_function function_used_as_property"

rm -rf "$WORK" && mkdir -p "$WORK"
(cd "$PROJECT" && tar --exclude=./.git -cf - .) | (cd "$WORK" && tar xf -)
{
	echo; echo "[debug]"; echo
	for w in $WARNINGS "$@"; do echo "gdscript/warnings/$w=2"; done
} >> "$WORK/project.godot"

"$GODOT" --headless --path "$WORK" --script res://tools/check_scripts.gd > "$WORK/check.log" 2>&1
# Each error is "SCRIPT ERROR: Parse Error: <msg>" followed by "   at: GDScript::reload (<file:line>)".
grep -E "^SCRIPT ERROR" -A1 "$WORK/check.log" | grep -v "^--" | paste - - \
	| sed 's/SCRIPT ERROR: Parse Error: //; s/SCRIPT ERROR: //; s/ *(Warning treated as error.)//; s/\t *at: GDScript::reload (/ @ /; s/)$//' \
	| sort -u > "$WORK/warnings.txt"
cat "$WORK/warnings.txt"
count=$(wc -l < "$WORK/warnings.txt")
echo "check_warnings: $count warning(s)/error(s)"
[ "$count" -eq 0 ]
