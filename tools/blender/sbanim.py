"""SINBOUND animation library (on top of sb.anim). See tools/blender/ANIMATION.md for a guide.

Core idea: a Clip holds, per joint, keyed OFFSET tracks (relative to the joint's rest transform)
with a per-key ease, plus additive procedural layers. clip.bake() samples everything per frame
and hands sb.anim-compatible key dicts to sb.anim(), so output goes through the normal NLA ->
glTF -> Godot pipeline (one NLA track per animation name).

    import sb, sbanim as A
    c = A.Clip("attack", 40)
    c.key(arm, 0)                                   # rest
    c.key(arm, 12, rot=(-120, 0, 20), ease="quad_in")    # slow anticipation, accelerates into the strike
    ...
    A.breathe(c, chest); A.noise(c, head, rot=(2, 3, 1))
    c.bake()

Units: rot = degrees (Euler XYZ offset added to rest), loc = meters (offset), scale = multiplier.
Axes (sb convention, character faces Blender -Y, +Z up), for a joint whose rest rotation is ~0:
    rot X +  : a limb hanging DOWN swings BACK; an upward chain (spine/neck) leans FORWARD;
               a foot pointing forward tips its toe DOWN.
    rot Z +  : yaw to the character's left... (+X side moves back).   rot Y + : +X side tips down.
Mirroring L<->R across X:  rot (x, -y, -z), loc (-x, y, z), scale unchanged.
"""
import math
import bpy
from mathutils import Vector, Euler, Quaternion, Matrix, noise as _noise

import sb

FPS = 30
LOOP_NAMES = ("idle", "walk", "run", "fly", "hover", "loop")

# =========================================================================== easing
# An ease belongs to the segment LEAVING a key (key k -> key k+1), like Blender's interpolation.
#   "smooth"   auto-clamped cubic spline through keys (Blender default feel, no overshoot)
#   "spline"   unclamped Catmull-Rom (may overshoot slightly; fluid arcs)
#   "linear", "constant" (= "step"/"snap": holds the value until the next key, then pops)
#   "<family>_<in|out|inout>[:param]"  families: sine quad cubic quart quint expo circ back elastic bounce
#   "in"/"out"/"inout" = cubic.   "_in" = slow start, hits the next key FAST (impacts, falls).
#   "_out" = fast start, settles into the next key (snaps, recoils).  back/elastic overshoot.
#   Parameters: "back_out:2.5" (overshoot amount, default 1.70158), "elastic_out:0.3" (period).
#   Or any callable u -> value (u in 0..1, value 0 at u=0 and 1 at u=1).


def _bounce_out(u):
    n, d = 7.5625, 2.75
    if u < 1 / d:
        return n * u * u
    if u < 2 / d:
        u -= 1.5 / d
        return n * u * u + 0.75
    if u < 2.5 / d:
        u -= 2.25 / d
        return n * u * u + 0.9375
    u -= 2.625 / d
    return n * u * u + 0.984375


def _base_in(fam, p):
    if fam == "sine":
        return lambda u: 1 - math.cos(u * math.pi / 2)
    if fam == "quad":
        return lambda u: u * u
    if fam == "cubic":
        return lambda u: u ** 3
    if fam == "quart":
        return lambda u: u ** 4
    if fam == "quint":
        return lambda u: u ** 5
    if fam == "expo":
        return lambda u: 0.0 if u <= 0 else 2 ** (10 * u - 10)
    if fam == "circ":
        return lambda u: 1 - math.sqrt(max(0.0, 1 - u * u))
    if fam == "back":
        s = 1.70158 if p is None else p
        return lambda u: (s + 1) * u ** 3 - s * u * u
    if fam == "elastic":
        per = 0.3 if p is None else p
        return lambda u: 0.0 if u <= 0 else (1.0 if u >= 1 else -(2 ** (10 * u - 10)) * math.sin(
            (10 * u - 10 - 2.5 * per) * 2 * math.pi / (10 * per)))
    if fam == "bounce":
        return lambda u: 1 - _bounce_out(1 - u)
    raise ValueError(f"unknown ease family {fam!r}")


_EASE_CACHE = {}


def ease_fn(spec):
    """Returns f(u) for an ease spec string (see above) or passes a callable through."""
    if callable(spec):
        return spec
    if spec in _EASE_CACHE:
        return _EASE_CACHE[spec]
    name, _, par = spec.partition(":")
    p = float(par) if par else None
    if name == "linear":
        f = lambda u: u
    elif name in ("constant", "step", "snap"):
        f = lambda u: 1.0 if u >= 1.0 else 0.0
    elif name in ("in", "out", "inout"):
        f = ease_fn("cubic_" + name)
    else:
        fam, _, kind = name.rpartition("_")
        fi = _base_in(fam, p)
        if kind == "in":
            f = fi
        elif kind == "out":
            f = lambda u, fi=fi: 1 - fi(1 - u)
        elif kind == "inout":
            f = lambda u, fi=fi: fi(2 * u) / 2 if u < 0.5 else 1 - fi(2 - 2 * u) / 2
        else:
            raise ValueError(f"unknown ease {spec!r}")
    _EASE_CACHE[spec] = f
    return f


def ease(spec, u):
    return ease_fn(spec)(min(1.0, max(0.0, u)))


# =========================================================================== small vector helpers

def _v3(v, default=0.0):
    if v is None:
        return (default, default, default)
    if isinstance(v, (int, float)):
        return (float(v), float(v), float(v))
    return (float(v[0]), float(v[1]), float(v[2]))


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def mirror_value(ch, v):
    """Mirror an offset across the X axis (L <-> R)."""
    if ch == "rot":
        return (v[0], -v[1], -v[2])
    if ch == "loc":
        return (-v[0], v[1], v[2])
    return v


_PAIRS = (("_L", "_R"), (".L", ".R"), ("_l", "_r"), ("Left", "Right"), ("left", "right"), ("L_", "R_"),
          ("l_", "r_"))


