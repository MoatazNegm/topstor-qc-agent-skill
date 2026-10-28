# Cluster safety rules (any TopStor cluster)

These come from real incidents on a TopStor dev cluster (three ZFS deadlocks that needed a host reboot, a kernel oops in iSCSI,
suspended pools). They apply to every flavour; the container-flavour items matter most because all nodes share ONE kernel there
(ZFS, LIO target, iSCSI initiator are kernel-wide: one bad stop hangs every node and the host).

## 1. Settle and sync

- After EVERY node start/return, and BEFORE EVERY stop: a real settle of `cluster.settle_seconds` (300 s) after the node's own
  setup has finished, then the isinsync check (`tools/cluster-settle.sh <node>`). Probe a RUNNING node. Disclose in the step
  comment when a wait was over or short.
- Nothing runs longer than 3 minutes without a check that it makes normal progress (log growing, processes, node logs). A stage
  slower than its previous run is investigated at once and the reason reported; never wait on a long timeout alone.
- A restarted node whose local etcd lacks some `volumes/...` keys while isinsync=yes and the pool information matches is not a
  finding.

## 2. Stopping nodes and pools

- A cluster node is stopped ONLY by `tools/cluster-stopnode.sh` (container flavour: stops the share containers that hold its
  pools, releases LIO, exports each pool with retries, checks it is gone, logs the initiator out of this node's own target, then a
  graceful stop). rc 2 = a pool could not be exported, the node was NOT stopped: change the sequence, never stop it by hand.
- **"Sudden death", "power off", "close" a node** in the container flavour = this graceful stop (the pool is handed to the other
  node without being suspended). On physical/VirtualBox nodes a real power cut is allowed (`--hard`) when the step asks for it.
- **iSCSI initiator holder.** In the container flavour one node container holds the kernel's iscsid; stopping it while ANOTHER node
  has a pool imported over its sessions suspends that pool. The guard refuses (rc 5): stop the other node / move the pool first, and
  stop the holder last. Pick the stop order by holder before the stage starts.
- NEVER log out iSCSI sessions while any node has a pool imported (find the owner first; in the container flavour `zpool list`
  shows the pools of every node). The only logout is the one built into `cluster-stopnode.sh` (own target, own pools exported).
- Never run `iscsiadm` on a container host: it socket-activates a host iscsid that steals the initiator from the nodes (recovery:
  stop the host iscsid and its socket unit; the node's guardian starts its own again).
- Never `docker kill` / `docker rm -f` a node that owns an imported pool; never detach or delete a disk of an imported pool (offline
  it through the product first, or skip with a reason); never `zpool export|clear` a SUSPENDED pool.
- Never re-run a "fresh build" phase (remove/recreate nodes, wipe LIO) while a pool is imported; export early, never late. Resume
  scripts start AFTER their build phase, never copy a header that includes it.
- `timeout 10 zpool list` between steps. rc 124 or a SUSPENDED pool: stop everything, report at once.

## 3. Disks (container flavour)

- Test disks are host loop devices on sparse files outside the nearly-full root disk. Every node gets its OWN disks (disjoint export
  lists `/root/loopdisks`): a device can back only one LIO backstore, so the node that exports it first owns it.
- "Add N disks while running" = attach loops, add the names to the node's list, wait until the disks are listed by the product.
  "Remove a disk" = only for a free disk: remove it from the list, clean LIO, delete the stale SCSI device, detach the loop.
- `tools/host-stale-clean.sh` at the start of a build (after every node was stopped): stale LIO disks and loops of earlier tests
  otherwise survive into the new cluster (a test once saw 17 instead of 12 disks).
- Replication builds: `tools/cluster-build-repl.sh` (logs out iSCSI gracefully only while no pool is imported).
- Not ported (write them yourself with the API calls named in the original harness): replica hot-add and disk lists, replication/group/domain/flask/balance wait loops, failover watch, SMB/NFS volume settings. Use `ts_api` from `tools/lib/tstor.sh` and `run`; keep DRYRUN.
- Replication setups: `tools/repl-iscsi-cross.sh` only with explicit node arguments; never for the owner of an imported pool
  (re-logging its own target suspended its pool once). The ACL is lost when the node restarts: run it again then.

## 4. Builds

- Every test starts on a freshly reset cluster (`tools/cluster-reset.sh`): reset the existing nodes, never recreate a node that
  works (recreation is slow and left stale state). Recreate only when a node is really broken.
- Only one node may sit on the first-boot address at a time: the reset tool keeps the members down while the primary is reset.
- After a node restart do not start the product setup by hand before the node's boot work is done; a reset or first boot may need
  two passes (new host name, restart, real setup).
- `tools/cluster-refreshcversion.sh` after every build and every code deploy (a stale version key makes a returning node fall back to
  the old branch).
- Do not run heavy disk cleanup during a join (it made a join fail once).

## 5. Reboots of a host or hypervisor

- Controlled by `loop.reboot_for_tool_problems` (default true; the value is printed in every supervisor snapshot).
  true: the tester may request a reboot for ANY problem caused by its tools or by a suspended/hung pool (not a code error), with
  evidence in `run.log` (the failing command and output, SUSPENDED pool, `txg_sync` in D state, `zpool list` rc 124, ...).
  false: only for a hung kernel/pool: a SUSPENDED pool that does not clear, `txg_sync` in D state, or `zpool list` rc 124.
- A tool or pool problem is not a code error: after the reboot the tester resumes the test from `RESUME.md` and does NOT fail the step.
  The request and the resume are logged in `run.log`.
- Before approving, the supervisor tells every other agent; each saves its state, writes its restart command and confirms it can
  resume its current job. Then the supervisor approves this one reboot (a hard reboot by any means is allowed, e.g. SysRq) and tells
  the user in the next report. Approval covers that one reboot only.
- Never restart the host's docker engine; never run a host-wide `sync` while a pool may be suspended (it blocks in D state).
- Never change the host's own management interface, its routes or firewall input rules; ask the user before any host network change.
- After a reboot: start the helper containers that do not come back by themselves, check `zpool list` is clean, resume the agents.

## 6. Data and logs

- Logs, timings, ledgers, config zips, round dirs and `config/input.yaml` stay in `state/` and are never committed.
- Images, disks and container data go to a large data disk, never to a nearly-full root disk.
