#!/bin/bash
# qtail.sh <label> -- <command...>   run a noisy command quietly (build/reset/join, zpool/etcd/status dumps): full output to state/quiet/<label>.out;
#   success prints "QTAIL <label> rc=0" + the last 5 lines, failure prints the rc + the last 20 lines. Tokens/passwords/32-hex ids masked.
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
L=${1:?label}; shift; [ "${1:-}" = -- ] && shift; [ $# -gt 0 ] || die "no command"
mkdir -p "$QC_STATE/quiet"; F=$QC_STATE/quiet/$L.out
"$@" > "$F" 2>&1; rc=$?; sed -i -E 's/"(token|password|pass)": ?"[^"]*"/"\1":"-"/g;s/[0-9a-f]{32}/-/g' "$F"
if [ $rc = 0 ]; then echo "QTAIL $L rc=0 ($(wc -l < "$F") lines, full: $F):"; tail -n 5 "$F" | cut -c1-200
else echo "QTAIL $L FAILED rc=$rc ($(wc -l < "$F") lines, full: $F); last 20:"; tail -n 20 "$F" | cut -c1-200; fi
exit $rc
