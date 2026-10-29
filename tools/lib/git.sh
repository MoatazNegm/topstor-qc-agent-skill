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
# latest_branch <url> -> highest <prefix><N> branch (no suffix) on that remote
latest_branch() { local pre; pre=$(cfg get repos.branch_prefix QSD5.)
	gls --heads "$1" 2>/dev/null | sed 's#.*refs/heads/##' | grep -E "^${pre//./\\.}[0-9]+$" | sed "s#^${pre//./\\.}##" | sort -n | tail -1 | sed "s#^#$pre#"; }
