#!/bin/bash
# qc-local.sh <test id> list | <step number> <pass|fail> [text...]   [round via QC_LOCAL_ROUND, default local-<id>]
# Local re-run of a test WITHOUT submitting to the platform (for re-checks of a fixed build): reads state/tests/test<id>.json (get it
# with qc-dltest.sh), prints the step list, or records one STEP line in the local round's run.log. It never calls the platform.
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
T=${1:?test id}; K=${2:?list or a step number}; F="$QC_STATE/tests/test$T.json"; [ -r "$F" ] || die "no $F: run qc-dltest.sh $T first"
R=${QC_LOCAL_ROUND:-local-$T}; [ -d "$(round_dir "$R")" ] || "$QC_TOOLS/round-new.sh" "$R" >/dev/null
if [ "$K" = list ]; then python3 -I -c 'import sys,json
for s in sorted(json.load(open(sys.argv[1]))["steps"],key=lambda x:x["step_number"]): print(s["step_number"],"|",s["description"][:160].replace("\n"," "),"| expect:",(s.get("success_symptom") or "")[:100].replace("\n"," "))' "$F"; exit 0; fi
V=${3:?pass|fail}; shift 3; case $V in pass|fail) ;; *) die "pass or fail";; esac
python3 -I -c 'import sys,json
n=int(sys.argv[2]); print(any(s["step_number"]==n for s in json.load(open(sys.argv[1]))["steps"]))' "$F" "$K" | grep -q True || die "test $T has no step $K"
"$QC_TOOLS/log.sh" "$R" STEP "test $T step $K LOCAL $V: $*"
