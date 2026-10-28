# git.sh -- git/GitHub helpers. Sourced. The credential FILE (repos.credential_file, git "store" format) is used directly by git
# (credential.helper=store --file=...) and, for the GitHub API, read through "git credential fill" into a header fd. Never printed,
# never copied, never put on a command line or into a remote URL.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
CRED=$(cfg get repos.credential_file)
REPOS="topstor pace topstorweb"
repo_clone() { cfg get "repos.$1.clone"; }
repo_url() { cfg get "repos.$1.url"; }
repo_upstream() { cfg get "repos.upstream.$1"; }
# g <repo> <git args...>: git in the clone with the stored credential, never prompting
g() { local r=$1; shift; GIT_TERMINAL_PROMPT=0 git -C "$(repo_clone "$r")" -c credential.helper= -c "credential.helper=store --file=$CRED" "$@"; }
gls() { GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c "credential.helper=store --file=$CRED" ls-remote "$@"; }
_gh_hdr() { local h=${GH_HOST:-github.com}
	printf 'Authorization: token %s\n' "$(printf 'protocol=https\nhost=%s\n\n' "$h" | git -c credential.helper= -c "credential.helper=store --file=$CRED" credential fill 2>/dev/null | sed -n 's/^password=//p')"
	printf 'Accept: application/vnd.github+json\nUser-Agent: topstor-qc-agent-skill\n'; }
# gh_api <METHOD> <path> [json body file] -> reply body
gh_api() { local m=$1 p=$2 b=$3 extra=(); [ -r "$CRED" ] || die "credential file not readable: $CRED"
	[ -n "$b" ] && extra=(-H "Content-Type: application/json" -d @"$b")
	curl -s -m 60 -X "$m" -H @<(_gh_hdr) "${extra[@]}" "https://api.github.com/${p#/}"; }
# latest_branch <url> -> highest <prefix><N> branch (no suffix) on that remote
latest_branch() { local pre; pre=$(cfg get repos.branch_prefix QSD5.)
	gls --heads "$1" 2>/dev/null | sed 's#.*refs/heads/##' | grep -E "^${pre//./\\.}[0-9]+$" | sed "s#^${pre//./\\.}##" | sort -n | tail -1 | sed "s#^#$pre#"; }
