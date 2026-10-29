#!/bin/bash
# qc-submit.sh <round> <test id> <step id> <pass|fail> <comment file> [--config]   submit ONE step result, exactly ONE try, then prove it
# (merges qcsubmit.sh + sub.sh + st.sh). Before: ledger (never a second submission of a step in a round), health gate (GET only).
# After: reply must carry the result, history must show exactly ONE new row with that result, monthEarned before -> after compared
# with pointsAwarded; a STEPCHECK line goes to the round's run.log. --config attaches the configuration zip of all nodes (always for
# a FAIL and for the "upload the config files" step). A FAIL is refused unless QC_FAIL_VERDICT names a validator file containing
# "VERDICT: REAL_APP_BUG" (FAIL only for a real app-code bug). Comments are masked (no tokens/passwords; QC_MASK_FILE adds words).
# rc: 0 stored and checked | 1 rejected | 2 UNKNOWN (empty reply/timeout; NOT retried, decide by hand) | 3 already submitted |
#     4 FAIL without verdict/config | 9 skill tree MODIFIED and QC_ACK_MODIFIED=1 not set (user acknowledgement) | 6 platform unhealthy, nothing sent | 7 history check failed | 8 points mismatch.
# The comment gets a last line "[skill vX.Y.Z manifest <12 hex> OK|MODIFIED]" (verify-manifest.sh); audit aid only.
# On rc != 0 a STOPPED-SUBMIT line is written: STOP, tell the supervisor; no retry, no resubmit, no delete.
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
. "$QC_TOOLS/lib/tstor.sh"
R=${1:?round}; T=${2:?test id}; S=${3:?step id}; RES=${4:?pass|fail}; CF=${5:?comment file}; MODE=$6
D=$(round_dir "$R"); L=$D/run.log; [ -d "$D" ] || die "no round $R (round-new.sh first)"
stop() { echo "$(date +%T) STOPPED-SUBMIT test $T $(step_words "$T" "$S") id $S: $2" | mask | tee -a "$L" >&2; exit "$1"; }
case $RES in pass|fail) ;; *) die "result must be pass or fail";; esac
LED=$QC_STATE/ledger/$R.sent
grep -qx "$T:$S" "$LED" 2>/dev/null && stop 3 "ledger: already submitted in round $R -- never submitted twice"
if [ "$RES" = fail ]; then
	[ "$MODE" = --config ] || stop 4 "a FAIL needs --config (configuration files of all nodes attached)"
	[ -n "${QC_FAIL_VERDICT:-}" ] && grep -q 'VERDICT: REAL_APP_BUG' "$QC_FAIL_VERDICT" 2>/dev/null || stop 4 "FAIL held: no validator verdict REAL_APP_BUG (QC_FAIL_VERDICT); tool, environment, guard refusal or sheet differences are never a FAIL"