def other(obj):
    """The mirror-side object by name (arm_L <-> arm_R, wing.L <-> wing.R, LeftHand <-> RightHand)."""
    n = obj.name
    cands = []
    for a, b in _PAIRS:
        for x, y in ((a, b), (b, a)):
            if n.endswith(x):
                cands.append(n[: -len(x)] + y)
            if n.startswith(x):
                cands.append(y + n[len(x):])
            if x in n:
                cands.append(n.replace(x, y))
    for m in cands:
        if m != n and m in bpy.data.objects:
            return bpy.data.objects[m]
    return None


def joints(root, include_root=True):
    """All EMPTY joints under (and including) root - pass as Clip(joints=...) so every
    animation keys every joint (no stale transforms left over when Godot switches clips)."""
    out = [root] if include_root and root.type == "EMPTY" else []
    for o in sb.descendants(root):
        if o.type == "EMPTY":
            out.append(o)
    return out


# =========================================================================== keyed track

class Track:
    """Sorted keys {frame: (value3, ease)} evaluated with per-segment eases."""

    def __init__(self, default):
        self.default = default
        self.keys = {}

    def set(self, f, v, e):
        self.keys[float(f)] = (v, e)

    def _list(self, loop_len):
        ks = sorted(self.keys.items())
        pts = [(f, v, e) for f, (v, e) in ks]
        if loop_len is not None and pts:
            if pts[0][0] > 0:
                pts.insert(0, (0.0, pts[-1][1] if pts[-1][0] >= loop_len else pts[0][1], pts[-1][2]))
            if pts[-1][0] < loop_len:
                pts.append((float(loop_len), pts[0][1], pts[0][2]))
        return pts

    def value(self, f, loop_len=None):
        pts = self._list(loop_len)
        if not pts:
            return self.default
        if f <= pts[0][0]:
            return pts[0][1]
        if f >= pts[-1][0]:
            return pts[-1][1]
        k = 0
        while pts[k + 1][0] < f:
            k += 1
        f0, v0, e = pts[k]
        f1, v1, _ = pts[k + 1]
        h = f1 - f0
        u = (f - f0) / h
        if e in ("smooth", "spline"):
            m0 = self._tangent(pts, k, loop_len, e == "smooth")
            m1 = self._tangent(pts, k + 1, loop_len, e == "smooth")
            u2, u3 = u * u, u * u * u
            h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
            return tuple(h00 * v0[i] + h10 * h * m0[i] + h01 * v1[i] + h11 * h * m1[i] for i in range(3))
        w = ease_fn(e)(u)
        return _lerp(v0, v1, w)

    @staticmethod
    def _tangent(pts, k, loop_len, clamp):
        n = len(pts)
        f, v, _ = pts[k]
        if 0 < k < n - 1:
            fp, vp = pts[k - 1][0], pts[k - 1][1]
            fn, vn = pts[k + 1][0], pts[k + 1][1]
        elif loop_len is not None and n > 2:
            # seamless cycle: neighbours wrap around (last key == first key)
            if k == 0:
                fp, vp = pts[-2][0] - loop_len, pts[-2][1]
                fn, vn = pts[1][0], pts[1][1]
            else:
                fp, vp = pts[-2][0], pts[-2][1]
                fn, vn = pts[1][0] + loop_len, pts[1][1]
        else:
            return (0.0, 0.0, 0.0)  # ends of a one-shot clip ease in/out
        out = []
        for i in range(3):
            t = (vn[i] - vp[i]) / (fn - fp)
            if clamp and ((v[i] >= vp[i] and v[i] >= vn[i]) or (v[i] <= vp[i] and v[i] <= vn[i])):
                t = 0.0  # extreme -> flat tangent (no overshoot)
            out.append(t)
        return out


# =========================================================================== clip

_DEFAULT = {"rot": (0.0, 0.0, 0.0), "loc": (0.0, 0.0, 0.0), "scale": (1.0, 1.0, 1.0)}


