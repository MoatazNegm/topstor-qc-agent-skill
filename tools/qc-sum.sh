#!/bin/bash
# qc-sum.sh [test] [step_no]   summary of state/qc-step-times.csv (PASSED steps of every round): no args = per test (rounds, steps,
# total); <test> = per step (passes, min/avg/max s, last); <test> <step> = every pass of that step. Input for the speed-up plan.
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
python3 -I - "$QC_STATE/qc-step-times.csv" "$@" <<'PY'
import csv,sys,os
if not os.path.exists(sys.argv[1]): print("no timings yet"); sys.exit()
rows=list(csv.DictReader(open(sys.argv[1]))); a=sys.argv[2:]
for r in rows: r["sec"]=int(r["seconds"])
sel=[r for r in rows if not a or r["test"]==a[0]]
if len(a)>1: sel=[r for r in sel if r["step_no"]==a[1]]
st=lambda v:"min %d avg %d max %d"%(min(v),sum(v)/len(v),max(v))
if not a:
    for t in sorted({r["test"] for r in rows},key=int):
        v=[r for r in rows if r["test"]==t]; s=[r["sec"] for r in v]
        print("test %s: rounds %d, passed steps %d, total %d s (%.1f min)"%(t,len({r["round"] for r in v}),len(v),sum(s),sum(s)/60))
elif len(a)==1:
    for n in sorted({r["step_no"] for r in sel},key=lambda x:int(x or 0)):
        v=[r for r in sel if r["step_no"]==n]; s=[r["sec"] for r in v]
        print("step %s: passes %d, %s, last %s %s  %s"%(n,len(v),st(s),v[-1]["passed_date"],v[-1]["passed_time"],v[-1]["description"][:50]))
else:
    for r in sel: print("round %s  %s %s  %d s"%(r["round"],r["passed_date"],r["passed_time"],r["sec"]))
PY
