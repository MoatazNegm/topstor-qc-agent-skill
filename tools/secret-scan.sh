#!/bin/bash
# secret-scan.sh [dir]   grep a tree (default: the skill repo, tracked + untracked files, state/ and config/input.yaml excluded) for
# key-like strings: platform keys (qc_...), GitHub tokens, private keys, AWS keys, long hex runs, password=/token= with a literal
# value, credentials inside URLs. rc 0 = clean; otherwise the file:line hits are printed with the value masked. Run before every push.
D=${1:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}
python3 -I - "$D" <<'PY'
import os,re,sys
root=sys.argv[1]
pats=[("platform key",r"\bqc_[A-Za-z0-9]{16,}"),("github token",r"\b(ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{20,}"),
 ("private key",r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),("aws key",r"\bAKIA[0-9A-Z]{16}\b"),
 ("long hex",r"\b[0-9a-f]{32,}\b"),("credential in url",r"https?://[^/\s:@]+:[^/\s@]+@"),
 ("literal secret",r"(?i)\b(password|passwd|pass|pw|token|secret|api_?key)\s*[:=]\s*['\"]?(?![$\-{(<'\"/]|_file|\s|\)|$)[A-Za-z0-9!@#%^&*+_./]{6,}")]
skip_dirs={".git","state","node_modules"}
hits=0
for dp,dn,fn in os.walk(root):
    dn[:]=[d for d in dn if d not in skip_dirs]
    for f in fn:
        p=os.path.join(dp,f); rel=os.path.relpath(p,root)
        if rel in ("config/input.yaml",): continue
        try: lines=open(p,errors="ignore").read().splitlines()
        except Exception: continue
        for i,l in enumerate(lines,1):
            for name,rx in pats:
                m=re.search(rx,l)
                if m and "secret-scan: allow" not in l:
                    hits+=1; print("%s:%d: %s: %s"%(rel,i,name,(l[:m.start()]+"<MASKED>"+l[m.end():])[:160].strip()))
print("SECRET SCAN: %s (%d hit(s)) in %s"%("CLEAN" if not hits else "HITS FOUND",hits,root)); sys.exit(1 if hits else 0)
PY
