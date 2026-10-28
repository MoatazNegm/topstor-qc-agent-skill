#!/bin/bash
# log.sh <round> <NOW|NOTE|STEP|HOLD|DONE> <text...>   append one masked, time-stamped line to the round's run.log (and print it).
# NOW  = live line at least every loop.now_line_minutes: step number and NAME in words, what runs ("settle 120 of 300 s"), next action
# STEP = a step result line; HOLD = a step held for a decision (not submitted); DONE = the final line (PASS ids, FAIL ids + reasons)
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
R=${1:?round}; K=${2:?kind}; shift 2; D=$(round_dir "$R"); [ -d "$D" ] || die "no round $R"
case $K in NOW|NOTE|STEP|HOLD|DONE) ;; *) die "kind must be NOW, NOTE, STEP, HOLD or DONE";; esac
echo "$(date +%T) $K $*" | mask | tee -a "$D/run.log"
