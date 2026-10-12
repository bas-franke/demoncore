"""Static scan for performance anti-patterns in per-frame GDScript code (perf role).

Usage (project root):  python tools/perf/scan_hotpaths.py [paths...]
Default: every .gd under autoload/, scenes/, scripts/, ui/.

Looks inside per-frame callbacks (_process, _physics_process, _draw, _integrate_forces, _input,
animate / pose overrides) and reports lines that allocate or scan the tree every frame:
  get_nodes_in_group / find_child(ren) / get_node("long/path") / load() / X.new() of heavy types /
  instantiate() / duplicate() / create_tween() / String formatting into node names / call_group.
It is a heuristic: throttled code (timers, `if _acc < ...: return`) still shows up, so read each hit.
Exit code 0 always; prints one line per hit plus a summary per file.
"""
import os
import re
import sys

ROOTS = ["autoload", "scenes", "scripts", "ui"]
HOT_FUNCS = re.compile(r"^(static\s+)?func\s+(_process|_physics_process|_draw|_integrate_forces|_input|"
                       r"_unhandled_input|animate|pose|_update\w*)\s*\(")
FUNC = re.compile(r"^(static\s+)?func\s+")
PATTERNS = [
    ("group scan", re.compile(r"get_nodes_in_group\(")),
    ("tree search", re.compile(r"\bfind_children?\(")),
    ("load()", re.compile(r"(?<![\w.])load\(")),
    ("heavy new()", re.compile(r"\b(StandardMaterial3D|ShaderMaterial|ArrayMesh|SurfaceTool|ImmediateMesh|"
                               r"MeshInstance3D|OmniLight3D|SpotLight3D|GPUParticles3D|CPUParticles3D|"
                               r"Label3D|Area3D|Timer|Tween)\.new\(")),
    ("instantiate()", re.compile(r"\.instantiate\(")),
    ("duplicate()", re.compile(r"\.duplicate\(")),
    ("tween", re.compile(r"create_tween\(")),
    ("call_group", re.compile(r"call_group\(")),
]


def scan_file(path):
    hits = []
    in_hot = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for no, line in enumerate(f, 1):
            if FUNC.match(line):
                m = HOT_FUNCS.match(line)
                in_hot = m.group(2) if m else None
                continue
            if in_hot is None or line.lstrip().startswith("#"):
                continue
            for name, pat in PATTERNS:
                if pat.search(line):
                    hits.append((no, in_hot, name, line.strip()))
    return hits


def main():
    paths = sys.argv[1:] or ROOTS
    files = []
    for p in paths:
        if os.path.isfile(p):
            files.append(p)
            continue
        for root, _dirs, names in os.walk(p):
            for n in names:
                if n.endswith(".gd"):
                    files.append(os.path.join(root, n))
    total = 0
    for path in sorted(files):
        hits = scan_file(path)
        for no, func, name, text in hits:
            print("%s:%d  [%s in %s]  %s" % (path.replace("\\", "/"), no, name, func, text[:110]))
        total += len(hits)
    print("-- %d hits in %d files scanned" % (total, len(files)))


if __name__ == "__main__":
    main()
