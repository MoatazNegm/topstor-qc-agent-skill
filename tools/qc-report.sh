#!/bin/bash
# qc-report.sh [test...]   timing report from state/qc-step-times.csv: per test the passed rows, time span, total minutes and the 4
# slowest steps (default: the last 4 tests). Show it to the user after every finished test.
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
python3 -I - "$QC_STATE/qc-step-times.csv" "$@" <<'PY'
import csv,sys,collections,os
if not os.path.exists(sys.argv[1]): print("no timings yet"); sys.exit()
r=list(csv.DictReader(open(sys.argv[1]))); by=collections.defaultdict(list)
for x in r: by[x['test']].append(x)
tests=sys.argv[2:] or sorted(by,key=lambda t:int(t))[-4:]
for t in tests:
    xs=by.get(t,[])
    if not xs: continue
    tot=sum(int(x['seconds']) for x in xs)
    print(f"test {t}: {len(xs)} passed steps, {xs[0]['passed_date']} {xs[0]['passed_time']} .. {xs[-1]['passed_date']} {xs[-1]['passed_time']}, total {tot//60}m{tot%60}s")
    for x in sorted(xs,key=lambda x:-int(x['seconds']))[:4]: print(f"   {x['description'][:70]}: {x['seconds']}s (round {x['round']})")
PY
