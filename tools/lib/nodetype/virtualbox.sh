# nodetype/virtualbox.sh -- backend for type: virtualbox (VBoxManage for power, ssh into the VM for exec/copy).
# vbox_manager_ssh (user@hypervisor) runs VBoxManage on another machine. Sourced by lib/node.sh.
. "$QC_TOOLS/lib/nodetype/ssh.sh"
_vbm() { local n=$1 m; shift; m=$(cfgn "$n" vbox_manager_ssh)
	if [ -n "$m" ]; then run ssh -o BatchMode=yes -o ConnectTimeout=10 -T "$m" "VBoxManage $(printf '%q ' "$@")" </dev/null; else run VBoxManage "$@"; fi; }
_vm() { cfgn "$1" vbox_name; }
_vmstate() { DRYRUN= _vbm "$1" showvminfo "$(_vm "$1")" --machinereadable 2>/dev/null | sed -n 's/^VMState="\(.*\)"/\1/p'; }
t_start() { [ "$(_vmstate "$1")" = running ] && return 0; _vbm "$1" startvm "$(_vm "$1")" --type headless >/dev/null; }
t_stop() {
	if [ "$2" = --hard ]; then _vbm "$1" controlvm "$(_vm "$1")" poweroff; return; fi   # a real power cut ("sudden death")
	_vbm "$1" controlvm "$(_vm "$1")" acpipowerbutton || return
	[ -n "$DRYRUN" ] && return 0
	local i; for i in $(seq 1 36); do [ "$(_vmstate "$1")" = poweroff ] && return 0; sleep 5; done
	echo "VM $(_vm "$1") still not powered off after 180 s" >&2; return 4
}
t_reboot() { if [ "$2" = --hard ]; then _vbm "$1" controlvm "$(_vm "$1")" reset; else _ssh_reboot "$1"; fi; }
t_state() { case "$(_vmstate "$1")" in running) echo running ;; "") echo missing ;; *) echo stopped ;; esac; }
