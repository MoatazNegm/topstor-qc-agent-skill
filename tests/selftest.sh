#!/bin/bash
# tests/selftest.sh   offline self-test of the skill tools: config parsing/validation, preflight stop rules, node wrappers per type
# (DRYRUN, nothing is executed on any node), guards, loop state, masking, submit refusals, secret scan. Touches no cluster, no
# platform, no repo. Fake secret files are created at run time in a temp dir and deleted at the end.
set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd); T=$(mktemp -d); [ -n "${KEEP:-}" ] && echo "keeping $T" || trap 'rm -rf "$T"' EXIT
pass=0; fail=0; ck() { if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "ok   $3"; else fail=$((fail+1)); echo "FAIL $3 (got '$1', want '$2')"; fi; }
for f in key pw cred sshkey; do head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$T/$f"; chmod 600 "$T/$f"; done
mkdir -p "$T/clone/topstor/.git"
cat > "$T/input.yaml" <<EOF
platform:
  url: https://qc.example.invalid/api
  app_id: "7"
  tester_key_file: $T/key
cluster:
  flavour: container
  cluster_ip: 10.0.0.200
  first_boot_ip: 10.0.0.250
  discovery_ip: 10.0.0.253
  admin_password_file: $T/pw
  settle_seconds: 1
nodes:
  - name: n1
    type: container
    container: selftest-ctr-a
    host: 10.0.0.201
    alias: a1
    role: primary
    cluster: 1
  - name: n2
    type: physical
    host: 10.0.0.77
    alias: a2
    ssh_user: root
    ssh_key_file: $T/sshkey
    role: member
  - name: n3
    type: virtualbox
    vbox_name: "TopStor node3"
    host: 10.0.0.78
    alias: a3
    ssh_user: root
    role: member
  - name: c1
    type: container
    container: selftest-ctr-c
    role: client
