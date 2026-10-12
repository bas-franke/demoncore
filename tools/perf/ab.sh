#!/usr/bin/env bash
# A/B the in-game bench: alternates runs of each experiment set, prints the median avg_ms per set.
#   tools/perf/ab.sh <runs> <enemies> <secs> "noweapons" "noweapons,nointerp" ...
# Interleaving keeps machine-load drift (other Godot instances) from favouring one side.
set -u
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$(grep -o '"[^"]*Godot_v[^"]*\.exe"' Play.bat | head -1 | tr -d '"')}"
GODOT="$(cygpath -u "${GODOT/_win64.exe/_win64_console.exe}" 2>/dev/null || echo "${GODOT/_win64.exe/_win64_console.exe}")"
runs="$1"; n="$2"; secs="$3"; shift 3
declare -A res
for ((r = 0; r < runs; r++)); do
	for exp in "$@"; do
		line="$(timeout $((secs + 120)) "$GODOT" --path . res://scenes/main.tscn -- --autopilot --bench="$secs" --stress="$n" --bench-exp="$exp" 2>&1 | grep '^\[PERF\] frames')"
		ms="$(echo "$line" | grep -o 'avg_ms=[0-9.]*' | cut -d= -f2)"
		rc="$(echo "$line" | grep -o 'render_cpu_ms=[0-9.]*' | cut -d= -f2)"
		echo "run $r  $exp  avg_ms=$ms render_cpu_ms=$rc"
		res[$exp]+="$ms "
	done
done
for exp in "$@"; do
	med="$(echo ${res[$exp]} | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"
	echo "MEDIAN  $exp  avg_ms=$med"
done
