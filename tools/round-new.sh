#!/bin/bash
# round-new.sh <test id> <iteration>   create a NEW, non-colliding round dir state/rounds/b<test>i<iteration>[a-z], download the full
# test sheet, write the first run.log line (test id, name, iteration), the start time (UTC, used by the history checks) and a
# RESUME.md skeleton. Prints the round name.
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
T=${1:?test id}; I=${2:?iteration}; base=b${T}i${I}; R=$base
for s in "" a b c d e f g h j k m n p q r s t u v w x y z; do R=$base$s; [ -e "$(round_dir "$R")" ] || break; done
D=$(round_dir "$R"); [ -e "$D" ] && die "no free round name for $base"
mkdir -p "$D"; "$QC_TOOLS/qc-dltest.sh" "$T" > "$D/steps.txt" || die "test sheet download failed"
date -u +%Y-%m-%dT%H:%M:%S > "$D/startts"
NAME=$(head -1 "$QC_STATE/tests/test$T.txt" | cut -d' ' -f3-)
echo "$(date +%T) ROUND $R: test $T $NAME, iteration $I; all steps downloaded ($D/steps.txt)" > "$D/run.log"
cat > "$D/RESUME.md" <<EOF
# Round $R -- test $T $NAME, iteration $I
- started: $(date '+%F %T')
- build: (fill in: tag and status file)
- last submitted step: (none)
- held step (not submitted, waiting for a decision): (none)
- exact next action: read all steps in steps.txt, stop all nodes with cluster-stopnode.sh, build
- restart command: (fill in the exact command to continue)
EOF
echo "$R"