repos:
  credential_file: $T/cred
  user_owner: someone
  branch_prefix: QSD5.
  topstor: {url: https://example.invalid/a.git, clone: $T/clone/topstor}
  pace:
    url: https://example.invalid/b.git
    clone: $T/clone/pace
  topstorweb:
    url: https://example.invalid/c.git
    clone: $T/clone/topstorweb
  upstream:
    topstor: up/a
    pace: up/b
    topstorweb: up/c
    base_branch: main
  node_paths:
    topstor: /TopStor
    pace: /pace
    topstorweb: /topstorweb
container_host:
  test_disk_regex: '^$T/disks/'
  stale_loop_regex: '^$T/disks/.*\.img$'
deploy:
  method: product-push
  push_command: 'true {branch}'
  software_repo_check_from: local
  software_repo:
    topstor: $T/bare.git
loop:
  iteration_tests: [10, 11]
state_dir: $T/state
EOF
git init -q --bare "$T/bare.git"; git init -q "$T/seed" && git -C "$T/seed" -c user.email=a@b -c user.name=t commit -q --allow-empty -m x && git -C "$T/seed" push -q "$T/bare.git" HEAD:refs/heads/QSD5.1 2>/dev/null
export QC_CONFIG=$T/input.yaml QC_ALLOW_MIXED_TYPES=1
TL=$ROOT/tools
python3 -I "$TL/lib/cfg.py" validate > "$T/v.out" 2>&1; ck $? 0 "complete config validates"
QC_ALLOW_MIXED_TYPES= python3 -I "$TL/lib/cfg.py" validate 2>&1 | grep -q 'does not fit flavour'; ck $? 0 "flavour/type mismatch is an error"
sed 's#^  cluster_ip: .*#  cluster_ip: CHANGE_ME#; s#^  first_boot_ip: .*#  first_boot_ip: CHANGE_ME#' "$T/input.yaml" > "$T/nofb.yaml"
QC_CONFIG=$T/nofb.yaml python3 -I "$TL/lib/cfg.py" validate 2>&1 | grep -q 'first_boot_ip'; ck $? 0 "cluster and first-boot address must be given by the user"
ck "$(python3 -I "$TL/lib/cfg.py" get loop.iteration_tests)" "10 11" "inline list parsed"
ck "$(python3 -I "$TL/lib/cfg.py" node n3 vbox_name)" "TopStor node3" "quoted scalar parsed"
ck "$(python3 -I "$TL/lib/cfg.py" get repos.topstor.url)" "https://example.invalid/a.git" "inline map parsed"
ck "$(python3 -I "$TL/lib/cfg.py" nodes --role member | tr '\n' ' ')" "n2 n3 " "nodes filter"
sed 's#admin_password_file: .*#admin_password: hunter22#' "$T/input.yaml" > "$T/bad.yaml"
QC_CONFIG=$T/bad.yaml python3 -I "$TL/lib/cfg.py" validate > "$T/b.out" 2>&1; ck $? 2 "inline secret refused"
grep -q 'inline secret value is not allowed' "$T/b.out"; ck $? 0 "inline secret message"
sed 's#user_owner: someone#user_owner: CHANGE_ME#' "$T/input.yaml" > "$T/ph.yaml"
QC_CONFIG=$T/ph.yaml "$TL/preflight.sh" --offline > "$T/p.out" 2>&1; ck $? 2 "placeholder -> preflight STOP rc 2"
QC_CONFIG=$T/missing.yaml "$TL/preflight.sh" > "$T/m.out" 2>&1; ck $? 2 "missing config -> preflight STOP rc 2"
o=$(DRYRUN=1 "$TL/node-exec" n1 'zpool list' 2>&1); ck "$o" "DRYRUN: docker exec selftest-ctr-a sh -c zpool list" "container node-exec"
o=$(DRYRUN=1 "$TL/node-exec" n2 'uptime' 2>&1); case "$o" in *"ssh -o BatchMode=yes"*"-i $T/sshkey"*"-T root@10.0.0.77 uptime") r=ok;; *) r="$o";; esac; ck "$r" ok "physical node-exec through ssh"
o=$(DRYRUN=1 "$TL/node-start" n3 2>&1); case "$o" in *"VBoxManage startvm TopStor node3 --type headless"*|*"VBoxManage showvminfo"*) r=ok;; *) r="$o";; esac; ck "$r" ok "virtualbox node-start"
"$TL/node-stop" n1 > /dev/null 2>&1; ck $? 5 "unguarded stop of a cluster node refused"
QC_GUARDED=1 "$TL/node-stop" n1 --hard > /dev/null 2>&1; ck $? 5 "hard stop of a container node refused"
o=$(DRYRUN=1 "$TL/node-stop" c1 2>&1); ck "$o" "DRYRUN: docker stop -t 120 selftest-ctr-c" "client stop allowed"
"$TL/repl-iscsi-cross.sh" > /dev/null 2>&1; ck $? 1 "repl-iscsi-cross needs explicit nodes"
LS="$TL/loop-state.sh"; $LS set-tests 10 11 >/dev/null; $LS test-done 10 pass >/dev/null
$LS code-change QSD5.2 "fix" >/dev/null; $LS test-done 11 pass >/dev/null
$LS is-clean >/dev/null; ck $? 1 "not clean: a code change mid-iteration needs a whole new iteration"
$LS test-done 10 pass >/dev/null; $LS is-clean >/dev/null; ck $? 0 "clean after one full iteration from the first test with no change"
$LS code-change QSD5.3 "fix 2" >/dev/null; $LS is-clean >/dev/null; ck $? 1 "a code change voids an earlier clean iteration"
$LS test-done 10 fail >/dev/null; $LS test-done 10 pass >/dev/null; $LS test-done 11 pass >/dev/null; $LS is-clean >/dev/null; ck $? 1 "not clean: test failed without code change, later passed"
$LS test-done 10 pass >/dev/null; $LS test-done 11 pass >/dev/null; $LS is-clean >/dev/null; ck $? 0 "clean again after the next full clean iteration"
"$TL/git-pr.sh" X > /dev/null 2>&1 <<< "" ; true
FAKEPW=s3cret$RANDOM; FAKEKEY=qc_$(printf 'Z%.0s' $(seq 1 20)); FAKEHEX=$(printf '0f%.0s' $(seq 1 20))
o=$(echo "login?user=admin&pass=$FAKEPW&token=abcd x $FAKEKEY $FAKEHEX" | (. "$TL/lib/common.sh"; mask))
ck "$o" "login?user=admin&pass=-&token=- x qc_- -" "mask output is exactly the masked text (under set -u)"
mkdir -p "$T/state/rounds/b10i1"; echo x > "$T/c"
"$TL/qc-submit.sh" b10i1 10 1 fail "$T/c" --config > /dev/null 2>&1; ck $? 4 "FAIL without validator verdict held"
"$TL/qc-submit.sh" b10i1 10 1 fail "$T/c" > /dev/null 2>&1; ck $? 4 "FAIL without config refused"
echo "10:5" > "$T/state/ledger/b10i1.sent"; "$TL/qc-submit.sh" b10i1 10 5 pass "$T/c" > /dev/null 2>&1; ck $? 3 "second submission of a step refused (ledger)"
# DRYRUN must not touch the host: shims record any call of a mutating command
mkdir -p "$T/shim"; printf '#!/bin/sh\n[ "$1" = list ] || echo "zpool $*" >> "%s/marker"\nexit 0\n' "$T/shim" > "$T/shim/zpool"; chmod +x "$T/shim/zpool"
for c in dd wipefs losetup curl targetcli iscsiadm partx mknod truncate; do printf '#!/bin/sh\necho "$0 $*" >> "%s/marker"\nexit 0\n' "$T/shim" > "$T/shim/$c"; chmod +x "$T/shim/$c"; done
# losetup READS are answered by the shim with one fake test loop (so the tools get past "no loops"); only mutations are recorded
printf '#!/bin/sh\ncase "$1" in -l|-nO|-n) echo "/dev/loop99 %s/disks/x.img"; exit 0;; esac\necho "$0 $*" >> "%s/marker"\nexit 0\n' "$T" "$T/shim" > "$T/shim/losetup"; chmod +x "$T/shim/losetup"
# G-06: DRYRUN checks that really reach the DRYRUN branch (own container-only config with two clusters; the container names do not exist)
mkdir -p "$T/disks" "$T/lf"; : > "$T/lf/a"
sed -n '1,/^nodes:/p' "$T/input.yaml" | sed '$d' | sed "s#^  settle_seconds: 1#  settle_seconds: 1\n  second_cluster_ip: 10.0.0.210\n  second_admin_password_file: $T/pw#" > "$T/dry.yaml"
cat >> "$T/dry.yaml" <<EOF
nodes:
  - {name: d1, type: container, container: selftest-ctr-d1, host: 10.0.0.211, alias: d1, role: primary, cluster: 1}
  - {name: d2, type: container, container: selftest-ctr-d2, host: 10.0.0.212, alias: d2, role: member, cluster: 1}
  - {name: e1, type: container, container: selftest-ctr-e1, host: 10.0.0.221, alias: e1, role: primary, cluster: 2}
