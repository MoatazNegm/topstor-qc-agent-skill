#!/bin/bash
# qc-dltest.sh <test id>   download the FULL test sheet (GET /tests/<id>) to state/tests/test<id>.json + .txt (id, number,
# on_failure, description, expected symptom per step) and print the .txt. Read ALL steps before building anything; it is also the
# working file of a local re-run after a code fix.
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
T=${1:?test id}; J=$QC_STATE/tests/test$T.json
qc_get "tests/$T" > "$J.new" && python3 -I -c 'import json,sys;json.load(open(sys.argv[1]))' "$J.new" 2>/dev/null || { rm -f "$J.new"; die "test $T could not be downloaded"; }
mv "$J.new" "$J"
python3 -I - "$J" "$QC_STATE/tests/test$T.txt" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d=d.get("activeTest") or d.get("test") or d
if not isinstance(d,dict) or not d.get("steps"):
    sys.stderr.write("ERROR: reply is not a test sheet with steps: %s\n"%str(d)[:200]); sys.exit(1)
with open(sys.argv[2],"w") as f:
    f.write("test %s %s (%d steps)\n"%(d.get("id"),d.get("name"),len(d.get("steps",[]))))
    for s in sorted(d.get("steps",[]),key=lambda x:x.get("step_number",0)):
        f.write("%s\t%s\t%s\t%s\t| expect: %s\n"%(s["id"],s["step_number"],s.get("on_failure"),
                " ".join(str(s.get("description","")).split())," ".join(str(s.get("success_symptom","")).split())))
print(open(sys.argv[2]).read())
PY
rc=$?; [ $rc = 0 ] || { rm -f "$J" "$QC_STATE/tests/test$T.txt"; die "test $T: the platform reply has no steps (see above); nothing kept"; }
