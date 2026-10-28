#!/bin/bash
# stage-times.sh <log file> <run name>   append the duration of every "HH:MM:SS STAGE <n> <text>" line of a driver log to
# state/qc-stage-times.csv (run, stage, started, seconds, text); the last stage counts only when a DONE line follows.
# Use it to find slow stages (anything slower than the previous run is investigated at once).
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
python3 -I - "$QC_STATE/qc-stage-times.csv" "${1:?log file}" "${2:?run name}" <<'PY'
import sys,re,csv,os
out,lf,run=sys.argv[1:4]
have={(r[0],r[1]) for r in csv.reader(open(out))} if os.path.exists(out) else set()
new=not os.path.exists(out); f=open(out,"a",newline=""); w=csv.writer(f)
if new: w.writerow(["run","stage","started","seconds","text"])
ev=[(m.group(1),m.group(2).strip()) for m in (re.match(r"(\d\d:\d\d:\d\d) (.*)",l) for l in open(lf,errors="ignore")) if m]
sec=lambda t:(lambda h,m,s:h*3600+m*60+s)(*map(int,t.split(":")))
st=[(t,x) for t,x in ev if re.match(r"STAGE \d+",x)]
done=any(re.search(r"\bDONE\b",x) for _,x in ev)
for i,(t,x) in enumerate(st):
    if i+1<len(st): e=st[i+1][0]
    elif done: e=ev[-1][0]
    else: continue
    k=re.match(r"STAGE (\d+)",x).group(1)
    if (run,k) in have: continue
    w.writerow([run,k,t,(sec(e)-sec(t))%86400,x[:80]])
print("written to",out)
PY
