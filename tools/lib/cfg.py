#!/usr/bin/env python3
# cfg.py - read and validate config/input.yaml (no third-party modules needed; PyYAML is used when present).
# usage: cfg.py get <dotted.path> [default]      scalar (lists are printed space-separated)
#        cfg.py nodes [--cluster N] [--role R] [--type T]   node names, one per line
#        cfg.py node <name> <field> [default]     one field of one node
#        cfg.py validate                          list every missing/invalid field; exit 2 when incomplete
#        cfg.py json                              the parsed config as JSON (paths only, never secret values)
# Config file: $QC_CONFIG, else <skill root>/config/input.yaml.
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CFG = os.environ.get("QC_CONFIG") or os.path.join(ROOT, "config", "input.yaml")


# ---------------------------------------------------------------- minimal YAML subset
def _strip_comment(s):
    out, q = [], None
    for i, ch in enumerate(s):
        if q:
            if ch == q:
                q = None
        elif ch in "'\"":
            q = ch
        elif ch == "#" and (i == 0 or s[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out).rstrip()


def _scalar(v):
    v = v.strip()
    if v == "" or v in ("~", "null", "Null", "NULL"):
        return None
    if (v[0] == v[-1]) and v[0] in "'\"" and len(v) >= 2:
        return v[1:-1]
    if v in ("true", "True", "yes"):
        return True
    if v in ("false", "False", "no"):
        return False
    if v.startswith("{") and v.endswith("}"):
        inner = v[1:-1].strip()
        out = {}
        for part in (inner.split(",") if inner else []):
            k, _, x = part.partition(":")
            if not k.strip():
                raise ValueError("bad inline map: %r" % v)
            out[k.strip()] = _scalar(x)
        return out
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        return [_scalar(x) for x in inner.split(",")] if inner else []
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    return v


def _lines(text):
    res = []
    for raw in text.splitlines():
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            raise ValueError("tabs are not allowed for indentation: %r" % raw)
        s = _strip_comment(raw)
        if s.strip():
            res.append([len(s) - len(s.lstrip(" ")), s.strip()])
    return res


def _parse(lines, i, ind):
    if i >= len(lines):
        return None, i
    if lines[i][1].startswith("- ") or lines[i][1] == "-":
        out = []
        while i < len(lines) and lines[i][0] == ind and (lines[i][1].startswith("- ") or lines[i][1] == "-"):
            rest = lines[i][1][1:].strip()
            if rest == "":
                i += 1
                val, i = _parse(lines, i, lines[i][0]) if i < len(lines) and lines[i][0] > ind else (None, i)
                out.append(val)
            elif re.match(r"^[A-Za-z0-9_.-]+:(\s|$)", rest):
                lines[i] = [ind + 2, rest]          # "- key: v" = a map that starts on this line
                val, i = _parse(lines, i, ind + 2)
                out.append(val)
            else:
                out.append(_scalar(rest))
                i += 1
        return out, i
    out = {}
    while i < len(lines) and lines[i][0] == ind and not lines[i][1].startswith("- "):
        m = re.match(r"^([A-Za-z0-9_.-]+):(?:\s+(.*))?$", lines[i][1])
        if not m:
            raise ValueError("cannot parse line: %r" % lines[i][1])
        k, v = m.group(1), m.group(2)
        i += 1
        if v is None or v == "":
            if i < len(lines) and (lines[i][0] > ind or (lines[i][0] == ind and lines[i][1].startswith("- "))):
                val, i = _parse(lines, i, lines[i][0])
            else:
                val = None
        else:
            val = _scalar(v)
        out[k] = val
    return out, i


def load(path=CFG):
    text = open(path).read()
    try:
        import yaml  # noqa
        return yaml.safe_load(text) or {}
    except ImportError:
        pass
    lines = _lines(text)
    val, i = _parse(lines, 0, lines[0][0] if lines else 0)
    if i != len(lines):
        raise ValueError("unparsed content near: %r" % lines[i][1])
    return val or {}


# ---------------------------------------------------------------- access helpers
def dig(c, path, default=None):
    cur = c
    for p in path.split("."):
        if isinstance(cur, list) and p.isdigit():
            cur = cur[int(p)] if int(p) < len(cur) else None
        elif isinstance(cur, dict):
            cur = cur.get(p)
        else:
            cur = None
        if cur is None:
            return default
    return cur


def show(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return " ".join(show(x) for x in v)
    if isinstance(v, dict):
        return json.dumps(v)
    return str(v)


def node(c, name):
    for n in c.get("nodes") or []:
        if isinstance(n, dict) and n.get("name") == name:
            return n
    return None


# ---------------------------------------------------------------- validation
PLACEHOLDER = re.compile(r"CHANGE_ME|<[^>]*>|^\.\.\.$")
SECRETISH = re.compile(r"(password|passwd|token|secret|api_?key|apikey|credential)$", re.I)
NODE_TYPES = ("container", "physical", "virtualbox")
ROLES = ("primary", "member", "replication-primary", "replication-member", "client")


def validate(c):
    errs, warns = [], []

    def need(path, msg=None):
        v = dig(c, path)
        if v is None or (isinstance(v, str) and (v.strip() == "" or PLACEHOLDER.search(v))):
            errs.append("%s: %s" % (path, msg or "missing or still a placeholder"))
            return None
        return v

    def need_file(path, secret=True):
        v = need(path, "missing: give the PATH of a file (never the value itself)")
        if v is None:
            return
        if not os.path.isfile(v):
            errs.append("%s: file %s does not exist" % (path, v))
        elif os.path.getsize(v) == 0:
            errs.append("%s: file %s is empty" % (path, v))
        elif secret and (os.stat(v).st_mode & 0o077):
            warns.append("%s: file %s is readable by group/others (chmod 600 it)" % (path, v))

    # inline secrets are refused everywhere: keys named like a secret must end in _file and hold a path
    def walk(x, p=""):
        if isinstance(x, dict):
            for k, v in x.items():
                kp = p + "." + k if p else k
                if SECRETISH.search(k) and not k.endswith("_file") and v not in (None, ""):
                    errs.append("%s: inline secret value is not allowed; use %s_file: /path/to/file" % (kp, k))
                walk(v, kp)
        elif isinstance(x, list):
            for i, v in enumerate(x):
                walk(v, "%s.%d" % (p, i))
    walk(c)

    need("platform.url")
    if PLACEHOLDER.search(show(dig(c, "platform.app_id"))):
        errs.append("platform.app_id: still a placeholder (give the id, or \"\" when the platform needs none)")
    need_file("platform.tester_key_file")
    if dig(c, "platform.admin_key_file"):
        warns.append("platform.admin_key_file is set: it is NEVER used for step results (sheet text changes only, after validation)")
    fl = need("cluster.flavour")
    if fl and fl not in ("container", "physical"):
        errs.append("cluster.flavour: must be container or physical")
    need("cluster.cluster_ip", "the cluster (portal) address of cluster 1 -- give YOUR network's address")
    need("cluster.first_boot_ip", "address a freshly reset node sits on (see the product setup)")
    need("cluster.discovery_ip", "discovery etcd address used during a join")
    need_file("cluster.admin_password_file")
    if dig(c, "cluster.reset_admin_password_file"):
        need_file("cluster.reset_admin_password_file")

    nodes = c.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        errs.append("nodes: at least one node is needed")
        nodes = []
    names = set()
    prim = {}
    for i, n in enumerate(nodes):
        p = "nodes.%d" % i
        if not isinstance(n, dict):
            errs.append(p + ": must be a map")
            continue
        nm = need(p + ".name")
        if nm in names:
            errs.append(p + ".name: duplicate name " + str(nm))
        names.add(nm)
        t = need(p + ".type")
        if t and t not in NODE_TYPES:
            errs.append("%s.type: must be one of %s" % (p, ", ".join(NODE_TYPES)))
        r = need(p + ".role")
        if r and r not in ROLES:
            errs.append("%s.role: must be one of %s" % (p, ", ".join(ROLES)))
        if r in ("primary", "replication-primary"):
            prim.setdefault(n.get("cluster", 1), []).append(nm)
        if r != "client":
            need(p + ".host", "the node IP/host name the node is reached with")
            need(p + ".alias", "short name the node gets in the cluster")
        if n.get("cluster") not in (None, 1, 2, "1", "2"):
            errs.append(p + ".cluster: must be 1 or 2")
        if str(n.get("cluster", 1)) == "2" and r != "client":
            need("cluster.second_cluster_ip", "a node has cluster: 2, so the second cluster address is needed")
            need_file("cluster.second_admin_password_file")
        if fl in ("container", "physical") and t and t in NODE_TYPES and r != "client":
            bad = (fl == "container" and t != "container") or (fl == "physical" and t == "container")
            if bad:   # QC_ALLOW_MIXED_TYPES=1 is for the offline selftest only (it exercises every node type in one config)
                (warns if os.environ.get("QC_ALLOW_MIXED_TYPES") else errs).append(
                    "%s.type: %s does not fit flavour %s (container flavour = containers on one shared kernel; physical = servers/VMs)" % (p, t, fl))
        if fl == "container" and t == "container" and n.get("docker_host"):
            warns.append("%s.docker_host is set: the host-* clean-up tools work on the LOCAL kernel and are REFUSED while any container node uses a remote docker host" % p)
        if t == "container":
            need(p + ".container", "the docker container name")
        if t == "physical":
            need(p + ".ssh_user")
        if t == "virtualbox":
            need(p + ".vbox_name", "the VBoxManage VM name")
            need(p + ".ssh_user", "ssh user inside the VM (node-exec goes through ssh)")
        for k in ("ssh_key_file",):
            if n.get(k):
                need_file(p + "." + k)
    for cl, ps in prim.items():
        if len(ps) > 1:
            errs.append("cluster %s has more than one primary: %s" % (cl, ", ".join(ps)))
    if nodes and not prim:
        errs.append("nodes: no node has role primary")

    need_file("repos.credential_file")
    need("repos.user_owner", "your GitHub account (owner of the repos below)")
    for r in ("topstor", "pace", "topstorweb"):
        need("repos.%s.url" % r, "https URL of YOUR repo")
        cl = need("repos.%s.clone" % r, "local path of your clone")
        if cl and not os.path.isdir(os.path.join(str(cl), ".git")):
            warns.append("repos.%s.clone: %s is not a git clone yet (the coder clones it on first use)" % (r, cl))
        need("repos.upstream.%s" % r, "owner/repo of the original (e.g. moataznegm/...)")
    need("repos.upstream.base_branch", "branch of the upstream repos the pull requests target")
    need("repos.branch_prefix")
    return errs, warns


def main(a):
    if not a:
        print(__doc__ or open(__file__).read().split("\nimport")[0]); return 1
    if not os.path.isfile(CFG):
        print("CONFIG MISSING: %s -- copy config/input.example.yaml to config/input.yaml and fill it in" % CFG, file=sys.stderr)
        return 2
    try:
        c = load()
    except Exception as e:  # noqa
        print("CONFIG UNREADABLE: %s: %s" % (CFG, e), file=sys.stderr); return 2
    cmd = a[0]
    if cmd == "get":
        v = dig(c, a[1])
        if v is None and len(a) > 2:
            v = a[2]
        print(show(v)); return 0
    if cmd == "nodes":
        f = dict(zip(a[1::2], a[2::2]))
        for n in c.get("nodes") or []:
            if "--cluster" in f and str(n.get("cluster", 1)) != f["--cluster"]: continue
            if "--role" in f and n.get("role") != f["--role"]: continue
            if "--type" in f and n.get("type") != f["--type"]: continue
            print(n.get("name"))
        return 0
    if cmd == "node":
        n = node(c, a[1])
        if n is None:
            print("no node named %s in %s" % (a[1], CFG), file=sys.stderr); return 3
        v = n.get(a[2])
        if v is None and len(a) > 3:
            v = a[3]
        print(show(v)); return 0
    if cmd == "validate":
        e, w = validate(c)
        for x in w: print("WARN  " + x)
        for x in e: print("ERROR " + x)
        if e:
            print("CONFIG INCOMPLETE: %d problem(s) in %s -- STOP and ask the user to fill them in" % (len(e), CFG)); return 2
        print("CONFIG OK: %s (%d nodes)" % (CFG, len(c.get("nodes") or []))); return 0
    if cmd == "json":
        print(json.dumps(c, indent=1)); return 0
    print("unknown command " + cmd, file=sys.stderr); return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
