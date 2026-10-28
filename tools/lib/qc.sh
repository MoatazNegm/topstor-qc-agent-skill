# qc.sh -- QualityCheck platform helpers. Sourced. The tester key is read from platform.tester_key_file at call time and handed
# to curl through a header FILE descriptor (never on the command line, never printed, only sent to platform.url).
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
QC_URL=$(cfg get platform.url); QC_URL=${QC_URL%/}
QC_APP=$(cfg get platform.app_id)
QC_KEYF=$(cfg get platform.tester_key_file)
_qc_hdr() { printf 'X-API-Key: %s\n' "$(head -n1 "$QC_KEYF" | tr -d '\r\n')"; [ -n "$QC_APP" ] && printf 'X-App-Id: %s\n' "$QC_APP"; }
# qc_curl <path> [curl args...] -> reply body on stdout
qc_curl() { local p=$1; shift; [ -r "$QC_KEYF" ] || die "tester key file not readable: $QC_KEYF"
	curl -s -m "${QC_TIMEOUT:-60}" -H @<(_qc_hdr) "$@" "$QC_URL/${p#/}"; }
qc_get() { qc_curl "$1"; }
# qc_code <path>: "http_code seconds" of a GET (health gate before a submit)
qc_code() { qc_curl "$1" -o /dev/null -w '%{http_code} %{time_total}'; }
qc_json() { python3 -I -c 'import sys,json
d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d=d.get(k) if isinstance(d,dict) else None
print("" if d is None else (json.dumps(d) if isinstance(d,(dict,list,bool)) else d))' "$1"; }
qc_earned() { qc_get test-results/summary | qc_json monthEarned 2>/dev/null; }
# qc_hist_rows <test> <step> <since ISO-UTC> -> "<count> <results...>" of history rows of that step after the time
qc_hist_rows() { local f; f=$(mktemp "$QC_STATE/tmp/h.XXXXXX")
	for i in 1 2 3 4 5 6; do qc_get test-results/history > "$f"; python3 -I -c 'import json,sys;json.load(open(sys.argv[1]))' "$f" 2>/dev/null && break; sleep 5; done
	python3 -I - "$f" "$1" "$2" "$3" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print("? nohistory"); sys.exit()
if isinstance(d,dict): d=d.get("history") or d.get("results") or []
t,s,since=int(sys.argv[2]),int(sys.argv[3]),sys.argv[4]
r=[x for x in d if int(x.get("test_id",-1))==t and int(x.get("step_id",-1))==s and str(x.get("executed_at",""))[:19]>=since[:19]]
print(len(r)," ".join(str(x.get("result")) for x in r))
PY
	rm -f "$f"; }
# step_words <test> <step id> -> "step <n> (<description, 60 chars>)" from the downloaded steps file
step_words() { python3 -I - "$QC_STATE/tests/test$1.json" "$2" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1])); d=d.get("activeTest") or d.get("test") or d
    s=[x for x in d["steps"] if str(x["id"])==sys.argv[2]][0]
    print("step %s (%s)"%(s["step_number"]," ".join(s["description"].split())[:60]))
except Exception: print("step id "+sys.argv[2])
PY
}