$(sed -n '/^repos:/,$p' "$T/input.yaml" | sed '/^container_host:/,/^deploy:/{/^deploy:/!d}' | sed '/^state_dir:/d')
container_host:
  test_disk_regex: '^$T/disks/'
  stale_loop_regex: '^$T/disks/.*\.img$'
  disk_dir: $T/disks
  loopdisks_files: [$T/lf/a]
state_dir: $T/state
EOF
QC_CONFIG=$T/dry.yaml python3 -I "$TL/lib/cfg.py" validate > "$T/dv.out" 2>&1; ck $? 0 "DRYRUN config validates ($(tail -n1 "$T/dv.out" | cut -c1-80))"
for c in "host-kernelclean.sh" "host-stale-clean.sh" "cluster-build-repl.sh b9" "cluster-reset.sh b9" "cluster-join.sh d2" "ts-disk-add.sh 1"; do
	rm -f "$T/shim/marker"; QC_CONFIG=$T/dry.yaml PATH="$T/shim:$PATH" DRYRUN=1 "$TL/${c%% *}" ${c#"${c%% *}"} > "$T/dry2.out" 2>&1 < /dev/null
	grep -q 'DRYRUN' "$T/dry2.out"; ck $? 0 "DRYRUN ${c%% *} reaches its DRYRUN branch ($(grep -m1 DRYRUN "$T/dry2.out" | cut -c1-60))"
	[ ! -e "$T/shim/marker" ]; ck $? 0 "DRYRUN ${c%% *} ran no mutating command"; done
# G-01: the branch check runs from this machine, with every node stopped; missing vs not reachable are told apart
"$TL/code-deploy.sh" --check-branch QSD5.1 > "$T/cb.out" 2>&1; ck $? 0 "check-branch: branch present, nodes stopped"
"$TL/code-deploy.sh" --check-branch QSD5.404 > "$T/cb.out" 2>&1; ck "$?$(grep -c MISSING "$T/cb.out")" 11 "check-branch: missing branch -> rc 1 MISSING"
sed "s#$T/bare.git#$T/nonexistent.git#" "$T/input.yaml" > "$T/unr.yaml"; QC_CONFIG=$T/unr.yaml "$TL/code-deploy.sh" --check-branch QSD5.1 > "$T/cb.out" 2>&1; ck "$?$(grep -c 'not reachable' "$T/cb.out")" 21 "check-branch: repo not reachable -> rc 2, not 'missing'"
# G-03: the last test of an iteration fails, then a code change: the iteration number advances once
rm -f "$T"/state/loop*.json 2>/dev/null; LS="$TL/loop-state.sh"
$LS set-tests 10 11 >/dev/null; $LS test-done 10 pass >/dev/null; $LS test-done 11 fail >/dev/null; $LS code-change QSD5.9 x >/dev/null; $LS show | grep -q '^iteration 2:'; ck $? 0 "code-change after a closed iteration does not skip an iteration number"
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" 1 --wait 5m >/dev/null 2>"$T/w.err"; ck "$?$(grep -c "whole number" "$T/w.err")" 11 "ts-disk-add --wait with a non-number is refused (rc 1)"
for bad in "x" "1.5" "0" "-1"; do QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" $bad >/dev/null 2>"$T/w.err"; ck "$?$(grep -c "whole number\|at least" "$T/w.err")" 11 "ts-disk-add count '$bad' is refused (rc 1)"; done
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" 1 2.5G >/dev/null 2>"$T/w.err"; ck "$?$(grep -c "whole number" "$T/w.err")" 11 "ts-disk-add size '2.5G' is refused (rc 1)"
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" 1 --wait >/dev/null 2>"$T/w.err"; ck "$?$(grep -c "got nothing" "$T/w.err")" 11 "ts-disk-add trailing --wait without a value is refused (rc 1)"
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" 1 >/dev/null 2>&1; ck $? 0 "ts-disk-add valid dry run still passes"
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" 08 09 >/dev/null 2>&1; ck $? 0 "ts-disk-add count 08 size 09 (leading zeros) is accepted as decimal"
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" 1 1 --wait 08 >/dev/null 2>&1; ck $? 0 "ts-disk-add --wait 08 (leading zero) is accepted as decimal"
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/ts-disk-add.sh" 1 1 2 >/dev/null 2>"$T/w.err"; ck "$?$(grep -c "too many" "$T/w.err")" 11 "ts-disk-add extra positional argument is refused (rc 1)"
# FEEDBACK-6 cases. A docker shim answers for the container nodes d1/d2 (no real docker, nothing runs anywhere).
mkdir -p "$T/dshim"; cat > "$T/dshim/docker" <<'SH'
#!/bin/sh
case "$1" in
inspect) echo running; exit 0;;
exec) shift; shift; cmd="$*"
	case "$cmd" in
	*"pgrep -x iscsid"*) [ "$2" = "x" ] ; exit 0;;
	*initiatorname*) echo "InitiatorName=iqn.test:ini"; exit 0;;
	hostname*|*"sh -c hostname"*) echo hostn; exit 0;;
	*cpoolowner*) exit 0;;
	*"iscsiadm -m session"*) [ -n "$FAKE_SESSION" ] && echo "tcp: [1] 10.0.0.212:3266,1 iqn.2016-03.com.hostn:t1 (non-flash)"; exit 0;;
	*"zpool list"*) [ -n "$FAKE_ZFAIL" ] && exit 124; [ -n "$FAKE_POOL" ] && echo "$FAKE_POOL"; exit 0;;
	*) echo "$cmd" >> "$FAKE_LOG"; exit 0;;
	esac;;
