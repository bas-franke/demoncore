#!/usr/bin/env bash
# Balance bench for the abilities role (docs/team/abilities.md). For each school in
# data/abilities/abilities.json, runs a headless standing-still run with only that school's
# abilities (no level-ups, huge HP, so Wrath and blood costs still work) and prints the total
# effective ability damage (no overkill) and kills after SECS seconds. The full per-ability line
# of each school is kept in /tmp/ability_bench_<school>.txt.
#   tools/ability_bench.sh <godot.exe> [secs=90] [rank=3]
GODOT="$1"; SECS="${2:-90}"; RANK="${3:-3}"
cd "$(dirname "$0")/.."
python - <<'PY' > /tmp/ability_schools.txt
import json
a = json.load(open('data/abilities/abilities.json', encoding='utf-8'))
schools = {}
for x in a['abilities']:
    schools.setdefault(x['school'], []).append(x['id'])
for k, v in schools.items():
    print(k.replace(' ', '_') + ' ' + ','.join(v))
PY
FRAMES=$(( SECS * 60 + 30 ))
while read -r school ids; do
  out=$(timeout 900 "$GODOT" --headless --path . res://scenes/main.tscn --fixed-fps 60 --quit-after $FRAMES \
    -- --ability-bench --abilities="$ids" --ability-rank="$RANK" 2>/dev/null | grep '^\[abilities\]' | tail -1)
  echo "$out" > "/tmp/ability_bench_${school}.txt"
  dmg=$(echo "$out" | sed -n 's/.*dmg=\([0-9]*\).*/\1/p')
  kills=$(echo "$out" | sed -n 's/.*kills=\([0-9]*\).*/\1/p')
  n=$(echo "$ids" | tr ',' '\n' | wc -l)
  printf "%-20s abilities=%d dmg=%7s kills=%5s per_ability=%6s\n" "$school" "$n" "$dmg" "$kills" "$(( ${dmg:-0} / n ))"
done < /tmp/ability_schools.txt
