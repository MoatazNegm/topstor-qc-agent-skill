#!/bin/bash
# verify-manifest.sh [--status|--hash|--update]   AUDIT aid: recompute the sha256 of every file listed in MANIFEST.sha256.
#   (no option) print OK or MODIFIED plus the changed/missing files; rc 0 = all match, rc 1 = MODIFIED or no manifest.
#   --status    print one word, OK or MODIFIED (used by qc-submit.sh for the step stamp).   --hash  print the manifest hash (sha256 of MANIFEST.sha256).
#   --update    MAINTAINER ONLY: regenerate MANIFEST.sha256 after a reviewed release. Agents never run it (docs/integrity.md).
# This detects accidental or casual edits; it cannot stop a determined user (they can edit this script too). Real enforcement is server side.
R=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd); M=$R/MANIFEST.sha256; cd "$R" || exit 1
listed() { { ls VERSION SKILL.md README.md config/input.example.yaml docs/*.md docs/roles/*.md tests/selftest.sh 2>/dev/null
	find tools -type f ! -name '*.pyc' ! -path '*/__pycache__/*' 2>/dev/null; } | grep -v '^docs/FIXLOG' | LC_ALL=C sort -u; }
case "${1:-}" in
--update) listed | while read -r f; do sha256sum "$f"; done > "$M"; echo "manifest rewritten: $(wc -l < "$M") files, hash $(sha256sum "$M" | cut -c1-12)"; exit 0;;
--hash) [ -f "$M" ] && sha256sum "$M" | cut -d' ' -f1 || echo none; exit 0;;
esac
[ -f "$M" ] || { [ "$1" = --status ] && echo MODIFIED || echo "MODIFIED: no MANIFEST.sha256"; exit 1; }
bad=$(sha256sum -c --quiet "$M" 2>&1 | sed 's/: FAILED.*/ changed/; s/: No such file.*/ missing/; /WARNING/d' | grep -E 'changed|missing')
extra=$(comm -13 <(awk '{print $2}' "$M" | LC_ALL=C sort -u) <(listed) | sed 's/$/ NOT-IN-MANIFEST/')
[ -n "$extra" ] && bad="$bad${bad:+
}$extra"
if [ -z "$bad" ]; then [ "$1" = --status ] && echo OK || echo "OK (skill v$(cat VERSION) manifest $(sha256sum "$M" | cut -c1-12), $(wc -l < "$M") files)"; exit 0; fi
[ "$1" = --status ] && echo MODIFIED || { echo "MODIFIED:"; echo "$bad"; }; exit 1
