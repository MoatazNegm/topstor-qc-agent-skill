# common.sh -- sourced by every tool: skill root, config access, state dir, logging, secret masking.
# Not a command. Env: QC_CONFIG (config file), DRYRUN=1 (node/git/platform writes are printed, not run).
QC_ROOT=${QC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
QC_TOOLS=$QC_ROOT/tools
cfg() { python3 -I "$QC_TOOLS/lib/cfg.py" "$@"; }
cfgn() { python3 -I "$QC_TOOLS/lib/cfg.py" node "$@"; }          # cfgn <node> <field> [default]

_sd=$(cfg get state_dir ./state 2>/dev/null); _sd=${_sd:-./state}
case "$_sd" in /*) QC_STATE=$_sd ;; *) QC_STATE=$QC_ROOT/${_sd#./} ;; esac
mkdir -p "$QC_STATE"/{rounds,tests,ledger,timings,agents,tmp} 2>/dev/null; chmod 700 "$QC_STATE/tmp" 2>/dev/null

die() { echo "$(date +%T) ERROR: $*" >&2; exit "${RC:-1}"; }
log() { echo "$(date +%T) $*"; }

# mask: remove anything that looks like a secret from a text before it is logged or sent as a step comment
# (tokens/keys/passwords in key=value or JSON form, long hex runs, qc_/ghp_/github_pat_ tokens).
# Extra literal words to hide (test passwords typed into steps): one per line in the file $QC_MASK_FILE (never committed).
mask() {
	if [ -n "${QC_MASK_FILE:-}" ] && [ -r "${QC_MASK_FILE:-}" ]; then
		python3 -I -c 'import sys,re
w=[l.strip() for l in open(sys.argv[1]) if l.strip()]
t=sys.stdin.read()
for x in sorted(w,key=len,reverse=True): t=t.replace(x,"-")
sys.stdout.write(t)' "${QC_MASK_FILE:-}"
	else cat; fi | sed -E 's/("?(token|password|passwd|pass|pw|key|apikey|api_key|secret)"? ?[:=] ?"?)[^"&[:space:],}]+/\1-/gI;
	        s/(qc|ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{8,}/\1_-/g;
	        s/[0-9a-fA-F]{32,}/-/g'
}

# secret_tmp <file> -> path of a 600 temp copy of the FIRST line (no newline) of a secret file, for curl @file use.
secret_tmp() {
	[ -r "$1" ] || die "secret file $1 is not readable"
	local t; t=$(mktemp "$QC_STATE/tmp/s.XXXXXX"); chmod 600 "$t"; head -n1 "$1" | tr -d '\r\n' > "$t"; echo "$t"
}

# run: execute, or print to stderr when DRYRUN=1
run() { if [ -n "${DRYRUN:-}" ]; then echo "DRYRUN: $*" >&2; else "$@"; fi; }

# round_dir <round> -> absolute dir of a round under state/rounds
round_dir() { echo "$QC_STATE/rounds/${1:?round name}"; }
