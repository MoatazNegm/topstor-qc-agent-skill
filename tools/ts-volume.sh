#!/bin/bash
# ts-volume.sh [--cluster N] <list [CIFS|HOME]|create-cifs <pool> <name> <ip> [size GB] [groups]|del <CIFS|HOME> <full volume name>>
# Volume calls of the product API (same as the UI; adapted vollib.sh). groups are GROUP IDS as the API wants them, not names
# (look them up with the groups call of your product version). Default size 1 GB, subnet bits from cluster.subnet_bits.
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
CL=1; [ "${1:-}" = --cluster ] && { CL=$2; shift 2; }
CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip); BITS=$(cfg get cluster.subnet_bits 24)
C=${1:?list|create-cifs|del}; shift
case $C in
list) T=${1:-CIFS}; ts_api "$CIP" GET "volumes/$T/volumesinfo" | python3 -I -c 'import sys,json
for v in json.load(sys.stdin).get("allvolumes",[]): print(v["name"],v.get("ipaddress"),v.get("pool"),v.get("statusmount"),v.get("runtime"),"groups="+str(v.get("groups")))';;
create-cifs) ts_api "$CIP" POST volumes/create --data-urlencode type=CIFS --data-urlencode "pool=${1:?pool}" --data-urlencode "name=${2:?name}" \
	--data-urlencode "ipaddress=${3:?ip}" --data-urlencode "size=${4:-1}G" --data-urlencode "groups=${5:-Everyone}" --data-urlencode "Subnet=$BITS" \
	--data-urlencode active=active --data-urlencode compression=on --data-urlencode dedup=on | tr -d '\n ' | cut -c1-260; echo;;
del) ts_api "$CIP" POST volumes/volumedel --data-urlencode "type=${1:?CIFS|HOME}" --data-urlencode "name=${2:?full volume name}" | tr -d '\n ' | cut -c1-200; echo;;
*) die "unknown command $C";;
esac
