#!/bin/bash
# qc-start.sh <test id>   mark "now" as the start of the next step of a test for the step timing (qc-submit.sh writes the seconds of
# every PASSED step since the previous submission or this mark to state/qc-step-times.csv; failed steps are not timed).
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
date +%s > "$QC_STATE/timings/.last_${1:?test id}"