esac
exit 0
SH
chmod +x "$T/dshim/docker"
# K-01: session to the target + imported pool = refused (rc 5), nothing logged out; no session = login-only path allowed; session but no pool = allowed
FAKE_LOG=$T/k01.log; : > "$FAKE_LOG"; export FAKE_LOG
QC_CONFIG=$T/dry.yaml PATH="$T/dshim:$PATH" OWN=d1 FAKE_SESSION=1 FAKE_POOL=tank "$TL/repl-iscsi-cross.sh" d2 > "$T/k01.out" 2>&1; ck "$?$(grep -c 'REFUSED' "$T/k01.out")$(grep -c 'iscsiadm -m node' "$FAKE_LOG")" 510 "K-01 repl-iscsi-cross refuses a logout while a pool is imported and the holder has a session"
: > "$FAKE_LOG"; QC_CONFIG=$T/dry.yaml PATH="$T/dshim:$PATH" OWN=d1 FAKE_POOL=tank "$TL/repl-iscsi-cross.sh" d2 > "$T/k01.out" 2>&1; ck "$?$(grep -c 'iscsiadm -m node.* -u' "$FAKE_LOG")" 01 "K-01 no session to the target yet: login-only path allowed with a pool imported (logout is a no-op there)"
: > "$FAKE_LOG"; QC_CONFIG=$T/dry.yaml PATH="$T/dshim:$PATH" OWN=d1 FAKE_SESSION=1 "$TL/repl-iscsi-cross.sh" d2 > "$T/k01.out" 2>&1; ck $? 0 "K-01 session but no pool imported: allowed"
# L-01/L-02: ts-disk-remove sources its lib, refuses while a pool is imported (rc 5), reports a hung zpool (rc 3), passes on an idle lab
QC_CONFIG=$T/dry.yaml PATH="$T/dshim:$PATH" DRYRUN=1 "$TL/ts-disk-remove.sh" loop99 > "$T/l01.out" 2>&1; ck "$?$(grep -c 'command not found' "$T/l01.out")" 00 "L-01 ts-disk-remove idle lab passes (no missing function)"
QC_CONFIG=$T/dry.yaml PATH="$T/dshim:$PATH" FAKE_POOL=tank "$TL/ts-disk-remove.sh" loop99 > "$T/l01.out" 2>&1; ck "$?$(grep -c 'REFUSED' "$T/l01.out")" 51 "L-02 ts-disk-remove refused while a pool is imported"
QC_CONFIG=$T/dry.yaml PATH="$T/dshim:$PATH" FAKE_ZFAIL=1 "$TL/ts-disk-remove.sh" loop99 > "$T/l01.out" 2>&1; ck "$?$(grep -c 'does not answer' "$T/l01.out")" 31 "L-01 ts-disk-remove reports a hung zpool (rc 3)"
# L-04: iscsi-stale-clean refuses when a configured node is not running (no alias fallback)
QC_CONFIG=$T/dry.yaml "$TL/iscsi-stale-clean.sh" > "$T/l04.out" 2>&1; ck "$(grep -c 'cannot read the host name' "$T/l04.out")" 1 "L-04 iscsi-stale-clean refuses without a readable node name"
# K-13: branch names with shell metacharacters are refused before anything runs
for bad in 'x;touch /tmp/pwn' 'a b' '$(id)' '-x'; do QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/code-deploy.sh" "$bad" > "$T/k13.out" 2>&1; ck "$?$(grep -c 'bad branch name' "$T/k13.out")" 11 "K-13 code-deploy refuses branch '$bad'"; done
QC_CONFIG=$T/dry.yaml "$TL/git-newbranch.sh" 'x;id' > "$T/k13.out" 2>&1; ck "$?$(grep -c 'bad branch name' "$T/k13.out")" 11 "K-13 git-newbranch refuses a bad branch name"
QC_CONFIG=$T/dry.yaml "$TL/git-pushbranch.sh" 'x y' > "$T/k13.out" 2>&1; ck "$?$(grep -c 'bad branch name' "$T/k13.out")" 11 "K-13 git-pushbranch refuses a bad branch name"
# K-05: settle seconds validated; unknown options refused; config validate rejects a non-integer
QC_CONFIG=$T/dry.yaml "$TL/cluster-settle.sh" d1 --settle abc > "$T/k05.out" 2>&1; ck "$?$(grep -c 'whole number' "$T/k05.out")" 11 "K-05 cluster-settle --settle abc refused"
QC_CONFIG=$T/dry.yaml "$TL/cluster-settle.sh" d1 --settle > "$T/k05.out" 2>&1; ck "$?$(grep -c 'whole number' "$T/k05.out")" 11 "K-05 cluster-settle --settle without a value refused"
QC_CONFIG=$T/dry.yaml "$TL/cluster-settle.sh" d1 --aftre-start > "$T/k05.out" 2>&1; ck "$?$(grep -c 'unknown option' "$T/k05.out")" 11 "K-05 cluster-settle unknown option refused"
sed 's#settle_seconds: 1#settle_seconds: 5m#' "$T/input.yaml" > "$T/ss.yaml"; QC_CONFIG=$T/ss.yaml python3 -I "$TL/lib/cfg.py" validate 2>&1 | grep -q 'settle_seconds: must be a whole number'; ck $? 0 "K-05 config validate rejects settle_seconds 5m"
# K-10 / K-04: unknown options on the build and stop tools are refused
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/cluster-reset.sh" b9 --no-disk > "$T/k10.out" 2>&1; ck "$?$(grep -c 'unknown option' "$T/k10.out")" 11 "K-10 cluster-reset --no-disk (typo) refused"
QC_CONFIG=$T/dry.yaml DRYRUN=1 "$TL/cluster-build-repl.sh" b9 --sngle > "$T/k10.out" 2>&1; ck "$?$(grep -c 'unknown option' "$T/k10.out")" 11 "K-10 cluster-build-repl typo option refused"
QC_CONFIG=$T/dry.yaml PATH="$T/dshim:$PATH" "$TL/cluster-stopnode.sh" d1 --hrad > "$T/k10.out" 2>&1; ck "$?$(grep -c 'unknown option' "$T/k10.out")" 11 "K-10 cluster-stopnode --hrad (typo) refused"
# K-04: a build whose status did not end is not wiped; a held lock refuses a second build
mkdir -p "$T/state/builds/build77"; echo "10:00:00 resetting node" > "$T/state/builds/build77/status"
QC_CONFIG=$T/dry.yaml "$TL/cluster-reset.sh" 77 > "$T/k04.out" 2>&1; ck "$?$(grep -c 'did not end' "$T/k04.out")" 51 "K-04 unfinished build status is not wiped"
[ "$(cat "$T/state/builds/build77/status")" = "10:00:00 resetting node" ]; ck $? 0 "K-04 status file untouched after the refusal"
( exec 8>"$T/state/builds/.lock"; flock -n 8; QC_CONFIG=$T/dry.yaml "$TL/cluster-reset.sh" 78 > "$T/k04b.out" 2>&1; echo "$?$(grep -c 'another build is running' "$T/k04b.out")" > "$T/k04b.rc" ); ck "$(cat "$T/k04b.rc")" 51 "K-04 a held build lock refuses a second build"
# K-02/K-03/K-10 offline: a local fake platform (python http.server) answers the platform calls
mkdir -p "$T/plat"; cat > "$T/plat/srv.py" <<'PY'
import json,sys
from http.server import BaseHTTPRequestHandler,HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def _s(self,c,b,ct="application/json"):
        self.send_response(c); self.send_header("Content-Type",ct); self.end_headers(); self.wfile.write(b.encode())
    def do_GET(self):
        p=self.path
        if p.startswith("/api/tests/active"): self._s(200,"{}")
        elif p.startswith("/api/test-results/summary"): self._s(200,'{"monthEarned":0}')
        elif p.startswith("/api/test-results/history"): self._s(200,"[]")
        elif p.startswith("/api/test-results/5/next"): self._s(200,'{"step":{"id":99,"step_number":3},"test_id":5,"test_name":"x"}')
        elif p.startswith("/api/test-results/8/next"): self._s(404,'{"error":"No more steps","allDone":true}')
        elif p.startswith("/api/test-results/9/next"): self._s(200,'{"step":{"id":7,"step_number":1},"test_id":9,"test_name":"x"}')
        elif p.startswith("/api/tests/6"): self._s(200,'{"error":"not found"}')
        else: self._s(404,"{}")
    def do_POST(self):
        n=int(self.headers.get("Content-Length") or 0); self.rfile.read(n)
        if "/complete" in self.path: self._s(500,'{"error":"boom"}')
        elif "/test-results/9/steps/7" in self.path: self._s(200,'{"message":"Result submitted successfully","pointsAwarded":0}')
        else: self._s(200,"{}")
