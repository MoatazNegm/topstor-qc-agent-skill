# nodetype/container.sh -- backend for type: container (TopStor node = privileged docker container).
# Functions: t_exec t_copy t_copy_from t_start t_stop t_reboot t_state t_bootid. Sourced by lib/node.sh.
# Never "docker kill" / "docker rm -f" a node: a kill of the owner of an imported pool suspends it and hangs the shared kernel.
_dk() { local h; h=$(cfgn "$1" docker_host); shift; if [ -n "$h" ]; then DOCKER_HOST=$h run docker "$@"; else run docker "$@"; fi; }
_ctr() { cfgn "$1" container; }
t_exec() { local n=$1; shift; if [ -n "${NODE_STDIN:-}" ]; then _dk "$n" exec -i "$(_ctr "$n")" sh -c "$*"; else _dk "$n" exec "$(_ctr "$n")" sh -c "$*" </dev/null; fi; }
t_copy() { _dk "$1" cp "$2" "$(_ctr "$1"):$3"; }
t_copy_from() { _dk "$1" cp "$(_ctr "$1"):$2" "$3"; }
t_start() { _dk "$1" start "$(_ctr "$1")" >/dev/null; }
t_stop() {
	[ "$2" = --hard ] && { echo "REFUSED: --hard is not allowed for container nodes (a killed pool owner hangs the shared kernel); use a graceful stop" >&2; return 5; }
	_dk "$1" stop -t 120 "$(_ctr "$1")" >/dev/null
}
t_reboot() {
	[ "$2" = --hard ] && { echo "REFUSED: --hard is not allowed for container nodes" >&2; return 5; }
	_dk "$1" restart -t 120 "$(_ctr "$1")" >/dev/null
}
t_state() {
	local s; s=$(DRYRUN= _dk "$1" inspect -f '{{.State.Status}}' "$(_ctr "$1")" 2>/dev/null) || { echo missing; return; }
	case "$s" in running) echo running ;; *) echo stopped ;; esac
}
t_bootid() { DRYRUN= _dk "$1" inspect -f '{{.State.StartedAt}}' "$(_ctr "$1")" 2>/dev/null; }
