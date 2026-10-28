#!/bin/bash
# qc-submit.sh <round> <test id> <step id> <pass|fail> <comment file> [--config]   submit ONE step result, exactly ONE try, then prove it
# (merges qcsubmit.sh + sub.sh + st.sh). Before: ledger (never a second submission of a step in a round), health gate (GET only).
# After: reply must carry the result, history must show exactly ONE new row with that result, monthEarned before -> after compared
# with pointsAwarded; a STEPCHECK line goes to the round's run.log. --config attaches the configuration zip of all nodes (always for
# a FAIL and for the "upload the config files" step). A FAIL is refused unless QC_FAIL_VERDICT names a validator file containing
# "VERDICT: REAL_APP_BUG" (FAIL only for a real app-code bug). Comments are masked (no tokens/passwords; QC_MASK_FILE adds words).
# rc: 0 stored and checked | 1 rejected | 2 UNKNOWN (empty reply/timeout; NOT retried, decide by hand) | 3 already submitted |
#     4 FAIL without verdict/config | 6 platform unhealthy, nothing sent | 7 history check failed | 8 points mismatch.
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
if [ -n "${DRYRUN:-}" ]; then echo "DRYRUN: would submit test $T step $S $RES ${MODE} comment: $(head -c 200 "$W/comment")"; exit 0; fi
ok=0; for i in 1 2 3 4 5 6; do o=$(qc_code tests/active); c=${o% *}; t=${o#* }; [ "$c" = 200 ] && [ "${t%.*}" -lt 5 ] && { ok=1; break; }
	log "platform GET slow/err before submit: http $c ${t}s (try $i)" >> "$L"; sleep 30; done
[ $ok = 1 ] || stop 6 "platform unhealthy for 3 minutes; nothing was sent"
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
	O=$(qc_curl "test-results/$T/steps/$S" -m 180 -X POST -F "result=$RES" -F "comment=<$W/comment" -F "configFile=@$ZIP;filename=All_Configs.zip")
else
	python3 -I -c 'import json,sys;print(json.dumps({"result":sys.argv[1],"comment":open(sys.argv[2]).read()}))' "$RES" "$W/comment" > "$W/body.json"
	O=$(qc_curl "test-results/$T/steps/$S" -X POST -H "Content-Type: application/json" -d @"$W/body.json")
fi
NOW=$(date +%s)
if [ -z "$(echo "$O" | tr -d '[:space:]')" ]; then
	sleep 20; read -r H1 _ <<< "$(qc_hist_rows "$T" "$S" "$SINCE")"
	[ "$H1" = $((H0+1)) ] && O="{\"result\":\"$RES\",\"note\":\"empty reply but history shows the row\"}" || stop 2 "UNKNOWN: empty reply/timeout and no new history row yet (rows $H0 -> $H1); NOT retried -- decide by hand"
fi
echo "$O" | grep -qi "\"result\": *\"$RES\"" || stop 1 "rejected: $(echo "$O" | cut -c1-300)"
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
echo "$(date +%T) STEPCHECK test $T $(step_words "$T" "$S") id $S: submitted $RES; monthEarned $E0 -> $E1 (pointsAwarded ${PTS:-?}); history rows for this step this round: $n ($rs), stored once: $([ "$n" = $((H0+1)) ] && echo yes || echo NO)${WARN:+; platform warning: $WARN}${AE:+; autoEnded=$AE}" | mask | tee -a "$L"
[ "$AE" = true ] && echo "$(date +%T) NOTE AUTOENDED: the platform ended test $T after this step (on_failure stop); take the next test from GET /tests/active" >> "$L"
[ "$n" = $((H0+1)) ] || stop 7 "history check: expected one new row, found '$n'"
if [ "$RES" = pass ] && [ -n "$PTS" ] && [ "$PTS" -gt 0 ] 2>/dev/null && [ -n "$E0" ] && [ -n "$E1" ] && [ $((E1-E0)) -ne "$PTS" ] 2>/dev/null; then
	stop 8 "points mismatch: monthEarned rose by $((E1-E0)), reply said $PTS"; fi
exit 0
