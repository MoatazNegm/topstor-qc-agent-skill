#!/bin/bash
# ts-user.sh [--cluster N] <list|add <name> <password file> [group ids]|login <name> <password file>|uid <node> <name>>
# User calls of the product API (adapted userlib.sh). The password of the NEW user is read from a file (first line) and sent as a
# form field from that file: it never appears on a command line, in the log or in a comment. group ids are the ids the API wants, not
# group names. login answers 0 when the user can log in through the cluster API.
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
CL=1; [ "${1:-}" = --cluster ] && { CL=$2; shift 2; }
CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip)
C=${1:?list|add|login|uid}; shift
case $C in
list) ts_api "$CIP" GET users/userlist --data-urlencode tenant=Cluster | python3 -I -c 'import sys,json;print(" ".join(sorted(u["name"] for u in json.load(sys.stdin)["allusers"])))';;
add) t=$(secret_tmp "${2:?password file}") || die "password file not readable"
	ts_api "$CIP" POST users/UnixAddUser -w ' HTTP%{http_code}' --data-urlencode "name=${1:?name}" --data-urlencode "Password@$t" --data-urlencode "groups=${3:-}" \
		--data-urlencode Volpool=NoHome --data-urlencode Volsize=1 --data-urlencode HomeAddress=NoAddress --data-urlencode HomeSubnet=8 \
		--data-urlencode "Myname=$TS_USER" | tr -d '\n' | cut -c1-400; echo; rm -f "$t";;
login) tk=$(ts_token "$CIP" "${2:?password file}"); [ -n "$tk" ] && [ "$tk" != baduser ] || exit 1;;   # NOTE: ts_token logs in as cluster.admin_user: for another user set cluster.admin_user in a copy of the config
uid) node_exec "${1:?node}" "getent passwd ${2:?name}" | cut -d: -f3;;
*) die "unknown command $C";;
esac