class Clip:
    """One named animation. Build it from keys + layers, then bake().

    name    NLA track / Godot animation name ("idle", "walk", "attack", ...)
    frames  length in frames (30 fps). Loop clips: the frame `frames` equals frame 0.
    loop    default: name in LOOP_NAMES. Loop clips wrap keys with seamless tangents.
    joints  optional list of joints that are ALWAYS keyed (rest if untouched); use joints(root).
    """

    def __init__(self, name, frames, loop=None, joints=None):
        self.name = name
        self.frames = int(frames)
        self.loop = (name in LOOP_NAMES) if loop is None else loop
        self.tracks = {}      # (obj, ch) -> Track
        self.layers = {}      # (obj, ch) -> [fn(frame) -> 3-tuple]
        self.mirrors = {}     # dst -> (src, phase_frames)
        self.posts = []       # fn(clip, frames_list, vals)
        self.always = list(joints or [])
        self.events = {}      # name -> frame (impact frames etc., for gameplay timing reference)

    # ------------------------------------------------------------------ authoring
    def key(self, joint, frame, rot=None, loc=None, scale=None, ease="smooth"):
        """Key offsets (from rest) at `frame`. Channels left None are not keyed here.
        Calling key(j, f) with no channels keys rot+loc rest (offset 0)."""
        if rot is None and loc is None and scale is None:
            rot, loc = (0, 0, 0), (0, 0, 0)
        for ch, v in (("rot", rot), ("loc", loc), ("scale", scale)):
            if v is None:
                continue
            tr = self.tracks.get((joint, ch))
            if tr is None:
                tr = self.tracks[(joint, ch)] = Track(_DEFAULT[ch])
            tr.set(frame, _v3(v, 1.0 if ch == "scale" else 0.0), ease)
        return self

    def pose(self, frame, poses, ease="smooth", mirror=False):
        """Key many joints at once: poses = {joint: {"rot":..., "loc":..., "scale":...}}.
        mirror=True also keys the other() side with mirrored values (unless given explicitly)."""
        for j, ch in poses.items():
            self.key(j, frame, ch.get("rot"), ch.get("loc"), ch.get("scale"), ch.get("ease", ease))
            if mirror:
                o = other(j)
                if o is not None and o not in poses:
                    self.key(o, frame, *(None if ch.get(c) is None else mirror_value(c, _v3(ch.get(c), 1.0 if c == "scale" else 0.0))
                                         for c in ("rot", "loc", "scale")), ease=ch.get("ease", ease))
        return self

    def hold(self, frame_from, frame_to, joints=None, ease="smooth"):
        """Copies keyed values at frame_from to frame_to (a hold). Moving hold: use pose() with
        slightly pushed values instead."""
        for (j, ch), tr in list(self.tracks.items()):
            if joints is not None and j not in joints:
                continue
            tr.set(frame_to, tr.value(frame_from, self._ll()), ease)
        return self

    def add(self, joint, fn, ch="rot"):
        """Additive procedural layer: fn(frame) -> (x, y, z) offset (scale: added to multiplier)."""
        self.layers.setdefault((joint, ch), []).append(fn)
        return self

    def mirror(self, src, dst=None, phase=0.0):
        """dst copies src's whole motion mirrored across X, shifted by `phase` (fraction of the
        clip; 0.5 = half a cycle, for walk arms/legs). dst defaults to other(src)."""
        dst = dst or other(src)
        if dst is None:
            raise ValueError(f"no mirror joint for {src.name}")
        self.mirrors[dst] = (src, phase * self.frames)
        return dst

    def post(self, fn):
        """Post-bake process fn(clip, frames, vals) - vals[joint][ch] = list of 3-tuples."""
        self.posts.append(fn)
        return self

    # ------------------------------------------------------------------ evaluation
    def _ll(self):
        return self.frames if self.loop else None

    def wrap(self, f):
        if self.loop:
            return f % self.frames
        return min(max(f, 0.0), float(self.frames))

    def eval(self, joint, ch, f):
        """Offset of `joint` channel `ch` at frame f (before post-processes)."""
        f = self.wrap(f)
        tr = self.tracks.get((joint, ch))
        v = tr.value(f, self._ll()) if tr else _DEFAULT[ch]
        for fn in self.layers.get((joint, ch), ()):
            v = _add(v, _v3(fn(f)))
        m = self.mirrors.get(joint)
        if m is not None:
            src, ph = m
            sv = self.eval(src, ch, f + ph)
            if ch == "scale":
                v = (v[0] * sv[0], v[1] * sv[1], v[2] * sv[2])
            else:
                v = _add(v, mirror_value(ch, sv))
        return v

    def touched(self):
        js = []
        seen = set()
        for j in ([k[0] for k in self.tracks] + [k[0] for k in self.layers] + list(self.mirrors)
                  + self.always + [j for p in self.posts for j in getattr(p, "joints", ())]):
            if j.name not in seen:
                seen.add(j.name)
                js.append(j)
        return js

    def sample(self, step=1):
        fl = list(range(0, self.frames + 1, step))
        if fl[-1] != self.frames:
            fl.append(self.frames)
        vals = {}
        for j in self.touched():
            vals[j] = {ch: [self.eval(j, ch, f) for f in fl] for ch in ("rot", "loc", "scale")}
        for p in self.posts:
            p(self, fl, vals)
        if self.loop:  # exact seam
            for j in vals:
                for ch in vals[j]:
                    vals[j][ch][-1] = vals[j][ch][0]
        return fl, vals

    def bake(self, step=1):
        """Samples every `step` frames and calls sb.anim(name, keys). Every touched joint gets all
        three channels keyed (so switching clips in Godot never leaves stale offsets)."""
        fl, vals = self.sample(step)
        keys = {}
        for j, chs in vals.items():
            rr = [math.degrees(a) for a in j.rotation_euler]
            rl = list(j.location)
            rs = list(j.scale)
            kl = []
            for i, f in enumerate(fl):
                r, l, s = chs["rot"][i], chs["loc"][i], chs["scale"][i]
                kl.append((f, {"rot": tuple(rr[k] + r[k] for k in range(3)),
                               "loc": tuple(rl[k] + l[k] for k in range(3)),
                               "scale": tuple(rs[k] * s[k] for k in range(3))}))
            keys[j] = kl
        sb.anim(self.name, keys, self.frames)
        return keys


# =========================================================================== periodic helpers

def phase(c, f, cycles=1, offset=0.0):
    """Cycle phase 0..1 at frame f (cycles = whole cycles per clip so loops stay seamless)."""
    return ((f / c.frames) * cycles + offset) % 1.0


def wave(c, f, cycles=1, offset=0.0):
    """sin(2 pi phase)"""
    return math.sin(2 * math.pi * phase(c, f, cycles, offset))


def cyc(c, keys, ease="smooth"):
    """Periodic 1-D curve over phase 0..1 from keys [(phase, value[, ease]), ...] (wraps
    seamlessly). Returns g(phase) -> float.  Great for hand-shaping walk curves."""
    tr = Track((0.0, 0.0, 0.0))
    for k in keys:
        tr.set(k[0] * 1000.0, (k[1], 0.0, 0.0), k[2] if len(k) > 2 else ease)
    return lambda p: tr.value((p % 1.0) * 1000.0, 1000.0)[0]


# =========================================================================== procedural generators

def breathe(c, chest, amp=1.6, rise=0.006, swell=0.012, cycles=1, inhale=0.42, shoulders=(),
            head=None, belly=None, offset=0.0):
    """Breathing: inhale (fast-ish, `inhale` fraction of the cycle) then a longer exhale.
    Chest tilts back and rises + swells; shoulders lift; head counter-rotates to stay level."""
    g = cyc(c, [(0.0, 0.0), (inhale, 1.0), (1.0, 0.0)])
    if not c.loop and cycles == 1:
        cycles = max(1, round(c.frames / 90))

    def b(f):
        return g(phase(c, f, cycles, offset))

    c.add(chest, lambda f: (-amp * b(f), 0, 0), "rot")
    c.add(chest, lambda f: (0, 0, rise * b(f)), "loc")
    c.add(chest, lambda f: (swell * b(f), swell * 0.6 * b(f), swell * 0.4 * b(f)), "scale")
    for s in shoulders:
        c.add(s, lambda f: (0, 0, rise * 1.2 * b(f)), "loc")
    if head is not None:
        c.add(head, lambda f: (amp * 0.7 * b(f - 3), 0, 0), "rot")
    if belly is not None:
        c.add(belly, lambda f: (-swell * 0.5 * b(f), -swell * 0.5 * b(f), 0), "scale")


