# Tools

Every tool reads `config/input.yaml` (or `$QC_CONFIG`) and writes only under `state/`. Each starts with a usage header (`sed -n 2,4p <tool>`). `DRYRUN=1` prints node, git, platform-writing, host clean-up, cluster build and product-API write commands instead of running them (read calls still run).

| Tool | Usage (first header line) | Adapted from (TopStor dev harness) |
|---|---|---|
| `preflight.sh` | preflight.sh [--offline]   FIRST command of every agent. Checks config/input.yaml exists and is complete (cfg.py validate), that | new |
| `node-exec` | node-exec <node> <shell command...>   run a command on a node of any type (docker exec / ssh), no TTY; NODE_STDIN=1 passes stdin through. DRYRUN=1 pri | new |
| `node-copy` | node-copy <node> <local path> <path on node>   copy a file to a node (docker cp / scp); --from <node> <path on node> <local path> copies back. | new |
| `node-start` | node-start <node> [--wait [timeout s]]   power on / start a node (docker start, VBoxManage startvm, start_command); rc 10 = NEEDS-HUMAN (power it on b | new |
| `node-stop` | node-stop <node> [--hard]   LOW LEVEL stop (docker stop -t 120 / poweroff / ACPI). Cluster nodes are refused unless called by cluster-stopnode.sh (QC_ | new |
| `node-reboot` | node-reboot <node> [--hard]   reboot a node (docker restart / systemctl reboot / VBox reset with --hard); guarded like node-stop; waits until it answe | new |
| `node-status` | node-status [node...]   one line per node: name type state boot-id (all nodes of the config when none is given). | new |
| `cluster-settle.sh` | cluster-settle.sh <node> [--after-start] [--settle S] [--no-sync]   wait until the node's own setup (docker_setup.sh) has finished, then a REAL | lib.sh `settle` + the 300 s settle/isinsync rule |
| `cluster-insync.sh` | cluster-insync.sh [cluster ip] [max seconds]   poll info/notification until isinsync is green (the UI's "Cluster in Sync" sign); | insync.sh |
| `cluster-stopnode.sh` | cluster-stopnode.sh <node> [--keep-running] [--hard] [--export]   the ONLY way to stop a TopStor cluster node (adapted stopnode.sh). | stopnode.sh |
| `cluster-return.sh` | cluster-return.sh <returning node> <leading node> [tag]   a stopped node comes back while the other node leads (adapted return.sh): | return.sh |
| `cluster-reset.sh` | cluster-reset.sh <build> [--cluster N] [--single] [--no-disks]   a fresh cluster from the EXISTING nodes (adapted resetcluster.sh): | resetcluster.sh |
| `cluster-join.sh` | cluster-join.sh <member node> [alias]   join a freshly reset node to its cluster with ONE call (hosts/joincluster: name, alias, node ip), | join.sh |
| `cluster-refreshcversion.sh` | cluster-refreshcversion.sh [node...]   re-publish cversion/<host> from the code really checked out on each node (the product's | refreshcversion.sh |
| `host-kernelclean.sh` | host-kernelclean.sh   CONTAINER FLAVOUR ONLY, run on the docker host that runs the node containers (adapted kernelclean.sh). | kernelclean.sh |
| `host-stale-clean.sh` | host-stale-clean.sh   CONTAINER FLAVOUR ONLY, on the docker host at the START of a build, after every node was stopped with | stalelooppclean.sh |
| `iscsi-stale-clean.sh` | iscsi-stale-clean.sh [node...]   delete iSCSI node records (and, container flavour, LUN-less LIO targets) of targets that are not a | cleaniscsistale.sh |
| `repl-iscsi-cross.sh` | repl-iscsi-cross.sh <node>[:<ip>] ...   CONTAINER FLAVOUR, replication setups (adapted replisciscross.sh). The shared kernel has ONE | replisciscross.sh |
| `round-new.sh` | round-new.sh <test id> <iteration>   create a NEW, non-colliding round dir state/rounds/b<test>i<iteration>[a-z], download the full | hand-over rules 1-2 (round dir, first run.log line) |
| `log.sh` | log.sh <round> <NOW\|NOTE\|STEP\|HOLD\|DONE> <text...>   append one masked, time-stamped line to the round's run.log (and print it). | NOW/STEPCHECK/DONE line rules |
| `qc-api.sh` | qc-api.sh <me\|active\|next <test>\|test <test>\|tests\|summary\|history\|warnings\|guide>   read-only platform calls, JSON to stdout | new |
| `qc-dltest.sh` | qc-dltest.sh <test id>   download the FULL test sheet (GET /tests/<id>) to state/tests/test<id>.json + .txt (id, number, | dltest.sh |
| `qc-start.sh` | qc-start.sh <test id>   mark "now" as the start of the next step of a test for the step timing (qc-submit.sh writes the seconds of | qcstart.sh |
| `qc-submit.sh` | qc-submit.sh <round> <test id> <step id> <pass\|fail> <comment file> [--config]   submit ONE step result, exactly ONE try, then prove it | qcsubmit.sh + sub.sh + i8/st.sh (STEPCHECK) |
| `qc-complete.sh` | qc-complete.sh <round> <test id> <complete\|end>   complete = all steps answered, advance the platform's loop; end = after a hard stop | new |
| `qc-report.sh` | qc-report.sh [test...]   timing report from state/qc-step-times.csv: per test the passed rows, time span, total minutes and the 4 | qcreport.sh |
| `qc-sum.sh` | qc-sum.sh [test] [step_no]   summary of state/qc-step-times.csv (PASSED steps of every round): no args = per test (rounds, steps, | qcsum.sh |
| `stage-times.sh` | stage-times.sh <log file> <run name>   append the duration of every "HH:MM:SS STAGE <n> <text>" line of a driver log to | stagetimes.sh |
| `loop-state.sh` | loop-state.sh <command>   state of the whole loop in state/loop.json (iterations, tests passed in a row with no code change). | new |
| `git-latest-branch.sh` | git-latest-branch.sh   the version under test: the highest <branch_prefix><N> branch (no suffix) on YOUR three repos; prints one | skill "latest branch" rule |
| `git-newbranch.sh` | git-newbranch.sh <NEW BRANCH> [base branch]   start a fix branch in all three clones FROM THE LATEST PUSHED BRANCH (default: the | new |
| `code-deploy.sh` | code-deploy.sh <BRANCH> [node...]   put the committed BRANCH of the three local clones onto the nodes (default: every running cluster | new |
| `git-pushbranch.sh` | git-pushbranch.sh <BRANCH>   push a fix branch of the three clones to YOUR repos with the stored credential (adapted pushbranch.sh), | pushbranch.sh |
| `git-pr.sh` | git-pr.sh <BRANCH> [--title <t>] [--body-file <f>]   open the FINAL pull requests from YOUR repos to the upstream repos (repos.upstream, | new |
| `agent.sh` | agent.sh <command>   registry of the fresh agents the supervisor runs (one task per agent), in state/agents/. | new |
| `mailbox.sh` | mailbox.sh <send\|read\|wait> ...   file mailbox between the supervisor and its agents (any agent framework can use it): | mailbox.sh |
| `supervisor-snapshot.sh` | supervisor-snapshot.sh   the supervisor's input for the periodic report (adapted from the original harness watch script): clock, platform active test, loop | original watch script |
| `secret-scan.sh` | secret-scan.sh [dir]   grep a tree (default: the skill repo, tracked + untracked files, state/ and config/input.yaml excluded) for | new |
| `cluster-build-repl.sh` | two-cluster replication build (graceful iSCSI logout, stop, reset cluster 1 then 2, explicit cross-iSCSI); the original also recreated a third container: not portable | buildrepl.sh |
| `ts-pool.sh` | ts-pool.sh [--cluster N] list|disks|new|del|cachespare-add   pool calls of the product API | poollib.sh, diskapi.sh |
| `ts-volume.sh` | ts-volume.sh [--cluster N] list|create-cifs|del   CIFS/HOME volume calls | vollib.sh |
| `ts-user.sh` | ts-user.sh [--cluster N] list|add|login|uid   user calls (password from a file) | userlib.sh |
| `ts-disk-add.sh` | ts-disk-add.sh <count> [GB]   add test loop disks (container flavour; others NEEDS-HUMAN rc 10) | hotadd.sh |
| `ts-disk-remove.sh` | ts-disk-remove.sh <loopN>   detach one test loop disk (container flavour) | hotadd.sh |
| `cluster-wait-takeover.sh` | cluster-wait-takeover.sh <survivor> [max s]   poll portal login after a stop, then print users, volumes, pools | waittakeover.sh |
| `client-mount-check.sh` | client-mount-check.sh   stat-probe NFS/CIFS mounts on client nodes, rc 1 on a stale one | new (stale mount check) |
| `qc-local.sh` | qc-local.sh <test> list|<step> pass|fail [text]   local re-run record, never submits | qclocal.sh |

Libraries (sourced, not run): `lib/common.sh` (config, state dir, `mask`, `secret_tmp`, `run`), `lib/cfg.py` (YAML subset reader + validator), `lib/node.sh` + `lib/nodetype/{container,physical,virtualbox,ssh}.sh` (node abstraction), `lib/tstor.sh` (TopStor API: login from a password file, isinsync, etcd reads, pools), `lib/qc.sh` (platform calls with the key from its file), `lib/git.sh` (git and GitHub API with the credential file).
