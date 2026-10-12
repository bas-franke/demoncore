#!/bin/bash
# Runs every headless check in the project and prints a pass/fail summary table.
# Owner: QA (docs/team/qa.md). Git Bash, from anywhere:
#
#   tools/qa/run_all.sh                      # everything (~6-10 min)
#   tools/qa/run_all.sh --quick              # skip the slow ones (warnings, flow over all maps, sfx run)
#   tools/qa/run_all.sh --only=check_scripts,flow_smoke
#   tools/qa/run_all.sh --list               # list check names
#   FLOW_SECS=60 tools/qa/run_all.sh         # game seconds per map in flow_smoke (default 30)
#
# Status per check:
#   PASS  exit code 0 and no SCRIPT ERROR in the log
#   WARN  exit code 0 but the log has SCRIPT ERROR lines (some other system threw while it ran)
#   FAIL  non-zero exit, crash or timeout (124)
# Logs: tools/qa/results/<timestamp>/<check>.log (git-ignored), plus summary.txt there.
# The script's exit code is the number of FAILed checks.

set -u
PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/c/Users/buunn/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
FLOW_SECS="${FLOW_SECS:-30}"
OUT="$PROJECT/tools/qa/results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

# name | timeout (s) | godot args ("@warnings" runs tools/check_warnings.sh instead)
CHECKS=(
	"import|600|--headless --import"
	"check_scripts|300|--headless --script res://tools/check_scripts.gd"
	"boot|180|--headless --quit-after 300"
	"abilities_check|120|--headless --script res://tools/abilities_check.gd"
	"gameplay_check|300|--headless --script res://tools/gameplay_check.gd"
	"progression_check|180|--headless --script res://tools/progression_check.gd"
	"progression_run_check|300|--headless --script res://tools/progression_run_check.gd"
	"map_check|600|--headless --fixed-fps 60 --disable-vsync res://tools/maps/map_check.tscn"
	"feature_check|300|--headless res://tools/maps/feature_check.tscn"
	"objectives_selftest|600|--headless --fixed-fps 60 --disable-vsync res://scenes/main.tscn -- --godmode --objectives-selftest"
	"music_check|300|--headless --script res://tools/music/music_check.gd"
	"sfx_smoke|300|--headless --script res://tools/sfx_smoke.gd -- --autopilot --secs=20"
	"story_check|180|--headless --script res://tools/story/story_check.gd"
	"basecamp_smoke|300|--headless --script res://tools/basecamp_smoke.gd"
	"roster_check|300|--headless --script res://scenes/characters/_roster_check.gd"
	"characters_check|300|--headless res://tools/characters/characters_check.tscn"
	"terrain_check|300|--headless --script res://tools/terrain/terrain_check.gd"
	"props_check|300|--headless --script res://tools/_props_check.gd"
	"qa_smoke_checks|600|--headless --script res://tools/qa/smoke_checks.gd"
	"flow_smoke|1200|--headless --fixed-fps 60 --disable-vsync --script res://tools/qa/flow_smoke.gd -- --autopilot --secs=$FLOW_SECS --demons"
	"perf_gate|400|--headless --fixed-fps 60 res://scenes/main.tscn -- --autopilot --bench=10 --stress=300 --bench-gate=25"
	"perf_roster|400|--headless res://tools/perf/spawn_cost.tscn -- --gate"
	"warnings|900|@warnings"
)
SLOW="warnings flow_smoke sfx_smoke perf_gate perf_roster objectives_selftest"

ONLY=""
QUICK=0
for a in "$@"; do
	case "$a" in
		--quick) QUICK=1 ;;
		--only=*) ONLY=",${a#--only=}," ;;
		--list) for c in "${CHECKS[@]}"; do echo "${c%%|*}"; done; exit 0 ;;
		*) echo "unknown arg $a"; exit 2 ;;
	esac
done

declare -a ROWS
fails=0
cd "$PROJECT"
for c in "${CHECKS[@]}"; do
	name="${c%%|*}"; rest="${c#*|}"; tmo="${rest%%|*}"; args="${rest#*|}"
	if [ -n "$ONLY" ] && [[ "$ONLY" != *",$name,"* ]]; then continue; fi
	if [ "$QUICK" = 1 ] && [[ " $SLOW " == *" $name "* ]]; then continue; fi
	# --quick: map_check's --fast mode (1 variant, 12 agents) instead of skipping it.
	[ "$QUICK" = 1 ] && [ "$name" = map_check ] && args="$args -- --fast"
	log="$OUT/$name.log"
	printf '[%s] %-22s ' "$(date +%H:%M:%S)" "$name"
	start=$(date +%s)
	if [ "$args" = "@warnings" ]; then
		timeout "$tmo" bash "$PROJECT/tools/check_warnings.sh" > "$log" 2>&1
	else
		# shellcheck disable=SC2086
		timeout "$tmo" "$GODOT" --path "$PROJECT" $args > "$log" 2>&1
	fi
	code=$?
	secs=$(( $(date +%s) - start ))
	serr=$(grep -c "^SCRIPT ERROR" "$log")
	err=$(grep -cE "^(USER )?ERROR" "$log")
	warn=$(grep -cE "^(USER )?WARNING" "$log")
	crash=$(grep -cE "Program crashed|CrashHandlerException|Dumping the backtrace" "$log")
	if [ "$code" != 0 ] || [ "$crash" != 0 ]; then
		status=FAIL; fails=$((fails + 1))
	elif [ "$serr" != 0 ]; then
		status=WARN
	else
		status=PASS
	fi
	note=""
	[ "$code" = 124 ] && note="TIMEOUT"
	[ "$crash" != 0 ] && note="CRASH"
	if [ "$name" = warnings ]; then
		note="$(grep -E "^check_warnings:" "$log" | tail -1)"
		[ "$status" = FAIL ] && [ "$code" = 1 ] && { status=WARN; fails=$((fails - 1)); }  # warnings never fail the suite
	fi
	echo "$status (exit $code, ${secs}s)"
	ROWS+=("$(printf '%-22s %-5s %5s %5s %6s %6s %6s  %s' "$name" "$status" "$code" "$secs" "$serr" "$err" "$warn" "$note")")
done

{
	echo
	echo "QA suite $(basename "$OUT")   logs: $OUT"
	printf '%-22s %-5s %5s %5s %6s %6s %6s  %s\n' check status exit secs scrErr errors warns note
	printf '%s\n' "------------------------------------------------------------------------------"
	for r in "${ROWS[@]}"; do echo "$r"; done
	echo
	echo "Top unique SCRIPT ERRORs (all logs):"
	# "SCRIPT ERROR: <msg>" + next line "   at: <func> (<file:line>)" -> "<msg> @ <file:line>"
	for f in "$OUT"/*.log; do
		grep -A1 "^SCRIPT ERROR" "$f" | grep -v "^--" | paste - - \
			| sed -E 's/^SCRIPT ERROR: //; s/\t *at: [^(]*\((.*)\)$/ @ \1/'
	done | sort | uniq -c | sort -rn | head -25
	echo
	echo "FAILED checks: $fails"
} | tee "$OUT/summary.txt"
exit "$fails"
