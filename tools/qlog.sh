#!/bin/bash
# qlog.sh <file> [n]   quiet view of a log/status file: line count, count of error/fail lines, last n (default 5) lines cut to 200 chars. Read-only.
F=${1:?file}; N=${2:-5}; [ -f "$F" ] || { echo "QLOG no file $F"; exit 1; }
echo "QLOG $F: $(wc -l < "$F") lines, $(grep -aciE 'error|fail|traceback' "$F") error/fail lines; last $N:"; tail -n "$N" "$F" | cut -c1-200