fi
W=$(mktemp -d "$QC_STATE/tmp/sub.XXXXXX"); trap 'rm -rf "$W"' EXIT
mask < "$CF" | cut -c1-6000 > "$W/comment"
[ -s "$W/comment" ] || stop 4 "empty comment: every result needs evidence (command/API call and what came back)"
# Audit stamp (docs/integrity.md): every step comment ends with "skill vX.Y.Z manifest <12 hex> OK|MODIFIED". An AUDIT aid, not enforcement.
SV=$(cat "$QC_ROOT/VERSION" 2>/dev/null || echo unknown); MH=$("$QC_TOOLS/verify-manifest.sh" --hash | cut -c1-12); MS=$("$QC_TOOLS/verify-manifest.sh" --status); MH=${MH:-none}
[ "$MS" != OK ] && [ "${QC_ACK_MODIFIED:-}" != 1 ] && stop 9 "skill tree is not OK (status ${MS:-empty}: a listed file differs from MANIFEST.sha256): nothing sent; tell the user, who may set QC_ACK_MODIFIED=1 to acknowledge"
STAMP="skill v$SV manifest $MH ${MS:-MODIFIED}"; printf '\n[%s]\n' "$STAMP" >> "$W/comment"
if [ -n "${DRYRUN:-}" ]; then echo "DRYRUN: would submit test $T step $S $RES ${MODE} comment: $(head -c 200 "$W/comment")"; exit 0; fi
ok=0; for i in 1 2 3 4 5 6; do o=$(qc_code tests/active); c=${o% *}; t=${o#* }; [ "$c" = 200 ] && [ "${t%.*}" -lt 5 ] && { ok=1; break; }
	log "platform GET slow/err before submit: http $c ${t}s (try $i)" >> "$L"; sleep 30; done
[ $ok = 1 ] || stop 6 "platform unhealthy for 3 minutes; nothing was sent"
# K-02: the platform must name THIS step as the next one (a replacement agent or a second round of the same test must not submit a stored step again).
# The id is read from the reply of GET test-results/<T>/next (fields id | step_id | step.id | nextStep.id); an unreadable reply is a NOTE only (the history check below still proves one row).
NXJ=$(qc_get "test-results/$T/next"); # real shape (platform OpenAPI): 200 {"step":{"id",...},"test_id","test_name"}; 404 {"error":"No more steps","allDone":true} = every step answered.
if echo "$NXJ" | python3 -I -c 'import sys,json
d=json.load(sys.stdin);sys.exit(0 if isinstance(d,dict) and (d.get("allDone") is True or d.get("error")=="No more steps") else 1)' 2>/dev/null; then
	stop 3 "platform says every step of test $T is answered (allDone): nothing sent"; fi
NX=$(echo "$NXJ" | python3 -I -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit()
for k in ("id","step_id"):
    if isinstance(d,dict) and d.get(k) is not None: print(d[k]); sys.exit()
for k in ("step","nextStep","next"):
    if isinstance(d,dict) and isinstance(d.get(k),dict) and d[k].get("id") is not None: print(d[k]["id"]); sys.exit()' 2>/dev/null)
if [ -n "$NX" ]; then [ "$NX" = "$S" ] || stop 3 "platform says the next step of test $T is $NX, not $S: step $S is already stored or out of order (resume the existing round; do not submit again)"
else echo "$(date +%T) NOTE could not read the next step from the platform (reply: $(echo "$NXJ" | tr -d '\n' | cut -c1-80)); relying on ledger + history check" >> "$L"; fi
SINCE=$(cat "$D/startts" 2>/dev/null || date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S)
E0=$(qc_earned); read -r H0 _ <<< "$(qc_hist_rows "$T" "$S" "$SINCE")"
case "$H0" in ""|*[!0-9]*) stop 6 "history unreadable before the submit (no proof possible afterwards); nothing was sent";; esac
ZIP=
if [ "$MODE" = --config ]; then
	getcfg() { local ip=$1 out=$2 tk; tk=$(ts_token "$ip"); [ -n "$tk" ] && [ "$tk" != baduser ] || return 1
		curl -s -m 300 -o "$out" -G "http://$ip:$TS_PORT/api/v1/hosts/getAllConfig" --data-urlencode "token=$tk" && unzip -tq "$out" >/dev/null 2>&1; }
	if getcfg "$(cfg get cluster.cluster_ip)" "$W/All_Configs.zip"; then
		C2=$(cfg get cluster.second_cluster_ip)
		if [ -n "$C2" ] && getcfg "$C2" "$W/c2.zip"; then
			mkdir -p "$W/all"; unzip -qo "$W/All_Configs.zip" -d "$W/all"; unzip -qo "$W/c2.zip" -d "$W/all"; rm -f "$W/All_Configs.zip"; (cd "$W/all" && zip -qr ../All_Configs.zip .)
		fi; ZIP=$W/All_Configs.zip
	else echo " (configuration files could not be downloaded from the cluster; submitted without them)" >> "$W/comment"; fi
fi
if [ -n "$ZIP" ]; then
	O=$(qc_curl "test-results/$T/steps/$S" -m 180 -w '\n__HTTP__%{http_code}' -X POST -F "result=$RES" -F "comment=<$W/comment" -F "configFile=@$ZIP;filename=All_Configs.zip")
else
	python3 -I -c 'import json,sys;print(json.dumps({"result":sys.argv[1],"comment":open(sys.argv[2]).read()}))' "$RES" "$W/comment" > "$W/body.json"
	O=$(qc_curl "test-results/$T/steps/$S" -w '\n__HTTP__%{http_code}' -X POST -H "Content-Type: application/json" -d @"$W/body.json")
fi
NOW=$(date +%s)
HC=${O##*__HTTP__}; O=${O%$'\n'__HTTP__*}; case $HC in [0-9][0-9][0-9]) ;; *) HC=000; esac
if [ -z "$(echo "$O" | tr -d '[:space:]')" ]; then
	sleep 20; read -r H1 _ <<< "$(qc_hist_rows "$T" "$S" "$SINCE")"
	[ "$H1" = $((H0+1)) ] && O="{\"result\":\"$RES\",\"note\":\"empty reply but history shows the row\"}" || stop 2 "UNKNOWN: empty reply/timeout and no new history row yet (rows $H0 -> $H1); NOT retried -- decide by hand"
fi
if ! echo "$O" | grep -qi "\"result\": *\"$RES\""; then
	# L-06: only a 4xx with a JSON "error" is a rejection (a success reply also carries "message"); L-06 http code in $HC.
	# K-03: a reply without the result (HTML 502/504, cut body) may still have stored the step: look at the history before calling it rejected
	if echo "$O" | python3 -I -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if isinstance(d,dict) and d.get("error") else 1)' 2>/dev/null && case $HC in 4??) true;; *) false;; esac; then
		stop 1 "rejected (http $HC): $(echo "$O" | cut -c1-300)"; fi
	sleep 20; read -r H1 _ <<< "$(qc_hist_rows "$T" "$S" "$SINCE")"
	if [ "$H1" = $((H0+1)) ]; then echo "$(date +%T) NOTE reply was not the expected result JSON but the history shows the row: $(echo "$O" | tr -d '\n' | cut -c1-80)" >> "$L"; O="{\"result\":\"$RES\"}"
	else stop 2 "UNKNOWN: reply without the result ($(echo "$O" | tr -d '\n' | cut -c1-120)) and no new history row (rows $H0 -> $H1); NOT retried -- decide by hand"; fi
fi
echo "$T:$S" >> "$LED"
PTS=$(echo "$O" | qc_json pointsAwarded 2>/dev/null); WARN=$(echo "$O" | qc_json warning 2>/dev/null); AE=$(echo "$O" | qc_json autoEnded 2>/dev/null); [ "$AE" = true ] || AE=
if [ "$RES" = pass ]; then LAST=$QC_STATE/timings/.last_$T; if [ -f "$LAST" ]; then
	python3 -I - "$QC_STATE/qc-step-times.csv" "$T" "$S" "$((NOW-$(cat "$LAST")))" "$(step_words "$T" "$S")" "$R" <<'PY'
import csv,os,sys,time
c,t,s,sec,words,r=sys.argv[1:7]; new=not os.path.exists(c)
with open(c,"a",newline="") as f:
    w=csv.writer(f)
    if new: w.writerow(["passed_date","passed_time","test","step_no","step_id","seconds","round","description"])
    n=words.split()[1] if words.startswith("step ") else ""
    w.writerow([time.strftime("%F"),time.strftime("%T"),t,n,s,sec,r,words])
PY
fi; fi
echo "$NOW" > "$QC_STATE/timings/.last_$T"
sleep 3; E1=$(qc_earned); n=; for i in 1 2 3 4 5 6; do read -r n rs <<< "$(qc_hist_rows "$T" "$S" "$SINCE")"; [ "$n" = $((H0+1)) ] && break; sleep 10; done
echo "$(date +%T) STEPCHECK test $T $(step_words "$T" "$S") id $S: submitted $RES; monthEarned $E0 -> $E1 (pointsAwarded ${PTS:-?}); history rows for this step this round: $n ($rs), $STAMP, stored once: $([ "$n" = $((H0+1)) ] && echo yes || echo NO)${WARN:+; platform warning: $WARN}${AE:+; autoEnded=$AE}" | mask | tee -a "$L"
[ "$AE" = true ] && echo "$(date +%T) NOTE AUTOENDED: the platform ended test $T after this step (on_failure stop); take the next test from GET /tests/active" >> "$L"
[ "$n" = $((H0+1)) ] || stop 7 "history check: expected one new row, found '$n'"
if [ "$RES" = pass ] && [ -n "$PTS" ] && [ "$PTS" -gt 0 ] 2>/dev/null && [ -n "$E0" ] && [ -n "$E1" ] && [ $((E1-E0)) -ne "$PTS" ] 2>/dev/null; then
	stop 8 "points mismatch: monthEarned rose by $((E1-E0)), reply said $PTS"; fi
exit 0
