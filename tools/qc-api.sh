#!/bin/bash
# qc-api.sh <me|active|next <test>|test <test>|tests|summary|history|warnings|guide>   read-only platform calls, JSON to stdout
# (guide = the platform's markdown user guide; read it first, it may have changed). Nothing here writes to the platform.
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
case ${1:-} in
me) qc_get api-keys/me ;;
active) qc_get tests/active ;;
next) qc_get "test-results/${2:?test id}/next" ;;
test) qc_get "tests/${2:?test id}" ;;
tests) qc_get "tests?appId=${QC_APP:-all}" ;;
summary) qc_get test-results/summary ;;
history) qc_get test-results/history ;;
warnings) qc_get test-results/warnings ;;
guide) qc_get docs/get_user_guide ;;
*) sed -n 2,3p "$0"; exit 1 ;;
esac
