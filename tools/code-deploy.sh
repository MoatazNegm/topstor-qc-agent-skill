#!/bin/bash
# code-deploy.sh <BRANCH> [node...]        put the committed BRANCH of the three local clones onto the nodes.
# code-deploy.sh --check-branch <BRANCH> [cluster]   exit 0 when BRANCH exists in the NODE SOFTWARE REPO (what a reset/join/return pulls from);
#                                          rc 1 = branch missing, rc 2 = repo or node not reachable (checked from this machine by default).
#
# WHY TWO METHODS. The product's nodes pull their code from a software repo ("systempull" / "csystempull", container flavour: git:// on
# 9418). A reset, a join, a return and every setup run do "git reset --hard" to that repo's branch, so code that only sits on a node
# is WIPED by the next of those. The original QC harness therefore pushes the branch into that software repo with the product's own
# systempush ("SPD_ROOT=<tree> systempush.sh <BRANCH>").
#   deploy.method: product-push (default)  run deploy.push_command on deploy.push_node (a node, or "local" = this machine); the string
#                    {branch} is replaced. Example: "/TopStor/systempush.sh {branch}". Then each node is told to pull
#                    (deploy.pull_command, example "/TopStor/systempull.sh {branch}") and the commit is compared with the clone.
#   deploy.method: bundle                  no software repo: a git bundle per repo is copied to the node and checked out. QUICK TEST
#                    ONLY: the next reset/join/return/setup wipes it, so use it only on a running cluster that will not be reset.
# After either method cluster-refreshcversion.sh re-publishes the version; restart/settle the nodes so the running processes load the
# code, and prove the fix live before you push to your GitHub repos.
. "$(dirname "$(readlink -f "$0")")/lib/git.sh"
. "$QC_TOOLS/lib/node.sh"
if [ "${1:-}" = --check-branch ]; then BR=${2:?branch}; valid_branch "$BR" || die "bad branch name '$BR' (letters, digits, . _ / - only)"; CLC=${3:-1}; bad=0; unreach=0; any=0
	# rc 0 = branch present everywhere; rc 1 = branch MISSING in a reachable repo; rc 2 = repo/node NOT REACHABLE (nothing proven either way).
	# deploy.software_repo_check_from: local (default, run from this machine: works with every node stopped) | node (ask the running primary
	# of the cluster; use it only when the repo URL is reachable from the nodes alone).
	FROM=$(cfg get deploy.software_repo_check_from local)
	for r in $REPOS; do u=$(cfg get "deploy.software_repo.$r"); [ -n "$u" ] || continue; any=1
		if [ "$FROM" = node ]; then P=$(primary_of "$CLC")
			if [ -z "$P" ] || [ "$(node_state "$P")" != running ]; then echo "$r: node not reachable: primary of cluster $CLC is not running, cannot check $u (start it, or use software_repo_check_from: local)"; unreach=1; continue; fi
			o=$(node_exec "$P" "timeout 30 git ls-remote --heads $u refs/heads/$BR; echo RC=\$?" 2>/dev/null)
		else o=$(timeout 30 git ls-remote --heads "$u" "refs/heads/$BR" 2>/dev/null; echo "RC=$?"); fi
		echo "$o" | grep -q '^RC=0' || { echo "$r: node not reachable: git ls-remote of $u failed (network, URL or permission), branch $BR not checked"; unreach=1; continue; }
		echo "$o" | grep -q "refs/heads/$BR" || { echo "$r: branch $BR is MISSING in the node software repo $u"; bad=1; }; done
	[ $any = 1 ] || echo "WARN: deploy.software_repo.* not configured: cannot check that $BR is in the node software repo" >&2
	[ $bad = 1 ] && exit 1; [ $unreach = 1 ] && exit 2; exit 0; fi
