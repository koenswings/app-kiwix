#!/bin/sh
# x-app.backup.exclude (agent-engine-dev#241): ZIM archives stay out of Engine backups, the rest of the
# instance stays in. Entry rules mirror the Engine's src/data/BackupExclude.ts and the root helper's
# check_exclude. Paths are matched with borg sh: semantics ('*' within one segment, '**' across; a
# matching folder takes everything under it). Needs python3 (PyYAML if present, else a block-list reader).
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import re, sys
src = open("compose.yaml").read()

def block_list(text, path):
    """The block list under path (e.g. x-app > backup > exclude); no YAML dependency."""
    lines, depth, indent, i = text.split("\n"), 0, -1, 0
    strip = lambda l: re.sub(r"\s+#.*$", "", l)
    while i < len(lines) and depth < len(path):
        l = strip(lines[i]); i += 1
        if not l.strip() or l.strip().startswith("#"): continue
        ind = len(l) - len(l.lstrip())
        if ind <= indent: return None
        if l.strip() == path[depth] + ":": depth, indent = depth + 1, ind
    if depth < len(path): return None
    out = []
    for l in lines[i:]:
        l = strip(l)
        if not l.strip() or l.strip().startswith("#"): continue
        if len(l) - len(l.lstrip()) <= indent: break
        m = re.match(r"^- (.*)$", l.strip())
        if not m: sys.exit("FAIL: not a block list item: " + l)
        out.append(re.sub(r"""^(["'])(.*)\1$""", r"\2", m.group(1).strip()))
    return out

try:
    import yaml
    doc = yaml.safe_load(src)
    ex = ((doc.get("x-app") or {}).get("backup") or {}).get("exclude")
    vols = doc["services"]["kiwix"]["volumes"]
    how = "PyYAML"
    assert ex == block_list(src, ["x-app", "backup", "exclude"]), "PyYAML and block reader disagree"
except ImportError:
    ex = block_list(src, ["x-app", "backup", "exclude"])
    vols = block_list(src, ["services", "kiwix", "volumes"])
    how = "block reader"

RE = re.compile(r"^[A-Za-z0-9._*/-]{1,200}$")
def problem(e):
    if not isinstance(e, str): return "entry %r is not a string" % (e,)
    if not RE.match(e): return "entry %r: empty, longer than 200, or a character outside [A-Za-z0-9._*/-]" % e
    if e.startswith("/"): return "entry %r is absolute" % e
    if e.startswith("-"): return "entry %r starts with '-'" % e
    for s in e.split("/"):
        if s == "": return "entry %r has an empty path segment" % e
        if s in (".", ".."): return "entry %r has a %r segment" % (e, s)
    return None

def sh_re(p):
    out = ""
    for t in re.split(r"(\*\*/?|\*)", p):
        out += ".*" if t in ("**/", "**") else "[^/]*" if t == "*" else re.escape(t)
    return re.compile("^" + out + "$")
def excluded(path, entries):
    segs = path.split("/")
    return any(sh_re(e).match("/".join(segs[:k + 1])) for e in entries for k in range(len(segs)))

n = 0
def ok(msg):
    global n; n += 1; print("ok: " + msg)
def fail(msg): sys.exit("FAIL: " + msg)

if not isinstance(ex, list) or not ex: fail("x-app.backup.exclude missing or not a list")
if len(ex) > 32: fail("more than 32 entries")
if len(set(ex)) != len(ex): fail("duplicate entries")
for e in ex:
    p = problem(e)
    if p: fail(p)
ok("x-app.backup.exclude (%s): %d valid entr%s %s" % (how, len(ex), "y" if len(ex) == 1 else "ies", ex))
for bad in ["", "/data", "-x", "data//x", "data/", "./data", "data/../x", "data/a b", "data/$x", "x" * 201]:
    if problem(bad) is None: fail("checker accepted bad entry %r" % bad)
ok("rule checker refuses bad entries")
if "./data:/data:ro" not in [str(v) for v in vols] and not any(isinstance(v, dict) and v.get("source") == "./data" for v in vols):
    fail("volume ./data:/data:ro not found: %r" % (vols,))
if "/data/*.zim" not in src: fail("compose no longer serves /data/*.zim")
if "data/*.zim" not in ex: fail("data/*.zim not excluded")
ok("ZIM path follows the compose layout (./data -> /data, serves /data/*.zim)")
for p in ["data/wikipedia_en-simple_all_maxi_2026-09.zim", "data/wikipedia_en_all_maxi_2026-09.zim", "data/renamed_1.zim"]:
    if not excluded(p, ex): fail(p + " is not excluded")
ok("ZIM files in data/ are excluded")
for p in ["data", "data/wikipedia_en-simple_all_maxi_2026-09.zim.sha256", "data/notes.txt", "data/README.md",
          "compose.yaml", ".env", "app.yaml", "README.md"]:
    if excluded(p, ex): fail(p + " must NOT be excluded")
ok("data/ itself, ZIM checksums, other files, compose.yaml and .env are NOT excluded")
print("PASS backup-exclude (%d checks)" % n)
PY
