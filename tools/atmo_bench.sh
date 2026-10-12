#!/usr/bin/env bash
# Frame-time cost of the Atmosphere presets at every quality tier (docs/team/visuals.md, Performance).
# Runs tools/atmo_test.tscn once per tier (Low..Ultra) with vsync off and appends one line per
# measurement ("bare" = no preset applied, then each preset) to the output file.
#   tools/atmo_bench.sh [out_file] [preset,list]
set -u
GODOT="${GODOT:-/c/Users/buunn/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
OUT="${1:-atmo_bench.txt}"
LIST="${2:-cathedral_city,frozen_monastery,storm_spire,outer_gardens,basecamp_hell}"
cd "$(dirname "$0")/.."
for q in 0 1 2 3; do
	"$GODOT" --path . res://tools/atmo_test.tscn -- --atmo-bench="$OUT" --atmo-tour-quality=$q --atmo-tour-list="$LIST" \
		| grep atmo_bench
done