HTTPServer(("127.0.0.1",int(sys.argv[1])),H).serve_forever()
PY
PORT=$((20000+RANDOM%20000)); python3 -I "$T/plat/srv.py" $PORT & SRV=$!; sleep 1
sed "s#https://qc.example.invalid/api#http://127.0.0.1:$PORT/api#" "$T/input.yaml" > "$T/plat.yaml"
mkdir -p "$T/state/rounds/b5i1"; date -u +%Y-%m-%dT%H:%M:%S > "$T/state/rounds/b5i1/startts"; echo c > "$T/pc"
QC_CONFIG=$T/plat.yaml "$TL/qc-submit.sh" b5i1 5 7 pass "$T/pc" > "$T/k02.out" 2>&1; ck "$?$(grep -c 'next step of test 5 is 99' "$T/state/rounds/b5i1/run.log" 2>/dev/null)" 31 "K-02 submit refused when the platform's next step is another step (nothing sent)"
# L-03: allDone reply = nothing sent, rc 3
QC_CONFIG=$T/plat.yaml "$TL/qc-submit.sh" b5i1 8 1 pass "$T/pc" > "$T/l03.out" 2>&1; ck "$?$(grep -c 'allDone' "$T/state/rounds/b5i1/run.log" 2>/dev/null)" 31 "L-03 submit refused when the platform says allDone (rc 3)"
# L-06: a 200 success reply with "message" but no "result" is not called a rejection (falls to the history check, here UNKNOWN rc 2)
QC_CONFIG=$T/plat.yaml "$TL/qc-submit.sh" b5i1 9 7 pass "$T/pc" > "$T/l06.out" 2>&1; ck "$?$(grep -c 'rejected' "$T/l06.out")" 20 "L-06 200 reply with message and no result is not read as a rejection"
QC_CONFIG=$T/plat.yaml "$TL/qc-dltest.sh" 6 > "$T/k10.out" 2>&1; ck $? 1 "K-10 qc-dltest refuses a reply without steps"
[ ! -e "$T/state/tests/test6.json" ]; ck $? 0 "K-10 qc-dltest keeps no file for a reply without steps"
QC_CONFIG=$T/plat.yaml "$TL/qc-complete.sh" b5i1 5 complete > "$T/k10.out" 2>&1; ck "$?$(grep -q 'http 500' "$T/k10.out" && echo 1)" 11 "K-10 qc-complete exits non-zero on an HTTP 500"
# integrity layer: manifest verifies, a modified file is flagged, the stamp format is right
"$TL/verify-manifest.sh" --status > "$T/vm.out" 2>&1; ck "$(cat "$T/vm.out")" OK "manifest matches the tree (run verify-manifest.sh --update after a reviewed change)"
mkdir -p "$T/skillcopy"; (cd "$ROOT" && tar cf - --exclude=.git --exclude=state --exclude=config/input.yaml .) | tar xf - -C "$T/skillcopy"; echo x >> "$T/skillcopy/docs/pitfalls.md"
o=$("$T/skillcopy/tools/verify-manifest.sh" --status); ck "$o" MODIFIED "a changed listed file gives MODIFIED (tested on a copy of the tree, not the real docs)"
QC_CONFIG=$T/input.yaml "$T/skillcopy/tools/qc-submit.sh" b10i1 10 6 pass "$T/c" > "$T/mod.out" 2>&1; rc=$?; ck "$rc$(tail -n1 "$T/state/rounds/b10i1/run.log" | grep -c "STOPPED-SUBMIT.*MODIFIED")" 91 "MODIFIED tree: qc-submit stops with rc 9 (STOPPED-SUBMIT line) without QC_ACK_MODIFIED"
QC_ACK_MODIFIED=1 DRYRUN=1 QC_CONFIG=$T/input.yaml "$T/skillcopy/tools/qc-submit.sh" b10i1 10 6 pass "$T/c" > "$T/mod.out" 2>&1; ck $? 0 "MODIFIED tree with QC_ACK_MODIFIED=1: dry run passes"
grep -qE '\[skill v[0-9.]+ manifest [0-9a-f]{12} MODIFIED\]' "$T/mod.out"; ck $? 0 "stamp in the comment reads MODIFIED"
QC_ACK_MODIFIED=1 DRYRUN=1 QC_CONFIG=$T/input.yaml "$TL/qc-submit.sh" b10i1 10 6 pass "$T/c" > "$T/dry-stamp.out" 2>&1; grep -qE '\[skill v[0-9.]+ manifest [0-9a-f]{12} (OK|MODIFIED)\]' "$T/dry-stamp.out"; ck $? 0 "DRYRUN qc-submit comment carries the stamp [skill vX manifest <12 hex> OK|MODIFIED]"
grep -qE 'STEPCHECK.*skill v\$SV manifest|STEPCHECK.*\$STAMP' "$TL/qc-submit.sh"; ck $? 0 "STEPCHECK line carries the stamp"
QCHECK_DRY=1 QC_CONFIG=$T/input.yaml "$TL/qcheck.sh" > "$T/qch.out" 2>&1; ck "$?$(grep -c '^QCHECK' "$T/qch.out")" 01 "qcheck dry run prints one summary line, rc 0"
QC_CONFIG=$T/nonexistent.yaml "$TL/qcheck.sh" > "$T/qch.out" 2>&1; ck "$?$(grep -c 'config missing' "$T/qch.out")" 21 "qcheck without config prints once and exits 2"
grep -q QC_MAINTAINER "$TL/git-pr.sh"; ck $? 1 "git-pr.sh has no pull-request-opening path (no QC_MAINTAINER)"
printf '#!/bin/sh\nexit 0\n' > "$T/skillcopy/tools/verify-manifest.sh"; chmod +x "$T/skillcopy/tools/verify-manifest.sh"
QC_CONFIG=$T/input.yaml "$T/skillcopy/tools/qc-submit.sh" b10i1 10 6 pass "$T/c" > "$T/mod.out" 2>&1; rc=$?; ck "$rc$(tail -n1 "$T/state/rounds/b10i1/run.log" | grep -c "STOPPED-SUBMIT")" 91 "empty manifest status counts as not OK: qc-submit stops with rc 9"
grep -rlE 'api\.github\.com' "$ROOT/tools" 2>/dev/null | grep -q .; ck $? 1 "no tool talks to api.github.com (no write-capable GitHub API call)"
(cd "$ROOT" && git ls-files 2>/dev/null | grep -v 'FIXLOG' | grep -v '^tests/selftest.sh$' | xargs grep -liE 'server.side|must enforce' 2>/dev/null) | grep -q .; ck $? 1 "no tracked file claims server-side enforcement"
QC_ACK_MODIFIED=1 DRYRUN=1 QC_CONFIG=$T/input.yaml "$T/skillcopy/tools/qc-submit.sh" b10i1 10 6 pass "$T/c" > "$T/emp.out" 2>&1; grep -qE ' MODIFIED\]' "$T/emp.out"; ck $? 0 "ACK with empty status stamps MODIFIED"
grep -qE 'manifest (none|[0-9a-f]{12}) MODIFIED\]' "$T/emp.out"; ck $? 0 "ACK with empty status and empty hash stamps manifest none (W-03)"
for r in tester coder validator; do grep -q 'SKILL.md. section 0A' "$ROOT/docs/roles/$r.md"; ck $? 0 "role $r inputs name SKILL.md section 0A (W-01)"; done
grep -q 'section 0A' "$ROOT/docs/roles/supervisor.md"; ck $? 0 "supervisor prompt template names SKILL.md section 0A (W-01)"
printf '%s' "$("$TL/verify-manifest.sh" --hash)" | grep -qE '^[0-9a-f]{64}$'; ck $? 0 "manifest hash is 64 hex"
kill $SRV 2>/dev/null; wait $SRV 2>/dev/null
# H-01: the selftest leaves the tree clean (no bytecode written)
[ -z "$(find "$ROOT" -name __pycache__ -not -path "*/.git/*")" ]; ck $? 0 "no __pycache__ written into the skill tree"
"$TL/secret-scan.sh" "$ROOT" > "$T/s.out" 2>&1; ck $? 0 "secret scan of the skill repo is clean"
grep -q "$(cat "$T/key")" -r "$T/state" 2>/dev/null; ck $? 1 "fake key never written into the state dir"
echo "selftest: $pass passed, $fail failed"; [ $fail = 0 ]
