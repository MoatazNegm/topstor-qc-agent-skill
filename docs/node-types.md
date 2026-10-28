# Node types and the node abstraction

Test steps and cluster tools never call docker, ssh or VBoxManage directly; they call the wrappers, which pick the backend from the
node's `type` in `config/input.yaml`:

| Wrapper | container (`docker`) | physical (`ssh`) | virtualbox (`VBoxManage` + ssh) |
|---|---|---|---|
| `node-exec <n> <cmd>` | `docker exec <container> sh -c` (no TTY) | `ssh -T -o BatchMode=yes user@host` | ssh into the VM |
| `node-copy <n> <src> <dst>` | `docker cp` | `scp` | `scp` |
| `node-start <n>` | `docker start` | `start_command` from the config (IPMI/WoL), else rc 10 = ask a human | `startvm --type headless` |
| `node-stop <n> [--hard]` | `docker stop -t 120` (`--hard` refused) | `systemctl poweroff` / `stop_hard_command` | ACPI power button / `controlvm poweroff` (power cut) |
| `node-reboot <n> [--hard]` | `docker restart -t 120` | `systemctl reboot` / `reset_command` | ssh reboot / `controlvm reset` |
| `node-status [n...]` | `State.Status`, boot id = `StartedAt` | ssh answers, boot id = `/proc/sys/kernel/random/boot_id` | `VMState`, boot id via ssh |

- `node-stop` / `node-reboot` refuse a cluster node unless called by `cluster-stopnode.sh` (env `QC_GUARDED=1`), so a pool is never
  left imported by accident. Nodes with `role: client` (NFS/CIFS clients) may be stopped directly.
- `docker_host` on a container node runs docker against a remote engine (`DOCKER_HOST`, e.g. `ssh://root@host`).
- `vbox_manager_ssh` runs VBoxManage on another machine (the hypervisor) through ssh.
- `DRYRUN=1` prints the command to stderr instead of running it (the tests in `tests/selftest.sh` use this).
- Commands are shell strings run by `sh -c` on the node (container) or by the remote login shell (ssh): quote accordingly.

## Adding a type

Create `tools/lib/nodetype/<type>.sh` with `t_exec t_copy t_copy_from t_start t_stop t_reboot t_state t_bootid`, add the type
to `NODE_TYPES` and its required fields to `validate()` in `tools/lib/cfg.py`, and a DRYRUN case to `tests/selftest.sh`.

## What is flavour-specific

- **Container flavour** (all nodes share the host kernel): the iSCSI holder guard, the export before every stop, the own-target
  logout, `host-kernelclean.sh`, `host-stale-clean.sh`, `repl-iscsi-cross.sh`, the `/root/loopdisks` export lists. These must run on
  the docker host itself.
- **Physical flavour** (each node has its own kernel): a stop is a real shutdown; `--export` exports the node's pools first when the
  step wants a clean hand-over; `--hard` is a power cut (only when the step asks for one). Disk add/remove steps are done with real
  disks or VM disks by the user or the hypervisor; the agent asks when it has no way to do them.
