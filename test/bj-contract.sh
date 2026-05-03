#!/usr/bin/env sh
set -eu

BJ="${BJ:-bj}"

state="$("$BJ" --no-color new --seed 7)"

printf '%s' "$state" | python3 -c '
import json
import sys

state = json.load(sys.stdin)
assert "phase" in state, "missing phase"
assert "dealer_hand" in state, "missing dealer_hand"
assert "player_hands" in state, "missing player_hands"
'

action="$(printf '%s' "$state" | python3 -c '
import json
import sys

state = json.load(sys.stdin)
phase = state.get("phase", {})
phase_type = phase.get("type")
if phase_type == "Insurance":
    print("insurance")
elif phase_type == "Finished":
    print("new")
else:
    print("stand")
')"

if [ "$action" = "new" ]; then
  next_state="$("$BJ" --no-color new --seed 8)"
else
  next_state="$(printf '%s' "$state" | "$BJ" --no-color "$action")"
fi

printf '%s' "$next_state" | python3 -c '
import json
import sys

state = json.load(sys.stdin)
assert "phase" in state, "missing phase after action"
'

printf 'ok\n'
