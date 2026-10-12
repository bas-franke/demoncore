"""sbanim showcase: winged templar knight (cape, tabard, plume, sword, shield, feathered wings).
Underscore file = never built by `all`. Build / preview explicitly:
  blender -b --factory-startup --python tools/blender/build.py -- _anim_demo/_knight
  blender -b --factory-startup --python tools/blender/anim_preview.py -- _anim_demo/_knight walk
Animations: idle walk fly attack hit death  (every sbanim feature is used somewhere - see comments)
"""
import math
import sb
import sbanim as A

CATEGORY = "_anim_demo"


def limb(name, parent, length, r1, r2, material):
    """Cylinder hanging DOWN from a joint (joint at the top)."""
    return sb.cylinder(name, parent, r1=r1, r2=r2, depth=length, rot=(180, 0, 0), material=material, segments=12)


def build():
    steel = sb.mat("Steel", (0.32, 0.31, 0.3), roughness=0.38, metallic=0.9)
    dark = sb.mat("DarkSteel", (0.12, 0.115, 0.11), roughness=0.5, metallic=0.85)
    gold = sb.mat("Gold", (0.72, 0.55, 0.26), roughness=0.32, metallic=1.0)
    cloth = sb.mat("Crimson", (0.32, 0.04, 0.035), roughness=0.85)
    feather = sb.mat("Ash", (0.62, 0.6, 0.56), roughness=0.8)
    glow = sb.mat("EyeGlow", (1.0, 0.75, 0.35), emission=(1.0, 0.6, 0.2), strength=8.0)
    slash_m = sb.mat("SlashGlow", (1.0, 0.85, 0.6), emission=(1.0, 0.7, 0.3), strength=10.0)

    root = sb.root("TemplarDemo")
    body = sb.empty("body", root)                       # ground pivot (death topples around it)
    hips = sb.empty("hips", body, loc=(0, 0, 1.0))
    sb.box("pelvis", hips, size=(0.34, 0.22, 0.16), loc=(0, 0, 0.02), material=dark, bevel=0.03)
    sb.box("belt", hips, size=(0.36, 0.24, 0.05), loc=(0, 0, 0.09), material=gold, bevel=0.01)

    thigh, shin, foot = {}, {}, {}
    for s, x in (("L", 1), ("R", -1)):
        thigh[s] = sb.empty(f"thigh_{s}", hips, loc=(x * 0.11, 0, -0.04))
        limb(f"thigh_m_{s}", thigh[s], 0.44, 0.075, 0.06, steel)
        shin[s] = sb.empty(f"shin_{s}", thigh[s], loc=(0, 0, -0.46))
        sb.sphere(f"knee_m_{s}", shin[s], 0.065, loc=(0, -0.02, 0), material=gold, segments=12, rings=6)
        limb(f"shin_m_{s}", shin[s], 0.42, 0.06, 0.045, steel)
        foot[s] = sb.empty(f"foot_{s}", shin[s], loc=(0, 0, -0.44))
        sb.box(f"foot_m_{s}", foot[s], size=(0.1, 0.26, 0.08), loc=(0, -0.06, -0.025), material=dark, bevel=0.02)

    spine = sb.empty("spine", hips, loc=(0, 0, 0.1))
    sb.box("abdomen", spine, size=(0.3, 0.2, 0.24), loc=(0, 0, 0.1), material=dark, bevel=0.03, taper=(1.15, 1.1))
    chest = sb.empty("chest", spine, loc=(0, 0, 0.24))
    sb.box("cuirass", chest, size=(0.44, 0.28, 0.34), loc=(0, 0, 0.14), material=steel, bevel=0.05, taper=(1.12, 1.05))
    sb.box("cuirass_trim", chest, size=(0.06, 0.03, 0.3), loc=(0, -0.145, 0.14), material=gold, bevel=0.01)
    # tabard front panel hangs from the belt (follow-through chain)
    tab = [sb.empty("tabard_0", hips, loc=(0, -0.13, 0.04))]
    for i in range(1, 4):
        tab.append(sb.empty(f"tabard_{i}", tab[-1], loc=(0, 0, -0.17)))
    for i, t in enumerate(tab[:3]):
        sb.box(f"tabard_m{i}", t, size=(0.24 - i * 0.02, 0.02, 0.18), loc=(0, 0, -0.085), material=cloth, bevel=0.005)

    neck = sb.empty("neck", chest, loc=(0, 0, 0.32))
    head = sb.empty("head", neck, loc=(0, 0, 0.06))
    sb.sphere("helm", head, 0.15, loc=(0, 0, 0.12), scale=(0.95, 1.05, 1.2), material=steel, segments=16, rings=10)
    sb.box("visor", head, size=(0.2, 0.06, 0.07), loc=(0, -0.13, 0.12), material=dark, bevel=0.015)
    sb.box("eyes", head, size=(0.14, 0.02, 0.018), loc=(0, -0.165, 0.13), material=glow, bevel=0.0)
    sb.box("crest", head, size=(0.03, 0.26, 0.06), loc=(0, 0.0, 0.3), material=gold, bevel=0.01)
    # plume (overlap chain driven by the head, negative gain = drag)
    plume = [sb.empty("plume_0", head, loc=(0, 0.1, 0.3), rot=(-60, 0, 0))]
    for i in range(1, 4):
        plume.append(sb.empty(f"plume_{i}", plume[-1], loc=(0, 0, 0.11), rot=(-12, 0, 0)))
    for i, p in enumerate(plume[:3]):
        sb.cylinder(f"plume_m{i}", p, r1=0.045 - i * 0.01, r2=0.035 - i * 0.01, depth=0.12, material=cloth, segments=8)

    arm, fore, hand = {}, {}, {}
    for s, x in (("L", 1), ("R", -1)):
        arm[s] = sb.empty(f"arm_{s}", chest, loc=(x * 0.27, 0, 0.26), rot=(0, -x * 6, 0))
        sb.sphere(f"pauldron_{s}", arm[s], 0.12, loc=(x * 0.02, 0, 0.02), scale=(1.1, 1.0, 0.8), material=steel,
                  segments=14, rings=8)
        limb(f"upper_m_{s}", arm[s], 0.28, 0.055, 0.05, dark)
        fore[s] = sb.empty(f"fore_{s}", arm[s], loc=(0, 0, -0.3), rot=(-10, 0, 0))
        limb(f"fore_m_{s}", fore[s], 0.26, 0.055, 0.045, steel)
        hand[s] = sb.empty(f"hand_{s}", fore[s], loc=(0, 0, -0.28))
        sb.sphere(f"gauntlet_{s}", hand[s], 0.05, loc=(0, 0, -0.03), material=dark, segments=10, rings=6)
    sword = sb.empty("sword", hand["R"], loc=(0, 0, -0.04), rot=(80, 0, 0))
    sb.cylinder("grip", sword, r1=0.018, depth=0.2, loc=(0, 0, -0.08), material=dark, segments=8)
    sb.box("guard", sword, size=(0.24, 0.04, 0.035), loc=(0, 0, 0.12), material=gold, bevel=0.01)
    sb.blade("blade", sword, length=0.95, width=0.045, thickness=0.008, loc=(0, 0, 0.13), rot=(0, 90, 0),
             material=steel)
    shield = sb.empty("shield", fore["L"], loc=(0.08, -0.02, -0.16))
    sb.box("shield_m", shield, size=(0.04, 0.42, 0.56), loc=(0, 0, -0.04), rot=(180, 0, 0), material=steel,
           bevel=0.02, taper=(1.0, 0.35))
    sb.box("shield_boss", shield, size=(0.05, 0.08, 0.1), loc=(0.02, 0, 0.04), material=gold, bevel=0.02)

    # cape: 5 links off the back of the chest (physics follow-through)
    cape = [sb.empty("cape_0", chest, loc=(0, 0.15, 0.27), rot=(-6, 0, 0))]
    for i in range(1, 6):
        cape.append(sb.empty(f"cape_{i}", cape[-1], loc=(0, 0, -0.24)))
    for i, cj in enumerate(cape[:5]):
        sb.box(f"cape_m{i}", cj, size=(0.5 + i * 0.05, 0.025, 0.25), loc=(0, 0, -0.12), material=cloth, bevel=0.006)

    # wings: shoulder -> mid -> tip, 4 feathers each on mid and tip (rest = half spread)
    feathers = []
    fold_feathers = {}
    for s, x in (("L", 1), ("R", -1)):
        w0 = sb.empty(f"wing_{s}", chest, loc=(x * 0.1, 0.16, 0.24), rot=(0, -x * 20, x * 15))
        limb(f"wing_bone0_{s}", w0, 0.42, 0.03, 0.022, dark).rotation_euler = (0, x * 1.5708, 0)
        w1 = sb.empty(f"wing_mid_{s}", w0, loc=(x * 0.42, 0, 0), rot=(0, x * 10, 0))
        limb(f"wing_bone1_{s}", w1, 0.4, 0.022, 0.016, dark).rotation_euler = (0, x * 1.5708, 0)
        w2 = sb.empty(f"wing_tip_{s}", w1, loc=(x * 0.4, 0, 0))
        limb(f"wing_bone2_{s}", w2, 0.3, 0.016, 0.008, dark).rotation_euler = (0, x * 1.5708, 0)
        for seg, (wj, n, ln) in enumerate(((w0, 3, 0.5), (w1, 4, 0.7), (w2, 4, 0.85))):
            for k in range(n):
                fj = sb.empty(f"feather_{seg}{k}_{s}", wj, loc=(x * (0.06 + k * 0.1), 0.01, 0),
                              rot=(0, x * (-5 - seg * 18 - k * 8), 0))
                sb.blade(f"feather_m{seg}{k}_{s}", fj, length=ln - k * 0.03, width=0.06, thickness=0.006,
                         rot=(180, 0, 0), material=feather, curve=0.05)
                if s == "L":
                    feathers.append((fj, (seg * 4 + k) / 10.0))
                    fold_feathers[fj] = {"rot": (0, (5 + seg * 18 + k * 8) * 0.9, 0)}

    # slash arc (snapped on with a CONSTANT key at the impact frame)
    slash = sb.empty("slash", body, loc=(-0.3, -0.2, 1.3), rot=(0, 0, 105))
    arc = [(math.cos(math.radians(a)) * 1.15, 0, math.sin(math.radians(a)) * 1.15) for a in range(50, 231, 10)]
    sb.ptube("slash_m", slash, arc, [0.004 + 0.035 * math.sin(math.pi * i / (len(arc) - 1)) for i in range(len(arc))],
             sides=4, material=slash_m)

    ALL = A.joints(root)
    WL = [sb_obj for sb_obj in (bpy_get("wing_L"), bpy_get("wing_mid_L"), bpy_get("wing_tip_L"))]
    rig = {"hips": hips, "spine": spine, "chest": chest, "head": head, "thigh": (thigh["L"], thigh["R"]),
           "shin": (shin["L"], shin["R"]), "foot": (foot["L"], foot["R"]), "arm": (arm["L"], arm["R"]),
           "fore": (fore["L"], fore["R"])}
    WING_FOLD = {WL[0]: {"rot": (0, 50, 62)}, WL[1]: {"rot": (0, -6, 22)}, WL[2]: {"rot": (0, 4, 14)},
                 **fold_feathers}
    HIDE = {"scale": (0.001, 0.001, 0.001)}

    def secondary(c, cape_freq=2.0, wind=None, floor=None):
        A.follow_through(c, cape, freq=cape_freq, damping=0.14, gravity=6.0, falloff=0.85, wind=wind, floor=floor)
        A.follow_through(c, tab, freq=3.0, damping=0.2, gravity=6.0, falloff=0.8, floor=floor)
        A.overlap(c, plume, source=head, delay=2.5, decay=0.9, gain=1.0)    # plume drags behind the head (drag mode)

    def fold_wings(c):
        c.pose(0, WING_FOLD, mirror=True)          # single key = constant pose, mirrored to R

    # ---------------------------------------------------------------- idle (loop)
    c = A.Clip("idle", 72, joints=ALL)
    fold_wings(c)
    c.key(slash, 0, **HIDE)
    c.pose(0, {arm["R"]: {"rot": (-12, 0, 0)}, fore["R"]: {"rot": (-25, 0, 0)}, arm["L"]: {"rot": (-8, 0, 0)},
               fore["L"]: {"rot": (-40, 0, 0)}, spine: {"rot": (3, 0, 0)}})
    A.breathe(c, chest, amp=2.0, rise=0.008, swell=0.015, cycles=2, shoulders=[arm["L"], arm["R"]], head=head)
    c.add(hips, lambda f: (0.018 * A.wave(c, f), 0, -0.006 * abs(A.wave(c, f))), "loc")   # weight shift
    c.add(hips, lambda f: (0, 2.0 * A.wave(c, f), 0), "rot")
    A.noise(c, head, rot=(3, 5, 2), freq=0.4, seed=1)
    A.noise(c, WL[1], rot=(0, 3, 4), freq=0.5, seed=2)
    c.mirror(WL[1], phase=0.5)                       # right wing = mirrored left noise, half a cycle later
    A.noise(c, arm["R"], rot=(2, 0, 2), freq=0.3, seed=3)
    secondary(c)
    c.bake()

    # ---------------------------------------------------------------- walk (loop)
    c = A.Clip("walk", 32, joints=ALL)
    fold_wings(c)
    c.key(slash, 0, **HIDE)
    A.walk(c, rig, stride=24, knee=60, arm=18, elbow=20, lean=7, heavy=0.4, twist=9)
    c.add(arm["R"], lambda f: (-8, 0, 0), "rot")    # sword arm carried a bit forward
    A.breathe(c, chest, amp=0.8, cycles=1)
    secondary(c, cape_freq=1.8)
    c.bake()
    print("WALK speed m/s =", round(A.stride_speed(0.9, 24, 32), 2))

    # ---------------------------------------------------------------- fly (loop)
    c = A.Clip("fly", 24, joints=ALL)
    c.key(slash, 0, **HIDE)
    A.wing_beat(c, WL, amp=42, bias=-4, down=0.36, lag=0.08, flex=36, sweep=22, feathers=feathers, spread=10,
                fold=10, body=hips, lift=0.07, pitch=4)
    legs = {thigh["L"]: {"rot": (-18, 0, -4)}, shin["L"]: {"rot": (38, 0, 0)}, foot["L"]: {"rot": (35, 0, 0)},
            spine: {"rot": (12, 0, 0)}, arm["R"]: {"rot": (-30, 0, 10)}, fore["R"]: {"rot": (-30, 0, 0)},
            arm["L"]: {"rot": (-20, 0, 0)}, fore["L"]: {"rot": (-50, 0, 0)}}
    c.pose(0, legs, mirror=True)
    c.key(thigh["R"], 0, rot=(-6, 0, 4))           # explicit override keeps legs asymmetric
    c.add(thigh["L"], lambda f: (6 * A.wave(c, f, offset=-0.2), 0, 0), "rot")   # dangling legs trail the lift
    c.add(thigh["R"], lambda f: (5 * A.wave(c, f, offset=-0.25), 0, 0), "rot")
    A.overlap(c, [thigh["L"], shin["L"], foot["L"]], delay=2, decay=0.9, gain=1.2)
    A.overlap(c, [thigh["R"], shin["R"], foot["R"]], delay=2, decay=0.9, gain=1.2)
    secondary(c, cape_freq=1.6, wind=(0, 6.0, 0))
    c.bake()

    # ---------------------------------------------------------------- attack (one-shot)
    c = A.Clip("attack", 44, joints=ALL)
    fold_wings(c)
    antic = {arm["R"]: {"rot": (-165, 0, 25)}, fore["R"]: {"rot": (-70, 0, 0)}, chest: {"rot": (-10, 4, -28)},
             spine: {"rot": (-6, 0, -8)}, hips: {"loc": (0, 0.06, -0.06)}, head: {"rot": (6, 0, 18)},
             arm["L"]: {"rot": (-40, 0, -25)}, fore["L"]: {"rot": (-50, 0, 0)},
             thigh["L"]: {"rot": (-12, 0, 0)}, shin["L"]: {"rot": (18, 0, 0)}, thigh["R"]: {"rot": (8, 0, 0)},
             shin["R"]: {"rot": (16, 0, 0)}, foot["L"]: {"rot": (-6, 0, 0)}, foot["R"]: {"rot": (-24, 0, 0)}}
    strike = {arm["R"]: {"rot": (-35, 0, 12)}, fore["R"]: {"rot": (-8, 0, 0)}, chest: {"rot": (22, -4, 30)},
              spine: {"rot": (14, 0, 8)}, hips: {"loc": (0, -0.16, -0.16)}, head: {"rot": (-14, 0, -16)},
              arm["L"]: {"rot": (30, 0, -30)}, fore["L"]: {"rot": (-30, 0, 0)},
              thigh["L"]: {"rot": (-42, 0, 0)}, shin["L"]: {"rot": (48, 0, 0)}, foot["L"]: {"rot": (-6, 0, 0)},
              thigh["R"]: {"rot": (28, 0, 0)}, shin["R"]: {"rot": (22, 0, 0)}, foot["R"]: {"rot": (-50, 0, 0)}}
    follow = {j: {k: tuple(x * 0.92 for x in v) for k, v in d.items()} for j, d in strike.items()}
    ev = A.attack(c, {"antic": antic, "strike": strike, "follow": follow}, start=0, antic=12, antic_hold=5,
                  strike=3, hold=5, recover=16, overshoot=0.12, push=0.1)
    A.jitter(c, arm["R"], rot=(1.5, 1.0, 1.5), start=12, end=17)          # strain in the held windup
    imp = ev["impact"]
    c.key(slash, 0, ease="constant", **HIDE)
    c.key(slash, imp - 1, ease="constant", scale=(1, 1, 1))             # snap ON (constant)
    c.key(slash, imp + 4, ease="constant", **HIDE)                      # snap OFF
    secondary(c, cape_freq=2.2)
    c.bake()
    print("ATTACK impact frame", imp)

    # ---------------------------------------------------------------- hit (one-shot)
    c = A.Clip("hit", 20, joints=ALL)
    fold_wings(c)
    c.key(slash, 0, **HIDE)
    A.hit_react(c, {hips: {"loc": (0, 0.07, -0.03), "rot": (-6, 0, 0)}, spine: {"rot": (-10, 0, 4)},
                    chest: {"rot": (-14, 3, 8), "scale": (1.03, 1.03, 0.96)}, head: {"rot": (-18, 0, -10)},
                    arm["L"]: {"rot": (-25, 0, -20)}, arm["R"]: {"rot": (-15, 0, 25)},
                    WL[1]: {"rot": (0, -20, -30)}},
                start=0, rise=2, settle=13, wobble=1.0, stagger=1.0)
    secondary(c, cape_freq=2.4)
    c.bake()

    # ---------------------------------------------------------------- death (one-shot)
    c = A.Clip("death", 64, joints=ALL)
    fold_wings(c)
    c.key(slash, 0, **HIDE)
    buckle = {hips: {"loc": (0, 0.04, -0.2)}, thigh["L"]: {"rot": (-40, 0, 0)}, shin["L"]: {"rot": (70, 0, 0)},
              thigh["R"]: {"rot": (-25, 0, 0)}, shin["R"]: {"rot": (55, 0, 0)}, spine: {"rot": (18, 0, 0)},
              head: {"rot": (25, 0, 0)}, arm["L"]: {"rot": (-10, 0, 0)}, arm["R"]: {"rot": (-20, 0, 0)}}
    limp = {hips: {"loc": (0, 0, -0.12)}, thigh["L"]: {"rot": (-15, 0, 8)}, shin["L"]: {"rot": (20, 0, 0)},
            thigh["R"]: {"rot": (-5, 0, -5)}, shin["R"]: {"rot": (8, 0, 0)}, spine: {"rot": (-6, 0, 0)},
            head: {"rot": (-10, 0, 35)}, arm["L"]: {"rot": (-30, -70, 0)}, arm["R"]: {"rot": (-50, 60, 0)},
            fore["L"]: {"rot": (-20, 0, 0)}, fore["R"]: {"rot": (-10, 0, 0)}}
    imp = A.death(c, body, fall=(-84, 0, 6), drop=(0, 0.25, 0.16), stagger=7, buckle=10, topple=11, bounce=0.06,
            recoil={chest: {"rot": (-12, 0, 6)}, head: {"rot": (-16, 0, 0)}}, buckle_pose=buckle, limp_pose=limp)
    # wings: keep folded until the fall, then flop open onto the ground (back_out overshoot), mirrored
    c.pose(imp - 6, WING_FOLD, mirror=True, ease="quad_in")
    c.pose(imp + 4, {WL[0]: {"rot": (0, 8, 5)}, WL[1]: {"rot": (0, 10, 15)}, WL[2]: {"rot": (0, 8, 0)},
                     **{fj: {"rot": (0, 0, 0)} for fj in fold_feathers}}, mirror=True, ease="back_out:2.0")
    secondary(c, cape_freq=2.6, floor=0.03)     # cape/tabard collide with the ground
    c.bake()
    return root


def bpy_get(name):
    import bpy
    return bpy.data.objects[name]
