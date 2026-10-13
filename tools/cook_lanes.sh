#!/bin/sh
# COOK IN ROLL LANES (Nick 10-13: no arm spins). Every key may roll the arm only ROLL_STEP from the key before, so the
# first key's forearm turn decides what the whole move can reach. Cook the move from 5 starting turns, keep the best
# by the lane score (hand + aim misses + bad frames), then judge it with the visible skin (tools/mesh_truth.gd).
#   sh tools/cook_lanes.sh plans/<name>.json
G=${G:-/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe}
plan=$1
best=""; bs=999
for r in -60 -30 0 30 60; do
  s=$(timeout 1200 $G --headless --path . -s tools/cook.gd -- $plan --roll $r 2>&1 | grep "^LANE" | awk '{print $5}')
  echo "  lane $r: score $s"
  if [ -n "$s" ] && awk "BEGIN{exit !($s < $bs)}"; then bs=$s; best=$r; fi
done
echo "  best lane $best (score $bs)"
timeout 1200 $G --headless --path . -s tools/cook.gd -- $plan --roll $best 2>&1 | grep "COOK\|miss\|SPIN" | sed 's/contacts \[.*\]/contacts …/' | cut -c1-150
