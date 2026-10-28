# tstor.sh -- TopStor REST API helpers (http://<ip>:<api_port>/api/v1). Sourced. Passwords come from FILES only.
. "$(dirname "${BASH_SOURCE[0]}")/node.sh"
TS_PORT=$(cfg get cluster.api_port 5001)
TS_USER=$(cfg get cluster.admin_user admin)
# pwfile_for <cluster ip>: the admin password file of that cluster (cluster 1 or the second cluster)
pwfile_for() { if [ -n "$1" ] && [ "$1" = "$(cfg get cluster.second_cluster_ip)" ]; then cfg get cluster.second_admin_password_file; else cfg get cluster.admin_password_file; fi; }
# ts_token <ip> [password file] [user, default cluster.admin_user] -> token on stdout (empty / "baduser" on failure)
ts_token() { local ip=$1 pf=${2:-$(pwfile_for "$1")} t; t=$(secret_tmp "$pf") || return 1
	curl -s -m 20 -G "http://$ip:$TS_PORT/api/v1/login" --data-urlencode "user=${3:-$TS_USER}" --data-urlencode "pass@$t" \
		| python3 -I -c 'import sys,json;print(json.load(sys.stdin)["token"])' 2>/dev/null; rm -f "$t"; }
# ts_api <ip> <GET|POST> <path> [curl args...]: adds token + user. Output = the JSON reply.
ts_api() { local ip=$1 m=$2 p=$3 tk; shift 3; tk=$(ts_token "$ip") || return 1
	[ -n "$tk" ] && [ "$tk" != baduser ] || { echo "no TopStor login on $ip" >&2; return 1; }
	[ -n "${DRYRUN:-}" ] && [ "$m" != GET ] && { echo "DRYRUN: would $m $p on $ip (not sent)" >&2; echo '{}'; return 0; }
	curl -s -m 120 -X "$m" -G "http://$ip:$TS_PORT/api/v1/$p" --data-urlencode "token=$tk" --data-urlencode "user=$TS_USER" "$@"; }
# ts_isinsync <ip> -> value of the isinsync field (the UI's "Cluster in Sync" sign)
ts_isinsync() { ts_api "$1" GET info/notification | python3 -I -c 'import sys,json;print(json.load(sys.stdin).get("isinsync"))' 2>/dev/null; }
ts_green() { case "$1" in True|true|yes|1|insync) return 0;; esac; return 1; }
# etcd_get <node> <etcd ip> <key> [--prefix]: read the product's etcd through its own etcdget.py on a node
etcd_get() { local n=$1; shift; node_exec "$n" "cd $(cfg get repos.node_paths.topstor /TopStor) && ./etcdget.py $*" 2>/dev/null | grep -v setlocale | tr '\n' ' '; }
# setup_running <node>: docker_setup.sh (the product's setup) still runs on the node
setup_running() { node_exec "$1" 'ps aux | grep -q "[d]ocker_setup"' >/dev/null 2>&1; }
# pools_on <node>: imported pools seen by the node (container flavour: every pool of the shared kernel)
pools_on() { node_exec "$1" 'timeout 10 zpool list -H -o name' 2>/dev/null | grep -v setlocale; }
pool_state() { node_exec "$1" "timeout 10 zpool list -H -o health $2" 2>/dev/null | grep -v setlocale | head -1; }
# pools_owned <node>: pools this node owns (product helper /pace/cpoolowner.sh)
pools_owned() { local h; h=$(node_exec "$1" hostname 2>/dev/null | tr -d '\r\n'); node_exec "$1" "$(cfg get repos.node_paths.pace /pace)/cpoolowner.sh mine $h" 2>/dev/null | grep -v setlocale; }
zpool_answers() { node_exec "$1" 'timeout 10 zpool list -H -o name >/dev/null 2>&1'; }
