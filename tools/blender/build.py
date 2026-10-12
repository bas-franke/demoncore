"""Builds Blender model scripts into .glb files for Godot.

Usage (from the project root):
  blender -b --factory-startup --python tools/blender/build.py -- all
  blender -b --factory-startup --python tools/blender/build.py -- enemies/choir_wisp demons/vharok

Each tools/blender/models/<category>/<name>.py defines build() (see sb.py for conventions) and
is written to assets/models/<category>/<name>.glb. Then run Godot once with --import.
"""
import importlib.util
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, "..", ".."))
MODELS = os.path.join(HERE, "models")
if os.name == "nt" and len(MODELS) > 120 and not MODELS.startswith(r"\\?" + "\\"):
    # blender.exe is not long-path aware: model scripts past MAX_PATH (260 chars) are invisible
    # to it unless addressed with the \\?\ prefix (this project lives ~210 chars deep).
    MODELS = r"\\?" + "\\" + MODELS
OUT = os.path.join(PROJECT, "assets", "models")
sys.path.insert(0, HERE)

import sb  # noqa: E402


def targets(args):
    if not args or args == ["all"]:
        found = []
        for cat in sorted(os.listdir(MODELS)):
            cdir = os.path.join(MODELS, cat)
            if os.path.isdir(cdir) and not cat.startswith("_"):  # _demo categories: build explicitly
                for f in sorted(os.listdir(cdir)):
                    if f.endswith(".py") and not f.startswith("_"):
                        found.append(f"{cat}/{f[:-3]}")
        return found
    return [a.replace("\\", "/").removesuffix(".py") for a in args]


def build_one(rel):
    src = os.path.join(MODELS, *rel.split("/")) + ".py"
    spec = importlib.util.spec_from_file_location(rel.replace("/", "_"), src)
    mod = importlib.util.module_from_spec(spec)
    sb.reset()
    spec.loader.exec_module(mod)
    mod.build()
    # Texture baking (opt-in: module-level BAKE = {"size": 1024}; see bake.py). SB_BAKE=0 skips it.
    import bake
    if getattr(mod, "BAKE", None) is not None and os.environ.get("SB_BAKE", "1") != "0":
        bake.bake_scene(mod.BAKE, rel)
    bake.flatten_scene()  # unbaked procedural (sbmat) materials -> flat colors
    cat = rel.split("/")[0]
    os.makedirs(os.path.join(OUT, cat), exist_ok=True)
    out = os.path.join(OUT, cat, rel.split("/")[-1] + ".glb")
    sb.export(out)
    print(f"BUILT {rel} -> {os.path.relpath(out, PROJECT)}")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    failed = []
    for rel in targets(args):
        try:
            build_one(rel)
        except Exception:
            traceback.print_exc()
            failed.append(rel)
            print(f"FAILED {rel}")
    print(f"DONE built={len(targets(args)) - len(failed)} failed={len(failed)} {failed}")


main()
