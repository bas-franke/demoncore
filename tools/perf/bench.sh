#!/usr/bin/env bash
# Performance benchmarks (perf role, docs/team/performance.md). Run from Git Bash in the project root:
#   tools/perf/bench.sh            # 300-enemy in-game bench (windowed) + roster spawn-cost table
#   tools/perf/bench.sh game 20 300 noweapons    # just the in-game bench: seconds, enemies, experiments
#   tools/perf/bench.sh roster [ids]             # just the roster table (headless), e.g. "seraph,archon"
#   tools/perf/bench.sh profile 8 300            # in-game bench under the GDScript profiler, top functions
# Results are appended to tools/perf/results.log (date + git-less tree, so compare by date).
# Numbers are wall-clock: close other Godot instances first or they will be noisy.
set -u
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$(grep -o '"[^"]*Godot_v[^"]*\.exe"' Play.bat | head -1 | tr -d '"')}"
GODOT="${GODOT/_win64.exe/_win64_console.exe}"
GODOT="$(cygpath -u "$GODOT" 2>/dev/null || echo "$GODOT")"
LOG=tools/perf/results.log
mode="${1:-all}"

game() {
	local secs="${1:-20}" n="${2:-300}" exp="${3:-}"
	local args=(--path . res://scenes/main.tscn -- --autopilot --bench="$secs" --stress="$n" --bench-out="$LOG")
	[ -n "$exp" ] && args+=(--bench-exp="$exp")
	echo "# $(date '+%F %T') game bench ${secs}s ${n} enemies ${exp}" >> "$LOG"
	"$GODOT" "${args[@]}" 2>&1 | grep '^\[PERF\]'
}

roster() {
	local only=()
	[ -n "${1:-}" ] && only=(-- --only="$1")
	echo "# $(date '+%F %T') roster" >> "$LOG"
	"$GODOT" --headless --path . res://tools/perf/spawn_cost.tscn "${only[@]}" 2>&1 | grep '^\[PERF\]' | tee -a "$LOG"
}

profile() {
	local secs="${1:-8}" n="${2:-300}" out
	out="$(mktemp)"
	"$GODOT" --path . -d --profiling res://scenes/main.tscn -- --autopilot --bench="$secs" --stress="$n" < /dev/null > "$out" 2>&1
	python tools/perf/profile_top.py "$out" 30
	rm -f "$out"
}

case "$mode" in
	game) shift; game "$@" ;;
	roster) shift; roster "$@" ;;
	profile) shift; profile "$@" ;;
	*) game 20 300; roster ;;
esac
