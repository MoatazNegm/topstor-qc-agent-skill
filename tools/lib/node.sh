# node.sh -- node abstraction: picks the backend of a node's type (container | physical | virtualbox) from the
# config and offers node_* functions + wait helpers. Sourced by the node-* tools and the cluster tools.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
node_type() { local t; t=$(cfgn "$1" type) || exit 3; [ -n "$t" ] || die "node $1 has no type"; echo "$t"; }
_load() { local t; t=$(node_type "$1") || exit 3; [ -f "$QC_TOOLS/lib/nodetype/$t.sh" ] || die "unknown node type $t"; . "$QC_TOOLS/lib/nodetype/$t.sh"; }
node_exec()     { ( _load "$1"; t_exec "$@" ); }
node_copy()     { ( _load "$1"; t_copy "$@" ); }
node_copy_from(){ ( _load "$1"; t_copy_from "$@" ); }
node_start()    { ( _load "$1"; t_start "$@" ); }
node_state()    { ( _load "$1"; t_state "$@" ); }
node_bootid()   { ( _load "$1"; t_bootid "$@" ); }
# stop/reboot of a cluster node only through the guarded cluster tools (QC_GUARDED=1); clients may be stopped directly
_guard() { local r; r=$(cfgn "$1" role); [ "$r" = client ] || [ -n "${QC_GUARDED:-}" ] || [ -n "${DRYRUN:-}" ] || {
	echo "REFUSED: $1 is a cluster node; stop it with tools/cluster-stopnode.sh (exports its pools first, guards iSCSI)" >&2; exit 5; }; }
node_stop()     { _guard "$1"; ( _load "$1"; t_stop "$@" ); }
node_reboot()   { _guard "$1"; ( _load "$1"; t_reboot "$@" ); }

# node_wait_up <node> [timeout s]: until node-exec works
node_wait_up() { local n=$1 to=${2:-900} t=0; [ -n "${DRYRUN:-}" ] && return 0
	until node_exec "$n" true >/dev/null 2>&1; do sleep 5; t=$((t+5)); [ $t -ge "$to" ] && { log "node $n not reachable after ${to}s"; return 1; }; done; }
# node_wait_down <node> [timeout s]
node_wait_down() { local n=$1 to=${2:-300} t=0; [ -n "${DRYRUN:-}" ] && return 0
	until [ "$(node_state "$n")" != running ]; do sleep 5; t=$((t+5)); [ $t -ge "$to" ] && { log "node $n still running after ${to}s"; return 1; }; done; }
# node_wait_reboot <node> <old boot id> [timeout s]: until the boot id changed and the node answers
node_wait_reboot() { local n=$1 old=$2 to=${3:-900} t=0 b; [ -n "${DRYRUN:-}" ] && return 0
	while :; do b=$(node_bootid "$n" 2>/dev/null); [ -n "$b" ] && [ "$b" != "$old" ] && node_exec "$n" true >/dev/null 2>&1 && return 0
		sleep 5; t=$((t+5)); [ $t -ge "$to" ] && { log "node $n did not come back from a restart within ${to}s"; return 1; }; done; }
# all cluster (non-client) nodes of cluster N (default all clusters)
cluster_nodes() { if [ -n "$1" ]; then cfg nodes --cluster "$1"; else cfg nodes; fi | while read -r n; do [ "$(cfgn "$n" role)" = client ] || echo "$n"; done; }
primary_of() { local c=${1:-1} n; for n in $(cfg nodes --cluster "$c"); do case "$(cfgn "$n" role)" in primary|replication-primary) echo "$n"; return;; esac; done; }
# require_local_kernel: the host-* clean-up tools act on THIS machine's kernel; refuse when a container node lives on a remote docker host
require_local_kernel() { local n h; for n in $(cluster_nodes); do [ "$(node_type "$n")" = container ] || continue
	h=$(cfgn "$n" docker_host); [ -z "$h" ] || { log "REFUSED: $n uses the remote docker host $h; the host-* tools would clean the wrong kernel. Run them on that docker host."; exit 5; }; done; }
