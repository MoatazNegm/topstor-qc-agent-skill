#!/bin/bash
# loop-state.sh <command>   state of the whole loop in state/loop.json (iterations, tests passed in a row with no code change).
#   show                           one line for the report
#   set-tests <id...> | --from-platform   the tests of one full iteration (config loop.iteration_tests, else GET /tests)
#   test-done <test id> <pass|fail>       a platform test finished (pass = every step passed)
#   code-change <branch> <reason...>      a code fix was pushed: a NEW iteration starts from the first test, clean count = 0
#   is-clean                       rc 0 when one whole iteration ran with every test passing, no failed run and no code change (= PR allowed)
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
s=json.load(open(f)) if os.path.exists(f) else {"iteration":1,"tests":[],"done":{},"dirty":False,"clean_in_row":0,"changes":[],"clean_iterations":0}
cmd=a[0] if a else "show"
def save(): json.dump(s,open(f+".new","w"),indent=1); os.replace(f+".new",f)
if cmd=="set-tests": s["tests"]=a[1:]; save()
elif cmd=="test-done":
    t,r=a[1],a[2]; s["done"][t]=r
    if r=="pass": s["clean_in_row"]+=1
    else: s["clean_in_row"]=0; s["dirty"]=True       # a failed run makes THIS iteration not clean, even if the test passes later
    if s["tests"] and all(x in s["done"] for x in s["tests"]):
        clean=(not s.get("dirty")) and all(s["done"][x]=="pass" for x in s["tests"])
        s.setdefault("log",[]).append({"iteration":s["iteration"],"clean":clean,"ended":time.strftime("%F %T")})
        if clean: s["clean_iterations"]+=1
        s["iteration"]+=1; s["done"]={}; s["dirty"]=False
    save()
elif cmd=="code-change":
    # a pushed fix: the version under test changed, so the NEXT run is a whole new iteration from the first test (standing rule:
    # "a new version makes the next run iteration 1 again"); every earlier clean result is void.
    s["changes"].append({"time":time.strftime("%F %T"),"branch":a[1],"reason":" ".join(a[2:]),"at_iteration":s["iteration"]})
    s["clean_in_row"]=0; s["clean_iterations"]=0; s["dirty"]=False
    if s["done"]: s["iteration"]+=1      # an open iteration is abandoned; a just-closed one already advanced the number
    s["done"]={}; save()
elif cmd=="is-clean":
    ok=bool(s["tests"]) and s["clean_iterations"]>=1
    print("CLEAN: one full iteration passed with no failure and no code change" if ok else "NOT CLEAN"); sys.exit(0 if ok else 1)
left=[x for x in s["tests"] if x not in s["done"]]
print("iteration %d: %d of %d tests done, %d left (%s); passed in a row with no code change: %d; clean full iterations: %d; code changes: %d (last: %s)"%(
 s["iteration"],len(s["tests"])-len(left),len(s["tests"]),len(left)," ".join(left) or "-",s["clean_in_row"],
 s["clean_iterations"],len(s["changes"]),
 (s["changes"][-1]["branch"] if s["changes"] else "none")))
PY