def noise(c, joint, rot=(0, 0, 0), loc=(0, 0, 0), freq=0.6, seed=0, octaves=2, start=None, end=None,
          fade=6):
    """Organic Perlin drift/jitter (loop-safe: loops sample noise around a circle).
    freq in Hz (0.3-1 = living drift, 6-12 = tremble/jitter). Optional start/end window w/ fade."""
    rot, loc = _v3(rot), _v3(loc)
    dur = c.frames / FPS
    if c.loop:
        cyc_n = max(1, round(freq * dur))
        rad = cyc_n / (2 * math.pi)  # circle radius in noise units = cycles per clip / 2pi
    base = Vector((seed * 17.31, seed * 3.77, seed * 9.13))

    def n1(f, ch):
        out = 0.0
        amp, fr = 1.0, 1.0
        for o in range(octaves):
            if c.loop:
                a = 2 * math.pi * f / c.frames
                p = Vector((math.cos(a) * rad * fr, math.sin(a) * rad * fr, ch * 5.3 + o * 11.1)) + base
            else:
                p = Vector((f / FPS * freq * fr, ch * 5.3 + o * 11.1, 0.37)) + base
            out += _noise.noise(p) * amp
            amp *= 0.5
            fr *= 2.03
        return out * 1.6

    def env(f):
        if start is None and end is None:
            return 1.0
        s = start or 0
        e = c.frames if end is None else end
        if f < s or f > e:
            return 0.0
        return min(1.0, (f - s) / max(fade, 1e-3), (e - f) / max(fade, 1e-3))

    if any(rot):
        c.add(joint, lambda f: tuple(rot[i] * n1(f, i) * env(f) for i in range(3)), "rot")
    if any(loc):
        c.add(joint, lambda f: tuple(loc[i] * n1(f, i + 3) * env(f) for i in range(3)), "loc")


def jitter(c, joint, rot=(1, 1, 1), freq=9.0, seed=0, start=None, end=None, fade=2):
    """High-frequency tremble (strain in a held anticipation, fear, rage)."""
    noise(c, joint, rot=rot, freq=freq, seed=seed, octaves=1, start=start, end=end, fade=fade)


def overlap(c, chain, source=None, delay=2.0, decay=0.85, gain=1.0, channels=("rot",), motion_only=True,
            mode=None):
    """Overlapping action along a chain (each link the parent of the next). Two modes:

    "wave" (default when source is None): you animate chain[0]; link i gets chain[0]'s motion
        delayed by i*delay frames, scaled by gain*decay^i -> the motion travels to the tip
        (tail wag, tentacle curl, whip). motion_only subtracts chain[0]'s static offset (loop:
        mean, one-shot: frame 0) so only MOTION propagates, not the pose.
    "drag" (default when `source` is given, e.g. the head for a plume, the hips for a loincloth):
        the chain lags behind the source's rotation: link i's world motion ~= source(f - i*delay)
        (gain 1 = full lag, decay softens toward the tip). Settles back to rest when the source
        holds, so it never leaves a stale offset. Source should be an ancestor of the chain.
    `delay`/`decay` may be per-link lists."""
    if mode is None:
        mode = "wave" if source is None else "drag"
    src = source or chain[0]
    links = chain[1:] if source is None else chain
    if mode == "drag":
        dsum = 0.0
        for i, j in enumerate(links, 1):
            d0 = dsum
            dsum += delay[i - 1] if isinstance(delay, (list, tuple)) else delay
            w = gain * (decay[i - 1] if isinstance(decay, (list, tuple)) else decay ** (i - 1))
            for ch in channels:
                c.add(j, (lambda f, ch=ch, d0=d0, d1=dsum, w=w:
                          _mul(_add(c.eval(src, ch, f - d1), _mul(c.eval(src, ch, f - d0), -1)), w)), ch)
        return
    base = {}

    def b(ch):
        if not motion_only:
            return _DEFAULT[ch]
        if ch not in base:
            if c.loop:
                n = max(8, c.frames)
                acc = (0.0, 0.0, 0.0)
                for i in range(n):
                    acc = _add(acc, c.eval(src, ch, c.frames * i / n))
                base[ch] = _mul(acc, 1.0 / n)
            else:
                base[ch] = c.eval(src, ch, 0)
        return base[ch]

    for i, j in enumerate(links, 1):
        d = sum((delay[k] if isinstance(delay, (list, tuple)) else delay) for k in range(i))
        w = gain * (decay[i - 1] if isinstance(decay, (list, tuple)) else decay ** i)
        for ch in channels:
            c.add(j, (lambda f, ch=ch, d=d, w=w: _mul(_add(c.eval(src, ch, f - d), _mul(b(ch), -1)), w)), ch)


