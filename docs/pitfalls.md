# Pitfalls (lessons from earlier QC runs)

Each line: what went wrong, what to do instead.

## Results and honesty
- FAILs were submitted because our own stop guard refused, or because the sheet's IPs / Windows machines differ: they cost points
  and said the product was broken when it was not. Only a validated real app bug is a FAIL (`docs/loop-rules.md` 4).
- A step that passed in iterations 1-4 failed in iteration 5 after the stop sequence changed: compare with earlier rounds before
  believing a failure; the supervisor must catch this before the submit.
- A comment claimed something that was true 15 s later, not at that moment; another overstated a time. Build comment text from
  command output captured at that moment; never type results from memory.
- `showmount -e` does not apply to NFSv4-only volumes: not a product bug, do not "fix" the product for it.
- A volume larger than the pool's free space must be accepted (maintainer decision), not reported.

## Builds and nodes
- A join "took 30 minutes" because a monitor only watched stage lines: watch the full log, check every 3 minutes, and find the cause
  (known cause: the discovery service started with an empty IP; check it and restart the discovery scan).
- A node started its setup before its image preload had finished and looped forever waiting for etcd: wait for the node's boot work.
- `docker exec` right after a container start returns an error text; a script kept that text as the host name and never matched:
  wait for a real host name (`dhcpNNN` on a reset node).
- A resume script re-ran the "fresh build" phase while a pool was ONLINE: the pool suspended, the host needed a reboot. Resume after
  the build phase only, and export pools early.
- Recreating node containers for every test was slow and left stale clones on old branches: reset the existing nodes.
- A branch made from an older base silently lost the previous fix: new branches start from the latest pushed branch, and the base
  must be an ancestor (`git-newbranch.sh` checks it).
- Uncommitted fixes on a node were wiped by the product's own `git reset --hard` during setup: commit and deploy before any reset.
- A returning node pulled its old branch from a stale version key: run `cluster-refreshcversion.sh` after every build and deploy.
- Old LIO disks/loops survived into a new build (17 instead of 12 disks): `host-stale-clean.sh` at the start of every build.
- Replication: the single-node cluster's node address was the docker address of another node, discovery was refused for 40 min:
  give every node a unique address and check `hosts/allinfo` before adding disks. Users/groups APIs take group ids, not names.

## iSCSI and pools
- Logging the host out of ALL sessions (not only the stopped node's own target) made the survivor's first import fail and the
  product dropped the import trigger: logout only of the stopped node's own target, after its pools were exported.
- Running `iscsiadm` on the container host started a host iscsid with the host's initiator name; the next cluster never logged in to
  its own disks. Use the nodes' own iscsiadm only.
- The default node list of the replication login helper re-logged the pool owner's own target and suspended its pool: give the
  nodes explicitly.
- A busy pool (share containers hold its datasets) cannot be exported; the product's stop then left it imported and the node's stop
  suspended it: stop the share containers first (`cluster-stopnode.sh` does it, and retries because the product restarts them).

## Platform
- A submit that timed out may still be stored; a blind retry would store it twice: one try, then prove with history.
- The platform replaced the running test under the agent: re-read `/tests/active` and follow it, do not argue.
- Points can be withheld for rapid failures across tests: do the work, do not rush results.
