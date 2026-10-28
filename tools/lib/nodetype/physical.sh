# nodetype/physical.sh -- backend for type: physical (a real server reached by ssh). Sourced by lib/node.sh.
# Power on / hard power off need an out-of-band command from the config (start_command, stop_hard_command,
# reset_command: e.g. ipmitool with -f <password file>); without one the tool returns 10 = NEEDS-HUMAN.
. "$QC_TOOLS/lib/nodetype/ssh.sh"
_oob() { local n=$1 f=$2 c; c=$(cfgn "$n" "$f"); [ -n "$c" ] || { echo "NEEDS-HUMAN: no $f for $n in the config; ask the user to do it by hand" >&2; return 10; }; run sh -c "$c"; }
t_start() { _ssh_up "$1" && return 0; _oob "$1" start_command; }
t_stop() { if [ "$2" = --hard ]; then _oob "$1" stop_hard_command; else _ssh_poweroff "$1"; fi; }
t_reboot() { if [ "$2" = --hard ]; then _oob "$1" reset_command; else _ssh_reboot "$1"; fi; }
t_state() { _ssh_up "$1" && echo running || echo stopped; }