def wing_beat(c, left, right=None, cycles=1, amp=48.0, bias=6.0, down=0.38, lag=0.07, flex=30.0,
              sweep=14.0, twist=10.0, feathers=None, spread=14.0, fold=8.0, body=None, lift=0.05,
              pitch=3.0, down_axis=(0, 1, 0), sweep_axis=(0, 0, 1), twist_axis=(1, 0, 0),
              feather_axis=(0, 0, 1)):
    """Flapping. left = chain of joints of the +X wing [shoulder, elbow, wrist...]; right = its
    mirror (default other() of each). Downstroke is FAST (`down` fraction of the cycle) and the
    wing is fully extended; the upstroke is slow, the outer links fold (flex) and sweep back,
    feathers close. Each link lags `lag` cycles behind its parent (whip-like tip).
    Axes are for the LEFT wing in its local frame: +down_axis rotation moves the wing down;
    +sweep_axis sweeps it back; feathers fan around feather_axis.
    feathers = [(joint, s), ...] for the left wing, s in 0..1 (inner..outer fan position).
    body (optional) rises after each downstroke by `lift` m and pitches `pitch` degrees."""
    stroke = cyc(c, [(0.0, -1.0, "sine_inout"), (down, 1.0, "sine_inout"), (1.0, -1.0)])
    openness = cyc(c, [(0.0, 1.0), (down * 0.85, 1.0), (down + (1 - down) * 0.3, 0.0), (0.92, 0.0),
                       (1.0, 1.0)])
    da, sa, ta, fa = (Vector(_v3(a)) for a in (down_axis, sweep_axis, twist_axis, feather_axis))
    right = right if right is not None else [other(j) for j in left]

    def link_fn(i):
        def f_(f):
            p = phase(c, f, cycles, -lag * i)
            s = stroke(p)
            o = openness(phase(c, f, cycles, -lag * i * 0.5))
            if i == 0:
                ang = (amp * s + bias)
                v = da * ang + ta * (twist * (1 - o) * -1.0)   # pitch feathering on the upstroke
            else:
                ang = amp * 0.35 * s * (0.8 ** (i - 1))
                v = da * ang + da * (flex * (1 - o) * (1.0 if i == 1 else -0.5)) + sa * (sweep * (1 - o))
            return tuple(v)
        return f_

    for i, j in enumerate(left):
        fn = link_fn(i)
        c.add(j, fn, "rot")
        if right and right[i] is not None:
            c.add(right[i], (lambda f, fn=fn: mirror_value("rot", fn(f))), "rot")
    for jl, s in (feathers or []):
        def ff(f, s=s):
            o = openness(phase(c, f, cycles, -lag))
            return tuple(fa * (s * (spread * o - fold * (1 - o))))
        c.add(jl, ff, "rot")
        jr = other(jl)
        if jr is not None:
            c.add(jr, (lambda f, ff=ff: mirror_value("rot", ff(f))), "rot")
    if body is not None:
        lift_c = cyc(c, [(0.0, -0.4), (down + 0.08, 1.0), (1.0, -0.4)])
        c.add(body, lambda f: (0, 0, lift * lift_c(phase(c, f, cycles, 0))), "loc")
        c.add(body, lambda f: (pitch * stroke(phase(c, f, cycles, -0.12)), 0, 0), "rot")


def stride_speed(leg_len, stride=26.0, frames=32, cycles=1, stance=0.6):
    """Ground speed (m/s) that keeps planted feet from skating for a walk() with these params:
    set the enemy's move speed to this (or pick frames from the speed)."""
    reach = leg_len * (math.sin(math.radians(stride)) + math.sin(math.radians(stride * 0.8)))
    return reach / (stance * frames / cycles / FPS)


