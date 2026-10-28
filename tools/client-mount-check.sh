#!/bin/bash
# client-mount-check.sh   For every node with role client: list its NFS/CIFS mounts and probe each with a 10 s stat.
# Exit 0 = none stale, 1 = at least one stale mount (clean it before the next test: umount -f -l it inside the client). Read-only.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
rc=0; for n in $(cfg nodes); do [ "$(cfgn "$n" role)" = client ] || continue
	[ -n "${DRYRUN:-}" ] && { log "DRYRUN: would check mounts on $n"; continue; }
	m=$(node_exec "$n" "grep -E ' (nfs|nfs4|cifs) ' /proc/mounts | awk '{print \$2}'" 2>/dev/null)
	[ -z "$m" ] && { echo "$n: no network mounts"; continue; }
	for d in $m; do if node_exec "$n" "timeout 10 stat -t '$d' >/dev/null 2>&1"; then echo "$n: $d ok"; else echo "$n: $d STALE"; rc=1; fi; done
done; exit $rc
