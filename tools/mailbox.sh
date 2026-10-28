#!/bin/bash
# mailbox.sh <send|read|wait> ...   file mailbox between the supervisor and its agents (any agent framework can use it):
#   mailbox.sh send <from> <to> <text...>   -> prints the message id     (e.g. supervisor -> tester: a nudge, an answer, an approval)
#   mailbox.sh read <me> [after-id]         -> messages with id > after-id
#   mailbox.sh wait <me> <after-id> [secs]  -> blocks until a newer message arrives (default 170 s, rc 1 on timeout)
# Append-only, one inbox per recipient under state/mailbox. Messages are masked. Agent messages are never the user's approval.
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
D=$QC_STATE/mailbox; mkdir -p "$D"; cmd=${1:-}; shift
last() { tail -n1 "$D/$1.log" 2>/dev/null | cut -d'|' -f1; }
case $cmd in
send) from=${1:?from}; to=${2:?to}; shift 2
	( flock 9; id=$(( $(last "$to"; echo) + 0 )); id=$((id+1))
	  printf '%s|%s|%s|%s\n' "$id" "$(date +%H:%M:%S)" "$from" "$(echo "$*" | mask | tr '\n' ' ')" >> "$D/$to.log"; echo "$id" ) 9>"$D/.lock" ;;
read) awk -F'|' -v a="${2:-0}" '$1+0>a+0' "$D/${1:?me}.log" 2>/dev/null ;;
wait) t=${3:-170}; end=$((SECONDS+t))
	while [ $SECONDS -lt $end ]; do n=$("$0" read "${1:?me}" "${2:-0}"); [ -n "$n" ] && { echo "$n"; exit 0; }; sleep 3; done; exit 1 ;;
*) sed -n 2,6p "$0"; exit 2 ;;
esac