def walk(c, rig, cycles=1, stride=26.0, knee=58.0, load=12.0, stance=0.6, lift=None, bob=0.0,
         auto_bob=True, sway=0.022, hip_roll=4.0, hip_yaw=7.0, twist=8.0, lean=6.0, arm=22.0,
         elbow=14.0, elbow_swing=16.0, arm_out=3.0, head_stab=0.75, heel=14.0, toe_off=22.0,
         heavy=0.0, offset=0.0):
    """Biped walk cycle generator (in place; the game moves the root).

    rig = {"hips": j, "spine": j?, "chest": j?, "head": j?, "thigh": (L, R), "shin": (L, R),
           "foot": (L, R)?, "arm": (L, R)?, "fore": (L, R)?}   (L = +X side)
    Contact of the LEFT foot at phase 0 (+offset), right at 0.5. Per leg:
      stance (`stance` fraction): thigh sweeps back linearly (foot planted), knee absorbs `load`
        right after contact, foot kept flat (heel strike `heel` -> flat -> heel-off -> `toe_off`).
      swing: knee folds to `knee` early in the swing then extends, thigh swings forward eased.
    auto_bob computes the hip height from the leg angles so the lowest foot stays on the ground
    (classic down-at-contact, up-at-passing). `bob` adds extra. `heavy` 0..1 = more sink/lean/lag.
    Torso counter-rotates (twist), arms swing opposite to legs with lag, head stabilises."""
    hips = rig["hips"]
    th, sh = rig["thigh"], rig["shin"]
    ft = rig.get("foot") or (None, None)
    ar = rig.get("arm") or (None, None)
    fo = rig.get("fore") or (None, None)
    spine, chest, head = rig.get("spine"), rig.get("chest"), rig.get("head")
    L1 = Vector(sh[0].location).length
    L2 = Vector(ft[0].location).length if ft[0] is not None else L1
    load = load * (1 + heavy)
    lean = lean * (1 + heavy * 0.6)
    S = stance
    back = stride * 0.8
    # thigh angle (forward +) over the leg's phase
    thigh_c = cyc(c, [(0.0, stride, "linear"), (S, -back, "sine_inout"), (S + (1 - S) * 0.8, stride * 1.06),
                      (1.0, stride)])
    knee_c = cyc(c, [(0.0, 3.0), (0.12 + heavy * 0.03, load), (0.32, 4.0), (S - 0.04, 10.0),
                     (S + (1 - S) * 0.35, knee), (0.93, 6.0), (1.0, 3.0)])
    # foot pitch relative to the ground (toe up +): heel strike, flat, heel-off, toe-off, swing
    foot_c = cyc(c, [(0.0, heel), (0.08, 0.0), (S * 0.7, 0.0), (S, -toe_off), (S + (1 - S) * 0.4, -6.0),
                     (0.95, heel * 0.9), (1.0, heel)])

    def ph(f, side):
        return phase(c, f, cycles, offset + (0.0 if side == 0 else 0.5))

    def leg_angles(f, side):
        p = ph(f, side)
        return thigh_c(p), knee_c(p)

    for side in (0, 1):
        sgn = 1 if side == 0 else -1

        def thigh_f(f, side=side):
            t, k = leg_angles(f, side)
            return (-t, 0, 0)

        def shin_f(f, side=side):
            t, k = leg_angles(f, side)
            return (k, 0, 0)

        def foot_f(f, side=side):
            t, k = leg_angles(f, side)
            # world foot pitch = thigh(x) + shin(x) + foot(x); want = -foot_c (toe up -> -X)
            want = -foot_c(ph(f, side))
            return (want - (-t + k), 0, 0)

        c.add(th[side], thigh_f, "rot")
        c.add(sh[side], shin_f, "rot")
        if ft[side] is not None:
            c.add(ft[side], foot_f, "rot")

    def leg_h(f, side):
        t, k = leg_angles(f, side)
        a1 = math.radians(t)
        a2 = math.radians(t - k)
        return L1 * math.cos(a1) + L2 * math.cos(a2)

    def hips_loc(f):
        p0 = phase(c, f, cycles, offset)
        z = 0.0
        if auto_bob:
            z = max(leg_h(f, 0), leg_h(f, 1)) - (L1 + L2)
        z += -bob * (0.5 + 0.5 * math.cos(4 * math.pi * p0)) * (1 + heavy)
        x = sway * math.sin(2 * math.pi * (p0 - 0.06))
        return (x, 0, z)

    c.add(hips, hips_loc, "loc")
    c.add(hips, lambda f: (0.0,
                           -hip_roll * math.sin(2 * math.pi * phase(c, f, cycles, offset)),
                           -hip_yaw * math.cos(2 * math.pi * phase(c, f, cycles, offset))), "rot")
    # legs must not inherit the pelvis roll fully (keeps knees from splaying): counter on thighs
    for side in (0, 1):
        c.add(th[side], lambda f: (0, hip_roll * math.sin(2 * math.pi * phase(c, f, cycles, offset)),
                                   hip_yaw * math.cos(2 * math.pi * phase(c, f, cycles, offset))), "rot")
    torso = chest or spine
    if spine is not None:
        c.add(spine, lambda f: (lean + 1.5 * (1 + heavy) * math.cos(4 * math.pi * phase(c, f, cycles, offset - 0.08)),
                                0, 0), "rot")
    if torso is not None:
        def torso_f(f):
            p = phase(c, f, cycles, offset - 0.04)
            p0 = phase(c, f, cycles, offset)
            # cancel the inherited pelvis yaw/roll, then counter-rotate against it
            return (0, hip_roll * 0.7 * math.sin(2 * math.pi * p),
                    hip_yaw * math.cos(2 * math.pi * p0) + twist * math.cos(2 * math.pi * p))
        c.add(torso, torso_f, "rot")
    if head is not None:
        def head_f(f):
            p = phase(c, f, cycles, offset - 0.1)
            yaw = -(twist * math.cos(2 * math.pi * p)) * head_stab
            nod = -lean * head_stab * 0.8 - 1.2 * math.cos(4 * math.pi * p)
            return (nod, -hip_roll * 0.5 * head_stab * math.sin(2 * math.pi * p), yaw)
        c.add(head, head_f, "rot")
    for side in (0, 1):
        sgn = 1 if side == 0 else -1
        if ar[side] is not None:
            def arm_f(f, side=side, sgn=sgn):
                # arm opposite to the same-side leg, lagging a little (drag)
                p = phase(c, f, cycles, offset + (0.0 if side == 0 else 0.5) - 0.06 - heavy * 0.04)
                fwd = -arm * math.cos(2 * math.pi * p)
                return (-fwd, -sgn * arm_out, 0)
            c.add(ar[side], arm_f, "rot")
        if fo[side] is not None:
            def fore_f(f, side=side):
                p = phase(c, f, cycles, offset + (0.0 if side == 0 else 0.5) - 0.12 - heavy * 0.05)
                fwd = -math.cos(2 * math.pi * p)
                return (-(elbow + elbow_swing * max(0.0, fwd)), 0, 0)
            c.add(fo[side], fore_f, "rot")


def attack(c, poses, start=0, antic=10, antic_hold=4, strike=4, hold=4, recover=14, overshoot=0.15,
           push=0.08, antic_ease="sine_inout", recover_ease="quad_inout"):
    """Anticipation -> strike -> impact hold -> recover, keyed on every joint in the poses.

    poses = {"antic": {joint: {"rot":..., "loc":...}}, "strike": {...},
             "follow": {...} optional pose reached at the END of the hold (follow-through)}
    Timeline (frames): start rest -(antic, slow ease)-> antic -(antic_hold: moving hold, pushes
    `push` further)-> -(strike frames, accelerating 'quad_in')-> strike pose * (1+overshoot)
    = IMPACT -(hold frames, tiny settle)-> follow/strike -(recover, ease)-> rest.
    Returns {"impact": frame, "end": frame} and records them in c.events."""
    A, S = poses.get("antic", {}), poses["strike"]
    F = poses.get("follow", None)
    js = list(dict.fromkeys(list(A) + list(S) + list(F or {})))
    f0 = start
    f1 = f0 + antic
    f2 = f1 + antic_hold
    f3 = f2 + strike
    f4 = f3 + hold
    f5 = f4 + recover

    def g(pose, j, ch, s=1.0):
        v = pose.get(j, {}).get(ch)
        if v is None:
            return _DEFAULT[ch] if ch != "scale" else (1, 1, 1)
        v = _v3(v, 1.0 if ch == "scale" else 0.0)
        if ch == "scale":
            return tuple(1 + (x - 1) * s for x in v)
        return _mul(v, s)

    for j in js:
        chans = [ch for ch in ("rot", "loc", "scale") if any(ch in p.get(j, {}) for p in (A, S, F or {}))]
        for ch in chans:
            kw = lambda v: {ch: v}  # noqa: E731
            c.key(j, f0, ease=antic_ease, **kw(g({}, j, ch)))
            c.key(j, f1, ease="sine_inout", **kw(g(A, j, ch)))
            c.key(j, f2, ease="quad_in", **kw(g(A, j, ch, 1 + push)))
            c.key(j, f3, ease="sine_out", **kw(g(S, j, ch, 1 + overshoot)))
            c.key(j, f4, ease=recover_ease, **kw(g(F, j, ch) if F is not None and j in F else g(S, j, ch)))
            c.key(j, f5, ease="smooth", **kw(g({}, j, ch)))
    c.events["impact"] = f3
    c.events["end"] = f5
    return {"impact": f3, "end": f5}


