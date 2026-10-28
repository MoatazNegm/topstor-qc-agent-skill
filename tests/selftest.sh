#!/bin/bash
# tests/selftest.sh   offline self-test of the skill tools: config parsing/validation, preflight stop rules, node wrappers per type
# (DRYRUN, nothing is executed on any node), guards, loop state, masking, submit refusals, secret scan. Touches no cluster, no
# platform, no repo. Fake secret files are created at run time in a temp dir and deleted at the end.
set -u
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
loop:
  iteration_tests: [10, 11]
state_dir: $T/state
EOF
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
for t in host-kernelclean.sh host-stale-clean.sh cluster-build-repl.sh cluster-reset.sh cluster-join.sh ts-disk-add.sh; do
	rm -f "$T/shim/marker"; PATH="$T/shim:$PATH" DRYRUN=1 "$TL/$t" b9 1 > "$T/dry.out" 2>&1 < /dev/null
	[ ! -e "$T/shim/marker" ]; ck $? 0 "DRYRUN $t does not run a mutating host command"; done
"$TL/secret-scan.sh" "$ROOT" > "$T/s.out" 2>&1; ck $? 0 "secret scan of the skill repo is clean"
grep -q "$(cat "$T/key")" -r "$T/state" 2>/dev/null; ck $? 1 "fake key never written into the state dir"
echo "selftest: $pass passed, $fail failed"; [ $fail = 0 ]
