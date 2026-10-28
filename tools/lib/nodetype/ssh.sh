# nodetype/ssh.sh -- shared ssh helpers for type physical and virtualbox (exec, copy, boot id). Sourced, not run.
# Always BatchMode (no password prompts), no TTY (-T): background loopers started by TopStor die with a TTY session.
_sshopts() { local n=$1 k p; k=$(cfgn "$n" ssh_key_file); p=$(cfgn "$n" ssh_port 22)
	echo "-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new -p $p ${k:+-i $k}"; }
_sshdst() { echo "$(cfgn "$1" ssh_user)@$(cfgn "$1" host)"; }
_ssh() { local n=$1; shift; run ssh $(_sshopts "$n") -T "$(_sshdst "$n")" "$@"; }
t_exec() { local n=$1; shift; if [ -n "$NODE_STDIN" ]; then _ssh "$n" "$*"; else _ssh "$n" "$*" </dev/null; fi; }
t_copy() { local n=$1 o; o=$(_sshopts "$n" | sed 's/-p /-P /'); run scp $o "$2" "$(_sshdst "$n"):$3"; }
t_copy_from() { local n=$1 o; o=$(_sshopts "$n" | sed 's/-p /-P /'); run scp $o "$(_sshdst "$n"):$2" "$3"; }
t_bootid() { DRYRUN= _ssh "$1" cat /proc/sys/kernel/random/boot_id 2>/dev/null </dev/null; }
_ssh_up() { DRYRUN= _ssh "$1" true >/dev/null 2>&1 </dev/null; }
# graceful OS actions, detached so the ssh session ends cleanly before the machine goes down
_ssh_poweroff() { _ssh "$1" 'nohup sh -c "sleep 2; systemctl poweroff" >/dev/null 2>&1 &' </dev/null; }
_ssh_reboot() { _ssh "$1" 'nohup sh -c "sleep 2; systemctl reboot" >/dev/null 2>&1 &' </dev/null; }
