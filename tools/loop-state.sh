#!/bin/bash
# loop-state.sh <command>   state of the whole loop in state/loop.json (iterations, tests passed in a row with no code change).
#   show                           one line for the report
#   set-tests <id...> | --from-platform   the tests of one full iteration (config loop.iteration_tests, else GET /tests)
#   test-done <test id> <pass|fail>       a platform test finished (pass = every step passed)
#   code-change <branch> <reason...>      a code fix was pushed: the clean count restarts at 0
#   is-clean                       rc 0 when every test of the iteration passed since the last code change (= PR allowed)
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
F=$QC_STATE/loop.json
case ${1:-show} in
set-tests) shift
	if [ "$1" = --from-platform ]; then . "$QC_TOOLS/lib/qc.sh"; IDS=$(qc_get "tests?appId=${QC_APP:-all}" | python3 -I -c 'import sys,json
d=json.load(sys.stdin); d=d.get("tests",d) if isinstance(d,dict) else d
print(" ".join(str(t["id"]) for t in d if not t.get("disabled") and not t.get("is_disabled")))'); else IDS="$*"; fi
	[ -n "$IDS" ] || IDS=$(cfg get loop.iteration_tests); [ -n "$IDS" ] || die "no test ids"; set -- set-tests $IDS ;;
esac
python3 -I - "$F" "$@" <<'PY'
import json,sys,os,time
f=sys.argv[1]; a=sys.argv[2:]
s=json.load(open(f)) if os.path.exists(f) else {"iteration":1,"tests":[],"done":{},"since_change":[],"clean_in_row":0,"changes":[],"clean_iterations":0}
cmd=a[0] if a else "show"
def save(): json.dump(s,open(f+".new","w"),indent=1); os.replace(f+".new",f)
if cmd=="set-tests": s["tests"]=a[1:]; save()
elif cmd=="test-done":
    t,r=a[1],a[2]; s["done"][t]=r
    if r=="pass":
        s["clean_in_row"]+=1
        if t not in s["since_change"]: s["since_change"].append(t)
    else: s["clean_in_row"]=0
    if s["tests"] and all(x in s["done"] for x in s["tests"]):
        clean=all(x in s["since_change"] for x in s["tests"])
        s.setdefault("log",[]).append({"iteration":s["iteration"],"clean":clean,"ended":time.strftime("%F %T")})
        if clean: s["clean_iterations"]+=1
        s["iteration"]+=1; s["done"]={}
    save()
elif cmd=="code-change":
    s["changes"].append({"time":time.strftime("%F %T"),"branch":a[1],"reason":" ".join(a[2:])})
    s["clean_in_row"]=0; s["since_change"]=[]; save()
elif cmd=="is-clean":
    ok=bool(s["tests"]) and all(x in s["since_change"] for x in s["tests"])
    print("CLEAN: every test of the iteration passed since the last code change" if ok else "NOT CLEAN"); sys.exit(0 if ok else 1)
left=[x for x in s["tests"] if x not in s["done"]]
print("iteration %d: %d of %d tests done, %d left (%s); passed in a row with no code change: %d; tests passed since the last code change: %d of %d; clean full iterations: %d; code changes: %d (last: %s)"%(
 s["iteration"],len(s["tests"])-len(left),len(s["tests"]),len(left)," ".join(left) or "-",s["clean_in_row"],
 len([x for x in s["since_change"] if x in s["tests"]]),len(s["tests"]),s["clean_iterations"],len(s["changes"]),
 (s["changes"][-1]["branch"] if s["changes"] else "none")))
PY
