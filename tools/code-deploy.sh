#!/bin/bash
# code-deploy.sh <BRANCH> [node...]   put the committed BRANCH of the three local clones onto the nodes (default: every running cluster
# node) without giving the nodes any credential: a git bundle per repo is copied with node-copy, fetched and checked out
# (checkout -f + reset --hard; uncommitted edits on a node are wiped anyway by the product's own setup). Then the commit on every
# node is compared with the clone and cluster-refreshcversion.sh re-publishes the version. Restart/settle the nodes afterwards
# so the running processes load the code; prove the fix live before you push.
. "$(dirname "$(readlink -f "$0")")/lib/git.sh"
. "$QC_TOOLS/lib/node.sh"
BR=${1:?branch}; shift; NS=${*:-$(cluster_nodes | while read -r n; do [ "$(node_state "$n")" = running ] && echo "$n"; done)}
W=$(mktemp -d "$QC_STATE/tmp/dep.XXXXXX"); trap 'rm -rf "$W"' EXIT; bad=0
for r in $REPOS; do g "$r" rev-parse -q --verify "refs/heads/$BR" >/dev/null || die "$r: no local branch $BR"
	[ -z "$(g "$r" status --porcelain)" ] || die "$r: commit first (only committed code is deployed)"
	g "$r" bundle create "$W/$r.bundle" "refs/heads/$BR" >/dev/null 2>&1 || die "$r: bundle failed"; done
for n in $NS; do for r in $REPOS; do p=$(cfg get "repos.node_paths.$r"); want=$(g "$r" rev-parse "refs/heads/$BR")
	node_copy "$n" "$W/$r.bundle" "/tmp/qc-$r.bundle" || { echo "$n $r: copy failed"; bad=1; continue; }
	node_exec "$n" "cd $p && git fetch -q -f /tmp/qc-$r.bundle +refs/heads/$BR:refs/qc/$BR && git checkout -q -f -B $BR refs/qc/$BR && git reset -q --hard refs/qc/$BR; rm -f /tmp/qc-$r.bundle" || { echo "$n $r: checkout failed"; bad=1; continue; }
	got=$(node_exec "$n" "cd $p && git rev-parse HEAD" 2>/dev/null | tr -d '\r\n')
	[ -n "$DRYRUN" ] || { [ "$got" = "$want" ] && echo "$n $r: $BR ${got:0:8} deployed" || { echo "$n $r: MISMATCH node=${got:0:8} clone=${want:0:8}"; bad=1; }; }
done; done
"$QC_TOOLS/cluster-refreshcversion.sh" $NS
exit $bad