BR=${1:?branch}; shift; valid_branch "$BR" || die "bad branch name '$BR' (letters, digits, . _ / - only)"; METHOD=$(cfg get deploy.method product-push)
if [ "$METHOD" = product-push ]; then
	PN=$(cfg get deploy.push_node local); PC=$(cfg get deploy.push_command); PL=$(cfg get deploy.pull_command)
	[ -n "$PC" ] || die "deploy.push_command is not set (see config/input.example.yaml); or set deploy.method: bundle for a quick test"
	PC=${PC//\{branch\}/$BR}; PL=${PL//\{branch\}/$BR}
	for r in $REPOS; do g "$r" rev-parse -q --verify "refs/heads/$BR" >/dev/null || die "$r: no local branch $BR"
		[ -z "$(g "$r" status --porcelain)" ] || die "$r: commit first (only committed code is deployed)"; done
	if [ "$PN" = local ]; then run bash -c "$PC" || die "push command failed"; else run node_exec "$PN" "$PC" || die "push command failed on $PN"; fi
	[ -n "${DRYRUN:-}" ] || "$QC_TOOLS/code-deploy.sh" --check-branch "$BR" || die "branch $BR did not arrive in the node software repo (or the repo is not reachable: see the message above)"
	NS=${*:-$(cluster_nodes | while read -r n; do [ "$(node_state "$n")" = running ] && echo "$n"; done)}
	bad=0; for n in $NS; do
		[ -z "$PL" ] || run node_exec "$n" "$PL" || { echo "$n: pull failed"; bad=1; continue; }
		for r in $REPOS; do p=$(cfg get "repos.node_paths.$r"); want=$(g "$r" rev-parse "refs/heads/$BR")
			got=$(node_exec "$n" "cd $p && git rev-parse HEAD" 2>/dev/null | tr -d '\r\n')
			[ -n "${DRYRUN:-}" ] || { [ "$got" = "$want" ] && echo "$n $r: $BR ${got:0:8} deployed" || { echo "$n $r: MISMATCH node=${got:0:8} clone=${want:0:8}"; bad=1; }; }; done; done
	run "$QC_TOOLS/cluster-refreshcversion.sh" $NS; exit $bad; fi
echo "WARN: deploy.method=bundle: a reset/join/return/setup on a node pulls from the software repo and WIPES this deployment" >&2
NS=${*:-$(cluster_nodes | while read -r n; do [ "$(node_state "$n")" = running ] && echo "$n"; done)}
W=$(mktemp -d "$QC_STATE/tmp/dep.XXXXXX"); trap 'rm -rf "$W"' EXIT; bad=0
for r in $REPOS; do g "$r" rev-parse -q --verify "refs/heads/$BR" >/dev/null || die "$r: no local branch $BR"
	[ -z "$(g "$r" status --porcelain)" ] || die "$r: commit first (only committed code is deployed)"
	g "$r" bundle create "$W/$r.bundle" "refs/heads/$BR" >/dev/null 2>&1 || die "$r: bundle failed"; done
for n in $NS; do for r in $REPOS; do p=$(cfg get "repos.node_paths.$r"); want=$(g "$r" rev-parse "refs/heads/$BR")
	node_copy "$n" "$W/$r.bundle" "/tmp/qc-$r.bundle" || { echo "$n $r: copy failed"; bad=1; continue; }
	node_exec "$n" "cd $p && git fetch -q -f /tmp/qc-$r.bundle +refs/heads/$BR:refs/qc/$BR && git checkout -q -f -B $BR refs/qc/$BR && git reset -q --hard refs/qc/$BR; rm -f /tmp/qc-$r.bundle" || { echo "$n $r: checkout failed"; bad=1; continue; }
	got=$(node_exec "$n" "cd $p && git rev-parse HEAD" 2>/dev/null | tr -d '\r\n')
	[ -n "${DRYRUN:-}" ] || { [ "$got" = "$want" ] && echo "$n $r: $BR ${got:0:8} deployed" || { echo "$n $r: MISMATCH node=${got:0:8} clone=${want:0:8}"; bad=1; }; }
done; done
"$QC_TOOLS/cluster-refreshcversion.sh" $NS
exit $bad
