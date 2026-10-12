"""Shared builder for the soul shard tiers (soul_shard_0/1/2.py). Each tier <= 200 tris.

Shards are centered on the origin (the pickup bobs them in code), main crystal ~0.34 m tall.
Materials are emissive (Godot converts them non-flashable for the crowds of pickups).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bosses"))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

TIERS = [
    # body color, glow color, glow strength
    ((0.22, 0.02, 0.04), (0.75, 0.06, 0.08), 1.1),
    ((0.34, 0.03, 0.14), (1.0, 0.12, 0.38), 2.4),
    ((0.55, 0.2, 0.06), (1.0, 0.42, 0.14), 3.2),
]


def build_tier(tier):
    body, glow, k = TIERS[tier]
    crystal = sb.mat(f"Shard_Crystal{tier}", body, 0.12, emission=glow, strength=k)
    root = sb.root(f"SoulShard{tier}")
    spin = sb.empty("spin", root)
    # main crystal: long upper point over a short lower one, faceted.
    kit.crystal("main", spin, height=0.36 if tier == 2 else 0.34, radius=0.062 if tier == 2 else 0.07, sides=6,
                top=0.72, loc=(0, 0, -0.03), material=crystal, seed=11 + tier, cap=0.3 if tier == 2 else 0.0)
    if tier == 0:
        kit.crystal("sliver", spin, height=0.16, radius=0.032, sides=5, top=0.7, loc=(0.05, 0.01, -0.06),
                    rot=(10, 28, 0), material=crystal, seed=3)
    if tier >= 1:
        sats = [((0.07, 0.03, -0.05), (0, 34, 20), 0.18), ((-0.065, -0.02, -0.06), (14, -30, -40), 0.2),
                ((0.0, -0.07, -0.07), (-36, 0, 10), 0.14)]
        for i, (loc, rot, h) in enumerate(sats):
            kit.crystal(f"sat{i}", spin, height=h, radius=h * 0.24, sides=5, top=0.72, loc=loc, rot=rot,
                        material=crystal, seed=20 + i)
    if tier == 2:
        kit.crystal("sat3", spin, height=0.16, radius=0.04, sides=5, top=0.7, loc=(0.02, 0.07, -0.06),
                    rot=(38, 10, 0), material=crystal, seed=31)
        band = sb.empty("band", root, rot=(18, 0, 0))
        gold = sb.mat("Shard_GoldBand", (0.7, 0.52, 0.22), 0.3, 0.95)
        sb.torus("band_ring", band, major=0.11, minor=0.009, loc=(0, 0, -0.02), material=gold,
                 major_segments=10, minor_segments=3)
    kit.merge_joint_meshes(root)
    print(f"SHARD{tier} TRIS", kit.tri_count())
    return root