def _response(t, rise, settle, wobble):
    """0 -> 1 snap in `rise` frames, then decays back to 0 over ~settle frames with a wobble."""
    if t <= 0:
        return 0.0
    if t < rise:
        return ease("expo_out", t / rise)
    u = t - rise
    k = 4.0 / max(settle, 1e-3)
    return math.exp(-k * u) * math.cos(wobble * math.pi * u / max(settle, 1e-3) * 1.6)


def hit_react(c, peaks, start=0, rise=2.0, settle=14.0, wobble=1.0, stagger=1.5):
    """Recoil: each joint snaps to its peak offset in `rise` frames, then springs back with a
    damped wobble. peaks = {joint: {"rot":..., "loc":..., "scale":...}} in chain order (root
    first) - each entry starts `stagger` frames after the previous (overlap)."""
    for i, (j, ch) in enumerate(peaks.items()):
        t0 = start + i * stagger
        for name in ("rot", "loc", "scale"):
            if ch.get(name) is None:
                continue
            v = _v3(ch[name], 1.0 if name == "scale" else 0.0)
            if name == "scale":
                v = (v[0] - 1, v[1] - 1, v[2] - 1)
            c.add(j, (lambda f, v=v, t0=t0: _mul(v, _response(f - t0, rise, settle, wobble))), name)
    c.events["hit"] = start


def death(c, body, start=0, fall=(82, 0, 0), drop=(0, 0, 0), stagger=6, buckle=10, topple=12,
          bounce=0.07, recoil=None, buckle_pose=None, limp_pose=None):
    """Death: stagger (recoil away) -> knees buckle -> topple (accelerating, 'quad_in' like
    gravity) -> ground impact with 2 decaying bounces -> settle (limbs flop to limp_pose with
    overshoot). `body` must pivot at the ground (feet). fall = final body rotation offset
    (+X = face down forward, -X = onto its back, Y = sideways).
    recoil = {joint: offsets} during stagger; buckle_pose = {joint: offsets} reached at the end
    of the buckle and kept; limp_pose = {joint: offsets} flopped into at impact.
    Returns impact frame. Clip should be long enough (impact + ~20)."""
    fall = _v3(fall)
    drop = _v3(drop)
    f_st = start + stagger
    f_bk = f_st + buckle
    f_im = f_bk + topple
    c.key(body, start, rot=(0, 0, 0), loc=(0, 0, 0), ease="sine_out")
    c.key(body, f_st, rot=_mul(fall, -0.05), loc=(0, 0, 0), ease="sine_inout")
    c.key(body, f_bk, rot=_mul(fall, 0.12), loc=_mul(drop, 0.3), ease="quad_in")
    c.key(body, f_im, rot=fall, loc=drop, ease="quad_out")
    c.key(body, f_im + 3, rot=_mul(fall, 1 - bounce), loc=drop, ease="quad_in")
    c.key(body, f_im + 6, rot=fall, loc=drop, ease="quad_out")
    c.key(body, f_im + 8, rot=_mul(fall, 1 - bounce * 0.3), loc=drop, ease="quad_in")
    c.key(body, f_im + 10, rot=fall, loc=drop, ease="constant")
    if recoil:
        hit_react(c, recoil, start=start, rise=2, settle=stagger + buckle, wobble=0.5, stagger=1.0)
    allj = list(dict.fromkeys(list(buckle_pose or {}) + list(limp_pose or {})))
    for j in allj:
        bp = (buckle_pose or {}).get(j, {})
        lp = (limp_pose or {}).get(j, bp)
        for ch in ("rot", "loc"):
            b = _v3(bp.get(ch))
            l_ = _v3(lp.get(ch, bp.get(ch)))
            c.key(j, start, **{ch: (0, 0, 0)}, ease="sine_inout")
            c.key(j, f_st, **{ch: _mul(b, 0.2)}, ease="sine_in")
            c.key(j, f_bk, **{ch: b}, ease="smooth")
            c.key(j, f_im - 2, **{ch: _lerp(b, l_, 0.3)}, ease="back_out:2.2")
            c.key(j, f_im + 6, **{ch: l_}, ease="constant")
    c.events["impact"] = f_im
    return f_im


# =========================================================================== follow-through (physics)

def _basis(obj, r, l, s):
    rest_r = obj.rotation_euler
    e = Euler((rest_r[0] + math.radians(r[0]), rest_r[1] + math.radians(r[1]), rest_r[2] + math.radians(r[2])),
              rest_r.order)
    loc = Vector(obj.location) + Vector(l)
    sc = Vector((obj.scale[0] * s[0], obj.scale[1] * s[1], obj.scale[2] * s[2]))
    return Matrix.LocRotScale(loc, e.to_quaternion(), sc)


def follow_through(c, chain, freq=2.2, damping=0.18, gravity=5.0, falloff=0.75, tip=None,
                   max_angle=80.0, warmup=2, inertia=1.0, wind=None, floor=None):
    """Secondary motion for hanging/trailing chains (capes, tails, chains, hair, banners, tassels):
    a verlet particle chain pinned at chain[0], springing toward the keyed pose of each link
    (`freq` Hz, softer toward the tip by `falloff` per link), with `damping` (0..1 per frame),
    `gravity` (m/s^2) and `inertia` (1 = full drag from the body's motion). Results are written
    as rotation offsets on chain links, so it reacts to everything else in the clip (walk bob,
    attack swings, falls). Loop clips are pre-rolled `warmup` cycles so the seam is clean.
    freq/damping may be per-link lists. chain = [link0, link1, ...] (each the parent of the next).
    tip = local end vector of the last link (default: same as the last link's own offset).
    wind = (x, y, z) m/s^2 gentle constant force (banners).
    floor = world Z the particles can't sink below (capes on a corpse); None = no collision.
    Model root is assumed at the world origin (true in build/preview)."""
    chain = list(chain)
    n = len(chain)

    def per(v, i):
        return v[i] if isinstance(v, (list, tuple)) else v

    tip_v = Vector(tip) if tip is not None else Vector(chain[-1].location)

    def proc(clip, fl, vals):
        cache = {}

        def world(obj, i):
            key = (obj.name, i)
            if key in cache:
                return cache[key]
            if obj in vals:
                r, l, s = vals[obj]["rot"][i], vals[obj]["loc"][i], vals[obj]["scale"][i]
                m = _basis(obj, r, l, s)
            else:
                m = obj.matrix_basis.copy()
            if obj.parent is not None:
                m = world(obj.parent, i) @ obj.matrix_parent_inverse @ m
            cache[key] = m
            return m

        nf = len(fl)
        targets = []
        for i in range(nf):
            pts = [world(j, i).translation.copy() for j in chain]
            pts.append(world(chain[-1], i) @ tip_v)
            targets.append(pts)
        lens = [(targets[0][k + 1] - targets[0][k]).length for k in range(n)]
        g = Vector((0, 0, -gravity / (FPS * FPS)))
        wv = Vector(_v3(wind)) / (FPS * FPS) if wind else Vector((0, 0, 0))
        p = [v.copy() for v in targets[0]]
        prev = [v.copy() for v in p]
        out = [None] * nf
        rounds = (warmup + 1) if clip.loop else 1
        for rnd in range(rounds):
            for i in range(nf):
                dt = (fl[i] - fl[i - 1]) if i > 0 else 0  # loop: frame F == frame 0
                if dt > 0:
                    sub = max(2, int(dt * 3))
                    h = dt / sub
                    a0 = targets[i - 1] if i > 0 else targets[-1]
                    for s_ in range(1, sub + 1):
                        u = s_ / sub
                        tgt = [a0[k].lerp(targets[i][k], u) for k in range(n + 1)]
                        root_prev = p[0].copy()
                        p[0] = tgt[0]
                        for k in range(1, n + 1):
                            om = 2 * math.pi * per(freq, k - 1) * (falloff ** (k - 1)) / FPS
                            vel = (p[k] - prev[k]) * ((1.0 - per(damping, k - 1)) ** h)
                            if inertia < 1.0:
                                vel += (p[0] - root_prev) * (1 - inertia)
                            acc = g + wv + (tgt[k] - p[k]) * (om * om)
                            prev[k] = p[k].copy()
                            p[k] = p[k] + vel + acc * (h * h)
                        for _it in range(3):
                            for k in range(1, n + 1):
                                d = p[k] - p[k - 1]
                                dl = d.length
                                if dl > 1e-9:
                                    p[k] = p[k - 1] + d * (lens[k - 1] / dl)
                                if floor is not None and p[k].z < floor:
                                    p[k].z = floor
                                    prev[k] = prev[k].lerp(p[k], 0.5)  # ground friction
                if rnd == rounds - 1:
                    out[i] = [v.copy() for v in p]
        # convert particle chain -> local rotations, root to tip
        lim = math.radians(max_angle)
        prev_eul = {}
        for i in range(nf):
            pw = world(chain[0].parent, i).to_quaternion() if chain[0].parent else Quaternion()
            for k, j in enumerate(chain):
                r, l, s = vals[j]["rot"][i], vals[j]["loc"][i], vals[j]["scale"][i]
                ql = _basis(j, r, l, s).to_quaternion()
                bone = (chain[k + 1].location if k + 1 < n else tip_v)
                bone = Vector(bone).normalized()
                cw = (pw @ ql) @ bone
                dw = (out[i][k + 1] - out[i][k]).normalized()
                q = cw.rotation_difference(dw)
                ang = q.angle
                if ang > lim:
                    q = Quaternion(q.axis, lim)
                wq = q @ pw @ ql
                ql2 = pw.inverted() @ wq
                rest = j.rotation_euler
                e = ql2.to_euler(rest.order, prev_eul.get(j, rest))
                prev_eul[j] = e
                vals[j]["rot"][i] = tuple(math.degrees(e[a] - rest[a]) for a in range(3))
                pw = wq

    proc.joints = chain
    for j in chain:
        if j not in c.always:
            c.always.append(j)
    c.post(proc)


# =========================================================================== raw sb.anim helpers

def actions_for(name):
    """[(object, action)] for every NLA strip named `name` (made by sb.anim or Clip.bake)."""
    out = []
    for o in bpy.data.objects:
        ad = o.animation_data
        if ad is None:
            continue
        for t in ad.nla_tracks:
            if t.name == name:
                for s in t.strips:
                    if s.action is not None:
                        out.append((o, s.action))
    return out


def fcurves(action):
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


def interpolate(name, interpolation="BEZIER", easing="AUTO", objects=None):
    """Post-process a RAW sb.anim clip: set Blender interpolation on all its keys
    ('CONSTANT', 'LINEAR', 'BEZIER', 'SINE', 'QUAD', 'CUBIC', 'EXPO', 'BACK', 'ELASTIC', 'BOUNCE'...)
    and easing ('AUTO', 'EASE_IN', 'EASE_OUT', 'EASE_IN_OUT'). Export samples it per frame."""
    for o, a in actions_for(name):
        if objects is not None and o not in objects:
            continue
        for fc in fcurves(a):
            for kp in fc.keyframe_points:
                kp.interpolation = interpolation
                kp.easing = easing
            fc.update()


def make_cycle(klist, frames):
    """For raw sb.anim key lists: ensure the last key (at `frames`) equals the first."""
    klist = sorted(klist, key=lambda k: k[0])
    if klist[-1][0] != frames:
        klist.append((frames, dict(klist[0][1])))
    else:
        klist[-1] = (frames, dict(klist[0][1]))
    return klist


def cyclic(name):
    """Post-process a RAW sb.anim loop clip: Cycles modifier on every F-curve so Blender computes
    seamless (wrap-around) auto tangents at the loop point - no ease-stop hitch at the seam.
    (Clips made with Clip(loop=True) are already seamless.)"""
    for _o, a in actions_for(name):
        for fc in fcurves(a):
            if not any(m.type == "CYCLES" for m in fc.modifiers):
                fc.modifiers.new("CYCLES")
            for kp in fc.keyframe_points:
                kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
            fc.update()
