#!/usr/bin/env python3
"""
DemonCore procedural music generator (offline, owned by the music role).

Renders every music stem as a seamless-looping 16 kHz 16-bit WAV (all mono; a few dark loops at
11.025 kHz; under 25 MB in total) into
assets/audio/music/ and writes assets/audio/music/manifest.json, which the MusicManager
autoload (autoload/music_manager.gd) reads. No samples, no downloads: every sound is
synthesized here with numpy (additive oscillators, formant choirs, pipe organ, modal drums,
inharmonic bells, FFT convolution reverb).

Usage:
    python tools/music/gen_music.py                 # render every track
    python tools/music/gen_music.py boss title      # render only some tracks
Requires Python 3.9+ and numpy. A full render takes roughly a minute.

Seamless loops: every stem buffer is exactly one loop long and everything wraps around.
Notes that ring past the end fold onto the start, continuous drones/LFOs are snapped to an
integer number of cycles per loop, and reverb is a *circular* FFT convolution, so the tail of
the last bar lands on the first bar. The WAV therefore loops with no click and no gap.

Stems of one track all have the same length (sample-exact), so MusicManager can play them in
an AudioStreamSynchronized and fade layers in and out without them drifting apart.
"""
import json
import os
import struct
import sys
import time

import numpy as np

# 16 kHz mono keeps ~40 tracks inside the 25 MB repo budget (docs/team/music.md); the mixes
# are dark, so the 8 kHz bandwidth costs little.
SR = 16000
NYQ = 0.45 * SR  # highest partial we let through (keeps a margin under Nyquist)
TAU = 2.0 * np.pi
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "music")


# =========================================================================== basics

def mtof(m):
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)) + 1e-20))


def loudness(x):
    """Perceived-loudness proxy (like K-weighting): ignore sub-bass, favour presence/highs.
    Used to balance stems, so a boom-heavy drum stem does not get normalized into thinness and
    a shrieking choir stem does not end up too loud."""
    mono = x.mean(axis=0) if x.ndim == 2 else x
    X = np.fft.rfft(mono)
    f = np.fft.rfftfreq(len(mono), 1.0 / SR)
    g = 1.0 / np.sqrt(1.0 + (100.0 / np.maximum(f, 1e-3)) ** 4)  # 2nd-order high-pass at 100 Hz
    g *= 1.0 + 0.6 / (1.0 + (1500.0 / np.maximum(f, 1e-3)) ** 2)  # ~+4 dB shelf above 1.5 kHz
    return rms(np.fft.irfft(X * g, n=len(mono)))


def peak_norm(x, level=1.0):
    p = float(np.max(np.abs(x)))
    return x * (level / p) if p > 1e-9 else x


def note_env(dur, attack, release, n=None):
    """Hold envelope: sin^2 attack, flat until `dur`, cos^2 release after it."""
    n = n or int((dur + release) * SR)
    e = np.ones(n)
    na = max(1, min(n, int(attack * SR)))
    e[:na] = np.sin(0.5 * np.pi * np.arange(na) / na) ** 2
    hold = min(n, int(dur * SR))
    nr = n - hold
    if nr > 0:
        e[hold:] *= np.cos(0.5 * np.pi * np.arange(nr) / nr) ** 2
    return e


def fft_filter(x, lo=None, hi=None, order=2):
    """Zero-phase Butterworth-magnitude band/low/high-pass via FFT (circular)."""
    n = x.shape[-1]
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    g = np.ones_like(f)
    if hi:
        g /= np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo:
        g /= np.sqrt(1.0 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * g, n=n)


def phase_of(freq, n, rng, vib_rate=0.0, vib_depth=0.0, vib_delay=0.2, cents=None):
    """Integrated phase of a (vibrato'd, drifting) oscillator. `cents` is an extra pitch curve."""
    t = np.arange(n) / SR
    c = np.zeros(n) if cents is None else cents.copy()
    if vib_depth:
        onset = np.clip((t - vib_delay) / 0.5, 0.0, 1.0)
        c += vib_depth * onset * np.sin(TAU * vib_rate * t + rng.uniform(0, TAU))
    f = freq * 2.0 ** (c / 1200.0)
    return TAU * np.cumsum(f) / SR


def harmonic_sum(ph, f, amps, rng):
    """sum_k amps[k] * sin(k * phase). amps entries may be scalars or per-sample arrays."""
    out = np.zeros(len(ph))
    for k, a in enumerate(amps, start=1):
        if k * f > NYQ:
            break
        out += a * np.sin(k * ph + rng.uniform(0, TAU))
    return out


def stereo(sig, pan=0.0):
    """Mono -> constant-power panned stereo (2, n). Stereo input is passed through."""
    if sig.ndim == 2:
        return sig
    a = (np.clip(pan, -1, 1) + 1.0) * np.pi / 4.0
    return np.vstack([sig * np.cos(a), sig * np.sin(a)]) * np.sqrt(2.0)


def soft_limit(x, threshold):
    """Linear below `threshold`, tanh-knee above it; output never exceeds 1.0."""
    a = np.abs(x)
    over = a > threshold
    y = x.copy()
    k = 1.0 - threshold
    y[over] = np.sign(x[over]) * (threshold + k * np.tanh((a[over] - threshold) / k))
    return y


def drive(x, amount):
    """tanh saturation that keeps unity gain for small signals."""
    return np.tanh(x * amount) / amount


# =========================================================================== reverb

def make_ir(t60, predelay=0.03, bright=0.5, seed=1):
    """Stereo IR: decorrelated noise with frequency-dependent decay (lows ring longer)."""
    rng = np.random.default_rng(seed)
    n = int((t60 * 1.05 + predelay) * SR)
    t = np.arange(n) / SR
    ir = np.zeros((2, n))
    bands = [(None, 250, t60 * 1.2), (250, 1800, t60), (1800, None, t60 * (0.25 + 0.4 * bright))]
    for lo, hi, T in bands:
        noise = fft_filter(rng.standard_normal((2, n)), lo, hi)
        ir += noise * 10.0 ** (-3.0 * t / T)
    # Soft onset (diffuse build-up) and predelay.
    ir *= np.clip(t / 0.06, 0, 1) ** 2
    pd = int(predelay * SR)
    ir = np.concatenate([np.zeros((2, pd)), ir[:, : n - pd]], axis=1)
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    return ir


def circ_conv(x, ir):
    L = x.shape[1]
    out = np.empty_like(x)
    for c in range(2):
        h = np.zeros(L)
        m = min(L, ir.shape[1])
        h[:m] = ir[c, :m]
        out[c] = np.fft.irfft(np.fft.rfft(x[c]) * np.fft.rfft(h), n=L)
    return out


IR_CATHEDRAL = make_ir(4.6, 0.045, 0.35, seed=7)
IR_HALL = make_ir(2.6, 0.03, 0.5, seed=8)
IR_ROOM = make_ir(1.2, 0.015, 0.6, seed=9)


# =========================================================================== instruments
# Every instrument returns a mono numpy array (peak ~1) unless noted; arrangement code sets
# levels with `gain`.

# Formant tables (Hz, dB, bandwidth Hz) for a low (bass/tenor) and high (alto/soprano) choir.
FORM_LO = {
    "a": ([600, 1040, 2250, 2450, 2750], [0, -7, -9, -9, -20], [60, 70, 110, 120, 130]),
    "e": ([400, 1620, 2400, 2800, 3100], [0, -12, -9, -12, -18], [40, 80, 100, 120, 120]),
    "i": ([250, 1750, 2600, 3050, 3340], [0, -30, -16, -22, -28], [60, 90, 100, 120, 120]),
    "o": ([400, 750, 2400, 2600, 2900], [0, -11, -21, -20, -40], [40, 80, 100, 120, 120]),
    "u": ([350, 600, 2400, 2675, 2950], [0, -20, -32, -28, -36], [40, 80, 100, 120, 120]),
}
FORM_HI = {
    "a": ([800, 1150, 2900, 3900, 4950], [0, -6, -32, -20, -50], [80, 90, 120, 130, 140]),
    "e": ([350, 2000, 2800, 3600, 4950], [0, -20, -15, -40, -56], [60, 100, 120, 150, 200]),
    "i": ([270, 2140, 2950, 3900, 4950], [0, -12, -26, -26, -44], [60, 90, 100, 120, 120]),
    "o": ([450, 800, 2830, 3800, 4950], [0, -11, -22, -22, -50], [70, 80, 100, 130, 135]),
    "u": ([325, 700, 2700, 3800, 4950], [0, -16, -35, -40, -60], [50, 60, 170, 180, 200]),
}


def formant_gain(freqs, vowel, high):
    F, A, B = (FORM_HI if high else FORM_LO)[vowel]
    g = np.zeros_like(freqs)
    for Fj, Aj, Bj in zip(F, A, B):
        # Bandwidths are widened: a choir's sparse harmonics would otherwise miss the peaks.
        g += 10.0 ** (Aj / 20.0) / (1.0 + ((freqs - Fj) / (Bj * 1.1)) ** 2)
    return g


def choir(midi, dur, rng, vowel="a", voices=4, attack=0.4, release=0.7, vib=16.0,
          corrupt=0.0, sag=0.0, slide=0.0, spread=0.7, breath=0.05):
    """Formant-synthesized choir section (stereo).

    corrupt: 0..1, tape-wow pitch warp + a ring-modulated tritone shadow (the "wrong" choir).
    sag:     cents the pitch droops over the note (tired/fallen angels).
    slide:   cents of a deliberate glissando over the note (screams use -700 or so).
    """
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    env = note_env(dur, attack, release, n)
    out = np.zeros((2, n))
    high = midi >= 58
    for _ in range(voices):
        det = rng.normal(0.0, 6.0 + corrupt * 16.0)
        f = mtof(midi) * 2.0 ** (det / 1200.0)
        cents = -sag * np.clip(t / max(dur, 0.1), 0, 1) + slide * np.clip(t / max(dur, 0.1), 0, 1) ** 1.5
        if corrupt:
            cents = cents + corrupt * 38.0 * np.sin(TAU * rng.uniform(0.25, 0.45) * t + rng.uniform(0, TAU))
        ph = phase_of(f, n, rng, rng.uniform(4.6, 5.8), vib * rng.uniform(0.7, 1.25), 0.25, cents)
        K = int(min(48, NYQ / f))
        k = np.arange(1, K + 1)
        amps = formant_gain(k * f, vowel, high) / k ** 0.6
        amps /= np.sqrt(np.sum(amps ** 2) * 2.0)
        sig = harmonic_sum(ph, f, amps, rng)
        sig *= 1.0 + 0.1 * np.sin(TAU * rng.uniform(0.2, 0.7) * t + rng.uniform(0, TAU))
        out += stereo(sig * env, rng.uniform(-spread, spread))
    out /= np.sqrt(voices)
    if breath:
        F = (FORM_HI if high else FORM_LO)[vowel][0]
        nz = fft_filter(rng.standard_normal(n), F[0] * 0.8, F[1] * 1.4)
        nz = nz / (rms(nz) + 1e-9) * 0.25 * breath
        out += stereo(nz * env, 0.0) * 0.7
    if corrupt:
        ring = np.sin(TAU * mtof(midi + 6) * t)
        out = out * (1.0 - 0.25 * corrupt) + out * ring * (0.35 * corrupt)
    return peak_norm(out)


ORGAN_PRINCIPAL = [(0.5, 0.35), (1, 1.0), (2, 0.55), (3, 0.18), (4, 0.3), (6, 0.08), (8, 0.1)]
ORGAN_FLUTE = [(1, 1.0), (2, 0.2), (3, 0.06), (4, 0.05)]
ORGAN_PLENUM = [(0.5, 0.7), (1, 1.0), (2, 0.8), (3, 0.45), (4, 0.6), (5, 0.25), (6, 0.35),
                (8, 0.35), (10, 0.15), (12, 0.15), (16, 0.1)]
ORGAN_REED = [(k, 1.0 / k ** 0.9) for k in range(1, 22)]


def organ(midi, dur, rng, stops=ORGAN_PRINCIPAL, attack=0.05, release=0.35, trem_rate=0.0,
          trem_depth=0.0, celeste=2.5, chiff=0.03):
    """Pipe organ: additive ranks (two slightly detuned ranks beat like a celeste)."""
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    f = mtof(midi)
    sig = np.zeros(n)
    for det in (0.0, celeste):
        ph = phase_of(f * 2.0 ** (det / 1200.0), n, rng)
        for r, a in stops:
            if r * f < NYQ:
                sig += a * np.sin(r * ph + rng.uniform(0, TAU))
                if r * f * 2 < NYQ and stops is not ORGAN_REED:
                    sig += 0.12 * a * np.sin(2 * r * ph + rng.uniform(0, TAU))
    if trem_depth:
        sig *= 1.0 - trem_depth * (0.5 + 0.5 * np.sin(TAU * trem_rate * t + rng.uniform(0, TAU)))
    if chiff:
        nz = fft_filter(rng.standard_normal(n), f * 1.5, f * 6.0)
        sig += nz / (rms(nz) + 1e-9) * chiff * np.exp(-t / 0.035) * rms(sig)
    return peak_norm(sig * note_env(dur, attack, release, n))


def strings(midi, dur, rng, voices=3, bright=10.0, attack=0.012, release=0.12, decay=None,
            vib=0.0, detune=7.0):
    """Bowed string section. decay=seconds gives spiccato/staccato."""
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    f = mtof(midi)
    K = int(min(40, NYQ / f))
    k = np.arange(1, K + 1)
    amps = (1.0 / k) / (1.0 + (k / bright) ** 2)
    sig = np.zeros(n)
    for v in range(voices):
        fv = f * 2.0 ** (rng.uniform(-detune, detune) / 1200.0)
        ph = phase_of(fv, n, rng, rng.uniform(4.8, 5.6), vib, 0.15)
        sig += harmonic_sum(ph, fv, amps, rng)
    sig *= note_env(dur, attack, release, n)
    if decay:
        sig *= np.exp(-t / decay)
    # Bow noise on the attack.
    nz = fft_filter(rng.standard_normal(n), 800, 5000)
    sig += nz / (rms(nz) + 1e-9) * rms(sig) * 0.25 * np.exp(-t / 0.04)
    return peak_norm(sig)


def brass(midi, dur, rng, voices=3, peak=9.0, sus=5.0, attack=0.06, release=0.25, detune=6.0,
          growl=0.0, scoop=30.0, vib=8.0):
    """Brass section: the brightness (harmonic count) swells on the attack like a real horn."""
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    f = mtof(midi)
    env = note_env(dur, attack, release, n)
    b = sus + (peak - sus) * np.exp(-t / 0.25)
    b = b * np.clip(t / attack, 0.2, 1.0) * (0.45 + 0.55 * env)
    K = int(min(30, NYQ / f))
    sig = np.zeros(n)
    for v in range(voices):
        cents = -scoop * np.exp(-t / 0.05) + rng.uniform(-detune, detune)
        ph = phase_of(f, n, rng, rng.uniform(4.8, 5.6), vib, 0.4, cents)
        amps = [k ** -0.55 * np.exp(-(k - 1) / b) for k in range(1, K + 1)]
        sig += harmonic_sum(ph, f, amps, rng)
    if growl:
        sig *= 1.0 + growl * np.sin(TAU * f * 0.5 * t)
        sig = drive(sig / (np.max(np.abs(sig)) + 1e-9), 1.0 + 3.0 * growl)
    return peak_norm(sig * env)


def bell(midi, rng, decay=6.0, dur=None, strike=0.4):
    """Church bell: hum, prime, minor-third tierce, quint, nominal and upper partials."""
    ratios = [0.5, 1.0, 1.19, 1.5, 2.0, 2.51, 2.66, 3.01, 4.17, 5.43, 6.8]
    amps = [0.6, 0.9, 0.7, 0.35, 1.0, 0.4, 0.35, 0.3, 0.2, 0.12, 0.08]
    f = mtof(midi)
    dur = dur or decay * 1.2
    n = int(dur * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for r, a in zip(ratios, amps):
        fr = f * r * (1.0 + rng.normal(0, 0.002))
        if fr < NYQ:
            T = decay * (1.0 / r) ** 0.75
            # Each partial is a slightly split pair -> the slow "wow" beating of a real bell.
            sig += a * np.exp(-t / T) * (np.sin(TAU * fr * t) + 0.6 * np.sin(TAU * fr * 1.0015 * t + 1.0))
    nz = fft_filter(rng.standard_normal(n), 1500, 7000)
    sig += nz / (rms(nz) + 1e-9) * strike * 0.3 * np.exp(-t / 0.01)
    return peak_norm(sig)


def harp(midi, rng, decay=2.2, bright=1.0):
    """Plucked harp: harmonics excited at a pluck point, upper ones die faster."""
    f = mtof(midi)
    n = int(decay * 1.6 * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for k in range(1, 30):
        fk = f * k * np.sqrt(1.0 + 0.00015 * k * k)
        if fk > NYQ:
            break
        a = abs(np.sin(np.pi * k * 0.13)) / k ** (1.3 - 0.3 * bright)
        sig += a * np.exp(-t * (1.0 + 0.45 * (k - 1)) / decay) * np.sin(TAU * fk * t + rng.uniform(0, TAU))
    sig *= np.clip(t / 0.002, 0, 1)
    return peak_norm(sig)


def music_box(midi, rng, decay=1.6, wow=0.0):
    """Music-box tine. wow > 0 detunes it like a warped, dying record."""
    f = mtof(midi) * 2.0 ** (rng.normal(0, wow) / 1200.0)
    n = int(decay * 1.5 * SR)
    t = np.arange(n) / SR
    sig = (np.sin(TAU * f * t) * np.exp(-t / decay)
           + 0.3 * np.sin(TAU * f * 3.9 * t) * np.exp(-t / (decay * 0.25))
           + 0.12 * np.sin(TAU * f * 9.2 * t) * np.exp(-t / (decay * 0.08)))
    sig *= np.clip(t / 0.001, 0, 1)
    return peak_norm(sig)


def loop_drone(T, midi, partials, rng, beat_cycles=3, lfo_cycles=2, lfo_depth=0.3):
    """A drone exactly one loop long, every frequency snapped to whole cycles per loop
    so it wraps seamlessly. Two ranks offset by `beat_cycles` per loop beat slowly."""
    L = T.L
    Ls = L / SR
    base = max(1, int(round(mtof(midi) * Ls)))
    i = np.arange(L)
    sig = np.zeros(L)
    for rank in (0, 1):
        for r, a in partials:
            cyc = int(round(r * base)) + rank * beat_cycles
            if cyc / Ls < NYQ:
                sig += a * np.sin(TAU * cyc * i / L + rng.uniform(0, TAU))
    if lfo_depth:
        sig *= 1.0 - lfo_depth * (0.5 + 0.5 * np.sin(TAU * lfo_cycles * i / L + rng.uniform(0, TAU)))
    return peak_norm(sig)


# ---------------------------------------------------------------- percussion

def taiko(rng, pitch=1.0, dur=1.4):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = 58.0 * pitch
    f = f0 * (1.0 + 1.6 * np.exp(-t / 0.018))
    ph = TAU * np.cumsum(f) / SR
    body = (np.sin(ph) * np.exp(-t / 0.42) + 0.45 * np.sin(1.59 * ph + 0.3) * np.exp(-t / 0.16)
            + 0.2 * np.sin(2.31 * ph) * np.exp(-t / 0.07))
    skin = fft_filter(rng.standard_normal(n), 80, 1800) * np.exp(-t / 0.025)
    x = body + 0.5 * skin / (np.max(np.abs(skin)) + 1e-9)
    return peak_norm(drive(x, 1.6))


def boom(rng, dur=2.2):
    """Gran cassa / huge low hit."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 36.0 * (1.0 + 1.3 * np.exp(-t / 0.05))
    x = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.9)
    rum = fft_filter(rng.standard_normal(n), 20, 160) * np.exp(-t / 0.45)
    x += 0.6 * rum / (np.max(np.abs(rum)) + 1e-9)
    # Peak 0.55: a gran cassa carries far more energy than its peak suggests.
    return peak_norm(drive(x, 1.4), 0.55)


def snare(rng, dur=0.6, rattle=0.18):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = (np.sin(TAU * 185 * t) + 0.5 * np.sin(TAU * 330 * t)) * np.exp(-t / 0.05)
    nz = fft_filter(rng.standard_normal(n), 1200, 8000) * np.exp(-t / rattle)
    return peak_norm(0.6 * tone + nz / (np.max(np.abs(nz)) + 1e-9))


def anvil(rng, base=820.0, dur=1.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for r, a, d in [(1, 1, 0.45), (2.41, 0.6, 0.28), (3.93, 0.5, 0.18), (5.86, 0.3, 0.1), (8.12, 0.2, 0.06)]:
        fr = base * r * (1.0 + rng.normal(0, 0.004))
        if fr < NYQ:
            x += a * np.exp(-t / d) * np.sin(TAU * fr * t)
    nz = fft_filter(rng.standard_normal(n), 2000, 9000) * np.exp(-t / 0.006)
    return peak_norm(x + 2.0 * nz)


def chains(rng, dur=0.35):
    """A rattle of chain links: several tiny metallic clicks in quick succession."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for _ in range(rng.integers(4, 8)):
        st = int(rng.uniform(0, 0.12) * SR)
        m = n - st
        tt = t[:m]
        click = np.zeros(m)
        for _ in range(3):
            click += np.sin(TAU * rng.uniform(2500, 7000) * tt) * np.exp(-tt / rng.uniform(0.008, 0.03))
        x[st:] += click * rng.uniform(0.4, 1.0)
    nz = fft_filter(rng.standard_normal(n), 3000, None) * np.exp(-t / 0.05)
    return peak_norm(x + 0.5 * nz)


def hat(rng, dur=0.15, decay=0.03):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return peak_norm(fft_filter(rng.standard_normal(n), 6000, None, 3) * np.exp(-t / decay))


def crash(rng, dur=3.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = fft_filter(rng.standard_normal(n), 2500, 10000) * np.exp(-t / 1.0)
    x = np.zeros(n)
    for _ in range(40):
        x += np.sin(TAU * rng.uniform(300, 8000) * t + rng.uniform(0, TAU)) * np.exp(-t / rng.uniform(0.3, 1.6))
    return peak_norm(nz / (np.max(np.abs(nz)) + 1e-9) + 0.15 * x / 40 * 6)


def sub_drop(rng, dur=2.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 28.0 + 50.0 * np.exp(-t / 0.5)
    return peak_norm(np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.8) * np.clip(t / 0.01, 0, 1))


class Kit:
    """Caches a few random variants of each percussion sound (round-robin feel, fast render)."""

    def __init__(self, rng, variants=4):
        self.rng = rng
        self.variants = variants
        self.cache = {}

    def get(self, name, **kw):
        key = (name, tuple(sorted(kw.items())))
        if key not in self.cache:
            fn = globals()[name]
            self.cache[key] = [fn(self.rng, **kw) for _ in range(self.variants)]
        return self.cache[key][self.rng.integers(self.variants)]


# =========================================================================== mixing

class Stem:
    """One layer of a track. Its loop is `bars` long (a divisor of the track's bars, so shorter
    stems repeat in sample-exact sync); `mono` stems are folded to one channel when written."""

    def __init__(self, track, name, role, ir, target_db, bars, mono, out_rate=None):
        self.track = track
        self.out_rate = out_rate  # write this stem at a lower rate (its length must stay exact)
        self.name = name
        self.role = role
        self.ir = ir
        self.target_db = target_db
        self.bars = bars
        self.mono = mono
        self.L = bars * track.bar_samples if track.loop else track.L
        self.dry = np.zeros((2, self.L))
        self.wet = np.zeros((2, self.L))

    @staticmethod
    def _wrap_add(buf, sig, i):
        L = buf.shape[1]
        i %= L
        pos = 0
        n = sig.shape[1]
        while pos < n:
            m = min(n - pos, L - i)
            buf[:, i:i + m] += sig[:, pos:pos + m]
            pos += m
            i = 0

    def add(self, sig, t, pan=0.0, gain=1.0, send=0.3, jitter=0.004):
        """Mix `sig` in at `t` seconds; anything past the loop end wraps to the start."""
        if jitter:
            t = max(0.0, t + self.track.rng.normal(0, jitter)) if t > 0.01 else t
        st = stereo(sig, pan) * gain
        i = int(round(t * SR))
        self._wrap_add(self.dry, st, i)
        if send > 0:
            self._wrap_add(self.wet, st * send, i)

    def render(self):
        x = self.dry + circ_conv(self.wet, self.ir)
        if self.mono:
            x = x.mean(axis=0, keepdims=True)
        return x


class Track:
    def __init__(self, name, bpm, bars, bpb=4, seed=1, loop=True, length=None, title="", out_rate=None):
        self.name = name
        # Optional lower output rate for dark single-stem tracks (repo budget); see resample().
        self.out_rate = out_rate
        self.title = title
        self.bpm = bpm
        self.bars = bars
        self.bpb = bpb
        self.spb = 60.0 / bpm
        self.loop = loop
        # Integer samples per bar, so stems of 2/4/8 bars tile exactly.
        self.bar_samples = int(round(bpb * self.spb * SR))
        self.L = int(round(length * SR)) if length else bars * self.bar_samples
        self.rng = np.random.default_rng(seed)
        self.kit = Kit(self.rng)
        self.stems = []
        self.reused = []  # manifest stem entries borrowed from another track (no new audio)

    def reuse(self, base, names):
        """Layer stems already rendered for track `base` under this track's own stems (by file
        reference, so they cost no bytes). The base must share tempo, meter and loop length."""
        info = MANIFEST["tracks"].get(base)
        assert info, "render %s before %s" % (base, self.name)
        assert (info["bpm"], info["beats_per_bar"], info["samples"]) == (self.bpm, self.bpb, self.L),             "%s does not match %s's tempo / meter / length" % (self.name, base)
        for st in info["stems"]:
            if st["name"] in names:
                self.reused.append(dict(st, name="%s_%s" % (base, st["name"])))

    def stem(self, name, role="base", ir=IR_CATHEDRAL, target_db=-20.0, bars=None, mono=True, out_rate=None):
        bars = bars or self.bars
        assert self.bars % bars == 0, "stem bars must divide track bars"
        if out_rate:  # a lower-rate stem must still be a whole number of samples per loop
            secs = bars * self.bpb * self.spb
            assert abs(secs * out_rate - round(secs * out_rate)) < 1e-6, "stem length not exact at %d Hz" % out_rate
        s = Stem(self, name, role, ir, target_db, bars, mono, out_rate)
        self.stems.append(s)
        return s

    def beat(self, b):
        """Beats -> seconds."""
        return b * self.spb

    def bar(self, bar, beat=0.0):
        """Bar (+ beat) -> seconds, on the integer-sample bar grid."""
        return bar * self.bar_samples / SR + beat * self.spb

    def step(self, bar, step16):
        """Bar + 16th-note step -> seconds."""
        return self.bar(bar, step16 / 4.0)

    def finish(self):
        """Balance stems to their loudness targets, soft-limit, write WAVs, return manifest info."""
        mixes = []
        for s in self.stems:
            x = s.render()
            x = x * (10.0 ** (s.target_db / 20.0) / loudness(x))
            # Soft-knee peak limiting: drum downbeats stacking up would otherwise force the
            # whole track down (and the calm layer with it).
            mixes.append(soft_limit(x, 0.42))
        # Peak of the all-layers mix: tile shorter stems to the full length, fold to mono.
        total = np.zeros(self.L)
        for x in mixes:
            m = x.mean(axis=0)
            total += np.tile(m, self.L // len(m) + 1)[: self.L]
        pk = float(np.max(np.abs(total)))
        # The all-layers sum may overshoot full scale a little: MusicManager plays 2 dB under
        # unity and the Master bus has a hard limiter, and frenzy downbeats are rare.
        scale = min(1.0, 1.25 / pk)
        info = [dict(r) for r in self.reused]
        for s, x in zip(self.stems, mixes):
            x = np.clip(x * scale, -0.99, 0.99)
            if not self.loop:  # stingers: make sure the tail ends in silence
                nf = int(0.4 * SR)
                x[:, -nf:] *= np.linspace(1.0, 0.0, nf)
            ld = round(20 * np.log10(loudness(x)), 1)  # measured at SR, before any resample
            rate = SR
            if self.out_rate and len(self.stems) == 1:
                x, rate = resample(x, self.out_rate), self.out_rate
            elif s.out_rate:
                x, rate = resample(x, s.out_rate), s.out_rate
            fname = "%s_%s.wav" % (self.name, s.name)
            write_wav(os.path.join(OUT, fname), x, self.loop, rate)
            info.append({"name": s.name, "role": s.role, "file": "res://assets/audio/music/" + fname,
                         "samples": int(x.shape[1]), "bars": s.bars, "channels": int(x.shape[0]), "mix_rate": rate,
                         "loudness_db": ld})
        print("  %-18s %5.1fs  peak %.2f  scale %.2f  %s" % (
            self.name, self.L / SR, pk * scale, scale,
            ", ".join("%s %.1fdB" % (i["name"], i["loudness_db"]) for i in info)))
        return {"title": self.title, "bpm": self.bpm, "bars": self.bars, "beats_per_bar": self.bpb,
                "samples": self.L, "mix_rate": SR, "loop": self.loop, "stems": info}


def resample(x, rate):
    """Band-limited circular FFT resample to `rate` (a loop stays seamless)."""
    n = x.shape[1]
    m = int(round(n * rate / SR))
    X = np.fft.rfft(x, axis=1)[:, : m // 2 + 1]
    return np.fft.irfft(X, n=m, axis=1) * (m / n)


def write_wav(path, x, loop, rate=None):
    """16-bit PCM WAV (mono or stereo). Loops get a 'smpl' chunk so Godot's importer detects them."""
    rate = rate or SR
    ch, n = x.shape
    pcm = np.round(np.clip(x, -1.0, 1.0).T * 32767.0).astype("<i2").tobytes()
    body = b"fmt " + struct.pack("<I", 16) + struct.pack("<HHIIHH", 1, ch, rate, rate * 2 * ch, 2 * ch, 16)
    body += b"data" + struct.pack("<I", len(pcm)) + pcm
    if len(pcm) % 2:
        body += b"\x00"
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / rate), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body)


def crackle(L, rng, density=30.0):
    """Fire bed exactly L samples long: sparse ember pops over a low roar (circular, loops)."""
    x = np.zeros(L)
    n = int(L / SR * density)
    idx = rng.integers(0, L, n)
    x[idx] = rng.uniform(-1, 1, n) * rng.uniform(0.2, 1.0, n) ** 2
    pops = fft_filter(x, 700, 6000)
    roar = fft_filter(rng.standard_normal(L), 50, 350)
    return peak_norm(pops / (np.max(np.abs(pops)) + 1e-9) + 0.5 * roar / (np.max(np.abs(roar)) + 1e-9))


# =========================================================================== themes
# Layout rules (size budget, see docs/team/music.md): every stem is mono except the hub and
# title themes; map tracks are 8 bars, their combat stem 4 bars on a tonic pedal (so it fits
# every chord of the calm layer); boss enrage/phase-3 stems are 4 bars.

def t_basecamp():
    """Basecamp Hell: brooding pipe organ over a pedal drone, monk hum, reed solo, distant bell,
    a slow heartbeat. C minor with a Phrygian Db. 66 BPM, 8 bars (written at 11.025 kHz)."""
    T = Track("basecamp", 66, 8, seed=11, title="Basecamp Hell", out_rate=11025)
    r = T.rng
    s = T.stem("main", "base", IR_CATHEDRAL, -20.0, )
    s.add(loop_drone(T, 24, [(1, 1.0), (2, 0.8), (3, 0.2), (4, 0.25)], r, 2, 2, 0.35), 0, 0, 0.32, 0.25, 0)
    s.add(loop_drone(T, 31, [(1, 0.6), (2, 0.3)], r, 3, 1, 0.5), 0, 0, 0.1, 0.4, 0)
    s.add(peak_norm(fft_filter(r.standard_normal(T.L), 25, 110, 3)), 0, 0, 0.12, 0.0, 0)
    chords = [[48, 51, 55, 60], [49, 53, 56, 61], [48, 51, 55, 63], [47, 50, 53, 56],
              [44, 48, 51, 56], [41, 48, 53, 56], [44, 49, 53, 56], [43, 47, 53, 56]]
    for ci, ch in enumerate(chords):
        for j, m in enumerate(ch):
            o = organ(m, T.bar(1) - 0.15, r, ORGAN_PRINCIPAL, 0.6, 1.3, 5.1, 0.22)
            s.add(o, T.bar(ci), (j - 1.5) * 0.35, 0.16, 0.45)
        hum = choir(ch[0] - 12 if ch[0] > 45 else ch[0], T.bar(1), r, "u" if ci < 4 else "o", 5, 1.0, 1.4, 10, 0.0, 12.0)
        s.add(hum, T.bar(ci), 0, 0.16, 0.5)
    mel = [[(72, 1.5), (75, 0.5), (80, 2)], [(77, 1), (75, 1), (72, 2)],
           [(73, 1.5), (72, 0.5), (68, 2)], [(71, 1), (68, 1), (67, 2)]]
    for pi, phrase in enumerate(mel):
        b = 0.0
        for m, d in phrase:
            o = organ(m, T.beat(d) * 0.95, r, ORGAN_REED, 0.08, 0.6, 5.6, 0.3, 4.0, 0.06)
            s.add(o, T.bar(4 + pi, b), 0.2, 0.09, 0.55)
            b += d
    s.add(bell(48, r, 7.0), T.bar(0), -0.5, 0.14, 0.7)
    s.add(bell(36, r, 9.0), T.bar(0) + 0.02, 0.4, 0.08, 0.7)
    s.add(bell(51, r, 6.0), T.bar(4), 0.5, 0.07, 0.8)
    for b in range(8):
        s.add(fft_filter(T.kit.get("taiko", pitch=0.55), None, 300), T.bar(b), 0, 0.22, 0.15)
        s.add(fft_filter(T.kit.get("taiko", pitch=0.6), None, 300), T.bar(b, 0.4), 0, 0.14, 0.15)
    return T


def t_title():
    """Title / menus: a sweet music-box hymn in D major that warps and sours into D minor."""
    T = Track("title", 60, 8, seed=21, title="A Hymn, Unsung", out_rate=11025)
    r = T.rng
    s = T.stem("main", "base", IR_CATHEDRAL, -20.0, )
    s.add(loop_drone(T, 38, [(1, 1.0), (2, 0.5), (3, 0.15)], r, 2, 2, 0.4), 0, 0, 0.25, 0.3, 0)
    chords = [[62, 66, 69], [62, 67, 71], [62, 66, 69], [61, 64, 69],
              [62, 66, 69], [59, 62, 67], [60, 64, 70], [62, 65, 69]]
    for b, ch in enumerate(chords):
        bad = 0.0 if b < 5 else 0.3 * (b - 4)
        for m in ch:
            c = choir(m, T.beat(4) - 0.1, r, "a" if b % 2 == 0 else "o", 4, 0.9, 1.2, 12, bad, 10.0 * bad)
            s.add(c, T.bar(b), 0, 0.14, 0.6)
        s.add(choir(ch[0] - 24, T.beat(4), r, "u", 4, 0.8, 1.0, 8), T.bar(b), 0, 0.08, 0.5)
    mel = [(78, 1), (78, 1), (76, 1), (74, 1), (79, 1), (78, 1), (76, 2), (81, 1), (81, 1), (79, 1),
           (78, 1), (76, 4), (74, 1), (76, 1), (78, 1), (81, 1), (79, 1), (77, 1), (76, 1), (74, 1),
           (76, 2), (72, 1), (76, 1), (74, 1), (73, 1), (74, 2)]
    b = 0.0
    for m, d in mel:
        wow = 4.0 + 30.0 * (b / 32.0) ** 2  # the record warps more and more
        s.add(music_box(m, r, 1.8, wow), T.beat(b), 0.15, 0.32, 0.5)
        s.add(music_box(m - 12, r, 1.2, wow), T.beat(b) + 0.01, -0.2, 0.08, 0.5)
        b += d
    s.add(bell(50, r, 8.0), 0, -0.6, 0.1, 0.8)
    return T


def t_sanctum():
    """Map: The Ruined Sanctum (battle_sanctum, the default). A cello laments over a humming choir
    in E minor; combat: war drums + an E-pedal string pulse; frenzy: horn calls (the last one sags
    to the b5), choir power chords, chains."""
    T = Track("battle_sanctum", 96, 8, seed=81, title="Requiem for a Ruin")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_CATHEDRAL, -20.0)
    combat = T.stem("combat", "combat", IR_HALL, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_CATHEDRAL, -23.5, bars=4)
    chords = [[52, 55, 59], [48, 52, 55], [45, 48, 52], [47, 51, 54],
              [52, 55, 59], [50, 55, 59], [48, 52, 55], [47, 51, 54, 60]]
    roots = [40, 36, 33, 35, 40, 38, 36, 35]
    calm.add(loop_drone(T, 28, [(1, 1.0), (2, 0.6), (3, 0.25)], r, 2, 2, 0.35), 0, 0, 0.22, 0.3, 0)
    for ci, ch in enumerate(chords):
        for m in ch[:3]:
            calm.add(choir(m, T.bar(1) - 0.15, r, "u" if ci % 2 == 0 else "o", 4, 0.8, 1.2, 10), T.bar(ci), 0, 0.1, 0.5)
        calm.add(strings(roots[ci], T.bar(1) - 0.1, r, 3, 6, 0.4, 0.9, None, 6), T.bar(ci), -0.3, 0.14, 0.4)
    cello = [(64, 3), (66, 1), (67, 4), (64, 2), (60, 2), (62, 4), (60, 3), (59, 1), (57, 4), (59, 4), (63, 4)]
    b = 0.0
    for m, d in cello:
        calm.add(strings(m - 12, T.beat(d) * 0.97, r, 1, 7, 0.12, 0.35, None, 22, 0), T.beat(b), 0.25, 0.22, 0.45)
        b += d
    calm.add(bell(52, r, 7.0), 0, -0.6, 0.09, 0.8, 0)
    for bar in range(4):
        for i in range(8):
            m = 40 + (7 if i in (3, 7) else 0)
            st = strings(m, T.beat(0.4), r, 3, 9, 0.005, 0.06, 0.16)
            combat.add(st, T.bar(bar, i * 0.5), -0.25, 0.2 if i % 2 == 0 else 0.13, 0.15)
        for s16, v in zip([0, 3, 8, 10, 14], [1.0, 0.55, 0.9, 0.6, 0.7]):
            combat.add(k.get("taiko"), T.step(bar, s16), 0, 0.55 * v, 0.2)
        for s16 in (4, 12):
            combat.add(k.get("snare", rattle=0.22), T.step(bar, s16), 0.2, 0.22, 0.3)
        for s16 in (1, 5, 6, 9, 13):
            combat.add(k.get("taiko", pitch=1.8), T.step(bar, s16), -0.35, 0.08, 0.15)
        if bar % 2 == 0:
            combat.add(k.get("boom"), T.bar(bar), 0, 0.5, 0.2)
    for s16 in range(8, 16, 2):
        combat.add(k.get("taiko", pitch=1.3), T.step(3, s16), 0.2, 0.3, 0.2)
    # frenzy: 4 bars over the E pedal (power chords fit every calm chord). Two horn calls,
    # the second sagging to the b5.
    calls = [(76, 1.5), (79, 0.5), (78, 1.0), (76, 1.0), (71, 4.0)]
    for bar in (0, 2):
        b = 0.0
        for m, d in calls:
            mm = 70 if (bar == 2 and m == 71) else m
            frenzy.add(brass(mm - 12, T.beat(d) * 0.92, r, 4, 11, 7, 0.04, 0.3, 8, 0.15, 25, 8), T.bar(bar, b), 0.1, 0.2, 0.4)
            b += d
    for bar in range(4):
        for m in (52, 59, 64):
            frenzy.add(choir(m, T.bar(1) - 0.15, r, "a", 4, 0.2, 0.5, 16, 0.2), T.bar(bar), 0, 0.1, 0.5)
        for s16 in (2, 6, 10, 14):
            frenzy.add(k.get("chains"), T.step(bar, s16), r.uniform(-0.7, 0.7), 0.1, 0.2)
    frenzy.add(k.get("crash"), T.bar(0), 0.4, 0.25, 0.3)
    return T


def t_city():
    """Map: Cathedral City (battle_city). Gregorian chant in D Phrygian; organum joins, then a
    tritone shadow; combat: taiko + a b2 string ostinato on a D pedal; frenzy: shrieks, horns, chains."""
    T = Track("battle_city", 92, 8, seed=31, title="Vespers of Ash")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_CATHEDRAL, -20.0)
    combat = T.stem("combat", "combat", IR_HALL, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_CATHEDRAL, -23.5, bars=4)
    calm.add(loop_drone(T, 38, [(1, 1.0), (2, 0.5), (3, 0.3), (4, 0.1)], r, 3, 2, 0.3), 0, -0.2, 0.22, 0.3, 0)
    calm.add(loop_drone(T, 45, [(1, 1.0), (2, 0.3)], r, 2, 1, 0.5), 0, 0.2, 0.1, 0.3, 0)
    chant = [(50, 2), (53, 2), (55, 2), (57, 4), (58, 2), (57, 2), (55, 2), (53, 2), (55, 2), (51, 4), (50, 8)]
    b = 0.0
    for i, (m, d) in enumerate(chant):
        v = "a" if i % 3 else "o"
        late = b >= 24
        calm.add(choir(m, T.beat(d) * 0.97, r, v, 5, 0.25, 0.9, 12, 0.35 if late else 0.0, 30 if late else 0),
                 T.beat(b), 0, 0.3, 0.55)
        if b >= 16:  # organum a fourth below
            calm.add(choir(m - 5, T.beat(d) * 0.97, r, v, 4, 0.3, 0.9, 10), T.beat(b), 0, 0.17, 0.55)
        if late:  # the tritone shadow creeping in
            calm.add(choir(m + 6, T.beat(d) * 0.97, r, "u", 3, 0.5, 0.9, 20, 0.8, 50), T.beat(b), 0.5, 0.06, 0.8)
        b += d
    for ch, st, ln in [([50, 53, 57], 0, 2), ([46, 50, 53], 2, 1), ([48, 52, 55], 3, 1),
                       ([50, 53, 57], 4, 2), ([51, 55, 58], 6, 1), ([45, 49, 52], 7, 1)]:
        for m in ch:
            calm.add(organ(m - 12, T.bar(ln) - 0.1, r, ORGAN_FLUTE, 0.7, 1.0, 4.5, 0.15), T.bar(st), 0, 0.06, 0.5)
    sw = choir(62, 2.4, r, "a", 4, 1.6, 0.4, 10, 0.4)[:, ::-1]  # reversed swell into bar 4
    calm.add(sw, T.bar(4) - sw.shape[1] / SR, 0.3, 0.12, 0.7, 0)
    calm.add(bell(50, r, 7.0), T.bar(0), -0.6, 0.1, 0.8, 0)
    calm.add(bell(51, r, 7.0), T.bar(4), 0.6, 0.08, 0.8, 0)
    ost = [0, 0, 12, 0, 1, 0, 3, 0]
    for bar in range(4):
        for i, rel in enumerate(ost):
            st = strings(38 + rel, T.beat(0.45), r, 3, 9, 0.006, 0.08, 0.18)
            combat.add(st, T.bar(bar, i * 0.5), -0.25, 0.22 if i % 2 == 0 else 0.16, 0.15)
        for s16, v in zip([0, 6, 8, 11, 14], [1.0, 0.65, 0.85, 0.6, 0.8]):
            combat.add(k.get("taiko"), T.step(bar, s16), -0.1, 0.55 * v, 0.2)
        for s16 in (2, 3, 7, 10, 13, 15):
            combat.add(k.get("taiko", pitch=1.7), T.step(bar, s16), 0.35, 0.1, 0.15)
        for s16 in (4, 12):
            combat.add(k.get("anvil"), T.step(bar, s16), 0.3, 0.13, 0.3)
        if bar % 2 == 0:
            combat.add(k.get("boom"), T.bar(bar), 0, 0.6, 0.25)
    for s16 in range(12, 16):
        combat.add(k.get("taiko", pitch=1.2), T.step(3, s16), 0.1, 0.25 + 0.1 * (s16 - 12), 0.2)
    # frenzy: 4 bars over the D pedal.
    for m in (74, 75):
        frenzy.add(choir(m, T.bar(4) - 0.5, r, "e", 4, 2.0, 1.0, 30, 0.6, 40), 0, 0.4 if m % 2 else -0.4, 0.2, 0.6)
    for bar in range(4):
        for s16, ln in ((0, 0.6), (10, 0.35)):
            for m in (38, 45):
                frenzy.add(brass(m + 12, ln, r, 3, 12, 6, 0.03, 0.2, 10, 0.3), T.step(bar, s16), 0, 0.2, 0.35)
        for s16 in (2, 6, 10, 14):
            frenzy.add(k.get("chains"), T.step(bar, s16), r.uniform(-0.7, 0.7), 0.12, 0.2)
        for s16 in range(1, 16, 2):
            frenzy.add(k.get("taiko", pitch=1.4), T.step(bar, s16), -0.3, 0.12, 0.15)
    frenzy.add(k.get("crash"), T.bar(0), 0.5, 0.25, 0.3)
    rc = k.get("crash")[::-1][-int(T.bar(1) * SR):]
    frenzy.add(rc, -rc.shape[0] / SR, -0.5, 0.15, 0.3, 0)  # reverse swell into the loop point
    return T


def t_monastery():
    """Map: The Frozen Monastery (battle_monastery). Oktavist bass choir in B minor, ice bells,
    cold wind; combat: tremolo strings on a B pedal, frame drums, icy metal; frenzy: shrieking
    sopranos, minor-2nd brass, clanging bells."""
    T = Track("battle_monastery", 84, 8, seed=91, title="Matins in the Snow")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_CATHEDRAL, -20.0)
    combat = T.stem("combat", "combat", IR_HALL, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_CATHEDRAL, -23.5, bars=4)
    chords = [[35, 47, 54, 59, 62], [31, 43, 50, 55, 59], [28, 40, 47, 52, 55], [30, 42, 49, 54, 58],
              [35, 47, 54, 59, 62], [33, 45, 52, 57, 61], [31, 43, 50, 55, 62], [30, 42, 46, 54, 61]]
    for ci, ch in enumerate(chords):
        for j, m in enumerate(ch):
            c = choir(m, T.bar(1) - 0.15, r, "o" if ci % 2 == 0 else "a", 5 if j == 0 else 4, 0.7, 1.2,
                      7 if j == 0 else 11)
            calm.add(c, T.bar(ci), (j - 2) * 0.2, 0.2 if j == 0 else 0.11, 0.5)
    i = np.arange(T.L)
    wind = fft_filter(r.standard_normal(T.L), 300, 1400, 2)
    gust = 0.4 + 0.6 * (0.5 + 0.5 * np.sin(TAU * 2 * i / T.L)) * (0.6 + 0.4 * np.sin(TAU * 5 * i / T.L + 1.0))
    calm.add(peak_norm(wind * gust), 0, 0, 0.07, 0.2, 0)
    ice = [83, 86, 90, 88, 83, 81, 78, 86]
    for bar in range(8):
        for bt in (0, 1.5, 3):
            if r.random() < 0.6:
                m = ice[(bar * 3 + int(bt * 2)) % len(ice)]
                calm.add(music_box(m, r, 2.5, 3), T.bar(bar, bt), r.uniform(-0.8, 0.8), 0.1, 0.7)
    calm.add(bell(47, r, 8.0), 0, -0.5, 0.1, 0.8, 0)
    for bar in range(4):
        for s16 in range(16):
            st = strings(47 + (12 if s16 in (6, 14) else 0), T.beat(0.24), r, 3, 8, 0.004, 0.05, 0.12)
            combat.add(st, T.step(bar, s16), -0.25, 0.14 if s16 % 4 == 0 else 0.08, 0.15)
        for s16 in range(0, 16, 2):
            combat.add(k.get("taiko", pitch=1.5), T.step(bar, s16), 0.3, 0.16 if s16 % 4 else 0.24, 0.2)
        for s16, v in ((0, 1.0), (10, 0.75)):
            combat.add(k.get("taiko", pitch=0.85), T.step(bar, s16), 0, 0.55 * v, 0.2)
        combat.add(k.get("anvil", base=1400.0), T.step(bar, 12), 0.4, 0.1, 0.4)
        if bar % 2 == 0:
            combat.add(k.get("boom"), T.bar(bar), 0, 0.5, 0.25)
    # frenzy: 4 bars over the B pedal.
    for m in (78, 79):
        frenzy.add(choir(m, T.bar(4) - 0.4, r, "i", 4, 1.6, 1.0, 28, 0.5, 30), 0, 0.4 if m % 2 else -0.4, 0.18, 0.6)
    for bar in range(4):
        root = 59
        for s16 in (0, 3, 6):
            for m in (root, root + 1):
                frenzy.add(brass(m, 0.3, r, 2, 12, 7, 0.02, 0.15, 10, 0.4), T.step(bar, s16), 0, 0.12, 0.3)
        for bt in range(4):
            frenzy.add(bell([71, 66, 72, 65][bt], r, 2.5, 2.0), T.bar(bar, bt + 0.5), r.uniform(-0.6, 0.6), 0.08, 0.5)
    frenzy.add(k.get("crash"), T.bar(0), -0.4, 0.25, 0.3)
    return T


def t_gardens():
    """Map: The Outer Gardens (battle_gardens). Ironically sweet F-major harp and soprano choir,
    souring to Bbm / Db; combat: half-time stomp and a distorted F-pedal bass with a semitone rub;
    frenzy: falling-angel glissandi, dissonant brass, 16th hats."""
    T = Track("battle_gardens", 104, 8, seed=41, title="The Gardens Above")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_HALL, -20.0)
    combat = T.stem("combat", "combat", IR_ROOM, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_CATHEDRAL, -23.5, bars=4)
    chords = [[53, 57, 60, 65], [52, 57, 60, 64], [50, 53, 58, 62], [52, 55, 60, 64],
              [50, 53, 57, 62], [49, 53, 58, 61], [49, 53, 56, 61], [48, 52, 55, 58]]
    roots = [53, 45, 46, 48, 50, 46, 49, 48]
    for ci, ch in enumerate(chords):
        bad = [0, 0, 0, 0, 0.1, 0.45, 0.6, 0.35][ci]
        for m in ch[1:]:
            calm.add(choir(m + 12, T.bar(1) - 0.12, r, "a" if ci % 2 == 0 else "o", 4, 0.5, 0.9, 14, bad, 25 * bad),
                     T.bar(ci), 0, 0.12, 0.45)
        seq = ch + [n + 12 for n in ch]
        if ci % 2:
            seq = seq[::-1]
        for j in range(8):
            calm.add(harp(seq[j] + 12, r, 2.0), T.bar(ci, j * 0.5), r.uniform(-0.5, 0.5), 0.2, 0.35)
        calm.add(harp(roots[ci] - 12, r, 3.0, 0.5), T.bar(ci), -0.1, 0.3, 0.3)
    for bar, bt, m in [(2, 0, 84), (2, 1.5, 81), (2, 3, 77), (6, 0, 85), (6, 1.5, 82), (6, 3, 77)]:
        calm.add(music_box(m, r, 1.5, 8 if bar > 4 else 2), T.bar(bar, bt), 0.6, 0.15, 0.6)
    for bar in range(4):
        for s16, v in zip([0, 7, 10], [1.0, 0.6, 0.75]):
            combat.add(k.get("taiko", pitch=0.9), T.step(bar, s16), 0, 0.55 * v, 0.15)
        combat.add(k.get("snare", rattle=0.25), T.step(bar, 8), 0.1, 0.35, 0.3)
        combat.add(k.get("anvil", base=640.0), T.step(bar, 8), 0.3, 0.12, 0.3)
        combat.add(k.get("boom"), T.bar(bar), 0, 0.45, 0.2)
        for i in range(8):
            accent = i in (0, 3, 6)
            bs = drive(strings(29, T.beat(0.42), r, 2, 18, 0.004, 0.06, 0.22, 0, 14) * 2.5, 2.0)
            combat.add(bs, T.bar(bar, i * 0.5), 0, 0.28 if accent else 0.18, 0.05)
            if accent:  # the rub: a ghost a semitone up
                combat.add(drive(strings(30, T.beat(0.3), r, 1, 10, 0.004, 0.05, 0.15), 2), T.bar(bar, i * 0.5), 0.3, 0.05, 0.1)
        for s16 in (4, 12):
            combat.add(k.get("hat", decay=0.06), T.step(bar, s16), 0.4, 0.08, 0.1)
    # frenzy: 4 bars over the F pedal: falling angels, a semitone-rubbing brass cluster, hats.
    for bar, m in ((0, 81), (2, 84)):
        frenzy.add(choir(m, T.beat(3), r, "a", 4, 0.15, 0.6, 25, 0.5, 0, -700), T.bar(bar), -0.5 if bar else 0.5, 0.2, 0.6)
    for bar in (1, 3):
        for s16 in (0, 6, 12):
            for m in (65, 66, 72):
                frenzy.add(brass(m, 0.3, r, 2, 12, 7, 0.02, 0.15, 12, 0.4), T.step(bar, s16), 0, 0.14, 0.3)
    for bar in range(4):
        for s16 in range(16):
            frenzy.add(k.get("hat"), T.step(bar, s16), 0.5, 0.07 if s16 % 4 else 0.12, 0.05)
    frenzy.add(k.get("crash"), T.bar(0), -0.4, 0.25, 0.3)
    return T


def t_citadel():
    """Map: The Sunlit Citadel (battle_citadel). Righteous crusader brass in A minor whose second
    fanfare ends a tritone off; combat: military snare, 16th strings on an A pedal; frenzy: full
    brass melody, choir, cymbals."""
    T = Track("battle_citadel", 120, 8, seed=51, title="Bastion of Valor")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_HALL, -20.0)
    combat = T.stem("combat", "combat", IR_ROOM, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_HALL, -23.5, bars=4)
    chords = [[57, 60, 64], [53, 57, 60], [55, 59, 62], [56, 59, 64],
              [57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]
    roots = [45, 41, 43, 40, 45, 41, 38, 40]
    calm.add(loop_drone(T, 33, [(1, 1.0), (2, 0.6), (3, 0.2)], r, 2, 2, 0.3), 0, 0, 0.2, 0.3, 0)
    for ci, ch in enumerate(chords):
        for j, m in enumerate(ch):
            calm.add(brass(m - 12, T.bar(1) - 0.15, r, 3, 4.0, 2.5, 0.5, 0.7, 5, 0, 10, 4), T.bar(ci), (j - 1) * 0.4, 0.13, 0.45)
    fan = [(76, 0.33), (76, 0.33), (76, 0.34), (81, 1.0), (84, 1.0), (83, 0.5), (81, 0.5), (76, 2.0)]
    for bar, last in ((2, 76), (6, 75)):  # the second call ends a tritone off: holy, but wrong
        b = 0.0
        for i, (m, d) in enumerate(fan):
            m = last if i == len(fan) - 1 else m
            calm.add(brass(m, T.beat(d) * 0.9, r, 1, 14, 8, 0.03, 0.4, 0, 0, 20, 10), T.bar(bar, b), 0.6, 0.18, 0.8)
            b += d
    for s16 in range(16):
        calm.add(k.get("snare", rattle=0.1), T.step(7, s16), -0.3, 0.02 + 0.006 * s16, 0.4)
    ost = [0, 0, 7, 0, 12, 0, 7, 3, 0, 0, 7, 0, 12, 10, 7, 3]
    for bar in range(4):
        for s16 in range(16):
            acc = s16 in (0, 4, 8, 12)
            if acc or s16 in (6, 14) or (s16 % 2 == 1 and bar % 2 == 1):
                combat.add(k.get("snare", rattle=0.14), T.step(bar, s16), 0.15, 0.3 if acc else 0.1, 0.2)
            st = strings(57 + ost[s16], T.beat(0.22), r, 3, 10, 0.004, 0.05, 0.1)
            combat.add(st, T.step(bar, s16), -0.3, 0.15 if s16 % 4 == 0 else 0.1, 0.15)
        for s16 in (0, 8):
            combat.add(k.get("boom"), T.step(bar, s16), 0, 0.4, 0.15)
        for s16 in (6, 14):
            combat.add(k.get("taiko", pitch=1.1), T.step(bar, s16), -0.2, 0.35, 0.2)
    for s16, p in zip(range(8, 16, 2), (1.5, 1.3, 1.1, 0.95)):
        combat.add(k.get("taiko", pitch=p), T.step(3, s16), 0.2, 0.35, 0.2)
    # frenzy: 4 bars; the brass melody fits both halves of the calm progression, the choir holds
    # an A power chord.
    mel = [(69, 2), (72, 1), (76, 1), (77, 3), (76, 1), (74, 2), (72, 2), (71, 4)]
    b = 0.0
    for m, d in mel:
        frenzy.add(brass(m, T.beat(d) * 0.92, r, 4, 13, 8, 0.04, 0.3, 8, 0.1, 25, 10), T.beat(b), 0, 0.22, 0.35)
        b += d
    for bar in range(4):
        for m in (57, 64, 69):
            frenzy.add(choir(m + 12, T.bar(1) - 0.15, r, "a", 4, 0.25, 0.5, 18), T.bar(bar), 0, 0.1, 0.5)
        frenzy.add(choir(45, T.bar(1) - 0.15, r, "o", 4, 0.25, 0.5, 10), T.bar(bar), 0, 0.12, 0.4)
    frenzy.add(k.get("crash"), T.bar(0), 0.4, 0.22, 0.3)
    return T


def t_boss_sariel():
    """Boss: Sariel the Seraph. E Phrygian-dominant war mass: organ + brass tritone riff, 3-3-2
    taiko, choir stabs. 'enrage' (4 bars): shrieks, mad church bells, 16ths, sub drops."""
    T = Track("boss_sariel", 132, 8, seed=61, title="Mass for the Fallen Host")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_HALL, -18.5)
    enrage = T.stem("enrage", "enrage", IR_CATHEDRAL, -22.0, bars=4)
    roots = [40, 40, 41, 40, 40, 46, 45, 35]
    triads = {40: [64, 67, 71], 41: [65, 69, 72], 46: [65, 70, 74], 45: [64, 69, 72], 35: [63, 66, 71]}
    riff = [0, 0, 12, 0, 1, 0, 7, 6]
    for bar in range(8):
        root = roots[bar]
        for i, rel in enumerate(riff):
            main.add(organ(root + rel, T.beat(0.45), r, ORGAN_PLENUM, 0.01, 0.12, 0, 0, 3.0, 0.05), T.bar(bar, i * 0.5), -0.2, 0.2, 0.25)
            main.add(brass(root + rel, T.beat(0.4), r, 2, 10, 6, 0.015, 0.1, 8, 0.5, 15, 0), T.bar(bar, i * 0.5), 0.2, 0.14, 0.2)
        for s16 in range(0, 16, 2):
            v = 1.0 if s16 in (0, 6, 12) else 0.45
            main.add(k.get("taiko", pitch=1.0 if v > 0.5 else 1.3), T.step(bar, s16), 0, 0.5 * v, 0.2)
        for s16 in (4, 12):
            main.add(k.get("anvil", base=700.0), T.step(bar, s16), 0.35, 0.16, 0.3)
            main.add(k.get("snare"), T.step(bar, s16), -0.2, 0.22, 0.3)
        if bar % 2 == 0:
            main.add(k.get("boom"), T.bar(bar), 0, 0.5, 0.2)
        for bt, vowel in ((0, "a"), (2.5, "o")):
            for m in triads[root]:
                main.add(choir(m, T.beat(1.0), r, vowel, 4, 0.03, 0.35, 8), T.bar(bar, bt), 0, 0.15, 0.45)
            main.add(choir(root + 12, T.beat(1.0), r, vowel, 4, 0.03, 0.35, 6), T.bar(bar, bt), 0, 0.14, 0.4)
    for m in (76, 77):
        enrage.add(choir(m, T.bar(4) - 0.3, r, "i", 4, 1.0, 0.8, 35, 0.8, 60), 0, 0.5 if m % 2 else -0.5, 0.2, 0.6)
    for bar in range(4):
        for bt in range(4):
            enrage.add(bell([64, 59, 65, 60][bt], r, 3.0, 2.5), T.bar(bar, bt), r.uniform(-0.6, 0.6), 0.1, 0.5)
        for s16 in range(16):
            enrage.add(k.get("chains") if s16 % 4 == 2 else k.get("hat"), T.step(bar, s16), 0.4, 0.09, 0.1)
    for s16 in range(8, 16):
        enrage.add(k.get("snare", rattle=0.1), T.step(3, s16), -0.2, 0.1 + 0.03 * (s16 - 8), 0.2)
    enrage.add(k.get("sub_drop"), 0, 0, 0.5, 0.05)
    return T


def t_boss_inquisitor():
    """Boss: Ozias, the Grand Inquisitor. D minor auto-da-fe built on the Dies Irae chant (13th c.):
    'main' bass choir + reed organ, judgement hammers, a fire bed and the Bell of Judgement;
    'phase2' (Trial by Fire) driving 3-3-2 taiko, b2 string ostinato, brass and a roaring pyre;
    'phase3' (4 bars, Auto-da-fe) tritone bells on every beat, shrieks, snare rolls, sub drops."""
    T = Track("boss_inquisitor", 100, 8, seed=101, title="Dies Irae, Dies Illa")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_CATHEDRAL, -19.0)
    p2 = T.stem("phase2", "phase2", IR_HALL, -21.0, bars=4)
    p3 = T.stem("phase3", "phase3", IR_CATHEDRAL, -22.5, bars=4)
    main.add(loop_drone(T, 26, [(1, 1.0), (2, 0.7), (3, 0.3), (4, 0.3)], r, 2, 2, 0.3), 0, 0, 0.2, 0.3, 0)
    main.add(crackle(T.L, r, 35.0), 0, 0, 0.1, 0.15, 0)
    dies = [(53, 2), (52, 2), (53, 2), (50, 2), (52, 2), (48, 2), (50, 2), (50, 2),
            (53, 1), (53, 1), (55, 2), (53, 1), (52, 1), (50, 2), (48, 1), (52, 1), (53, 2), (52, 2), (50, 2)]
    b = 0.0
    for m, d in dies:
        main.add(choir(m, T.beat(d) * 0.96, r, "o" if d > 1 else "a", 6, 0.08, 0.5, 8), T.beat(b), 0, 0.3, 0.5)
        main.add(organ(m - 12, T.beat(d) * 0.96, r, ORGAN_REED, 0.03, 0.3, 0, 0, 3.0, 0.04), T.beat(b), -0.2, 0.14, 0.4)
        if b >= 16:  # second phrase: organum a fifth below
            main.add(choir(m - 7, T.beat(d) * 0.96, r, "o", 4, 0.08, 0.5, 6), T.beat(b), 0, 0.17, 0.5)
        b += d
    for bar in range(8):
        for bt, v in ((0, 1.0), (2, 0.7)):
            main.add(k.get("anvil", base=520.0), T.bar(bar, bt), 0.3, 0.14 * v, 0.4)
            main.add(k.get("taiko", pitch=0.8), T.bar(bar, bt), 0, 0.5 * v, 0.25)
        if bar % 2 == 0:
            main.add(bell(38, r, 6.0), T.bar(bar), -0.3, 0.16, 0.6)
    roots = [38, 34, 39, 33]  # phase2 is 4 bars: it cycles twice under the chant
    triads = {38: [62, 65, 69], 34: [62, 65, 70], 39: [63, 67, 70], 33: [61, 64, 69]}
    sixteenths = [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 3, 0, 1, 0, 0, 0]
    for bar in range(4):
        for s16 in range(16):
            p2.add(strings(38 + sixteenths[s16], T.beat(0.22), r, 3, 9, 0.004, 0.05, 0.11), T.step(bar, s16),
                   -0.3, 0.15 if s16 % 4 == 0 else 0.09, 0.15)
        for s16 in range(0, 16, 2):
            acc = s16 in (0, 6, 12)
            p2.add(k.get("taiko", pitch=1.0 if acc else 1.35), T.step(bar, s16), 0.1, 0.5 if acc else 0.2, 0.2)
        for bt in (0, 1.5):
            for m in triads[roots[bar]]:
                p2.add(brass(m - 12, 0.35, r, 2, 11, 6, 0.02, 0.15, 8, 0.35), T.bar(bar, bt), 0, 0.13, 0.3)
    i = np.arange(p2.L)
    roar = fft_filter(r.standard_normal(p2.L), 80, 900, 2)
    swell = (0.5 + 0.5 * np.sin(TAU * 2 * i / p2.L - np.pi / 2)) ** 2  # one swell per 2 bars
    p2.add(peak_norm(roar * swell), 0, 0, 0.12, 0.2, 0)
    for m in (86, 87):
        p3.add(choir(m - 12, T.bar(4) - 0.3, r, "i", 4, 0.8, 0.8, 35, 0.8, 60), 0, 0.5 if m % 2 else -0.5, 0.18, 0.6)
    for bar in range(4):
        for bt in range(4):
            p3.add(bell([62, 68, 63, 57][bt], r, 2.5, 2.2), T.bar(bar, bt), r.uniform(-0.6, 0.6), 0.12, 0.5)
        for s16 in range(16):
            p3.add(k.get("hat"), T.step(bar, s16), 0.4, 0.07, 0.1)
        if bar % 2 == 0:
            p3.add(k.get("sub_drop"), T.bar(bar), 0, 0.45, 0.05)
    for s16 in range(16):
        p3.add(k.get("snare", rattle=0.1), T.step(3, s16), -0.2, 0.06 + 0.02 * s16, 0.2)
    return T


def t_defeat():
    """Game over: a D-minor funeral dirge (Chopin's march rhythm on muffled drums), low organ,
    a moaning bass choir and a tolling bell. 50 BPM, 4 bars, loops while the end screen is up."""
    T = Track("defeat", 50, 4, seed=111, title="Unmade", out_rate=11025)
    r = T.rng
    s = T.stem("main", "base", IR_CATHEDRAL, -21.0)
    s.add(loop_drone(T, 26, [(1, 1.0), (2, 0.6), (3, 0.2)], r, 2, 1, 0.3), 0, 0, 0.2, 0.3, 0)
    chords = [[50, 53, 57], [50, 55, 58], [50, 53, 57], [49, 52, 55, 57]]
    for ci, ch in enumerate(chords):
        for m in ch:
            s.add(organ(m - 12, T.bar(1) - 0.2, r, ORGAN_PRINCIPAL, 0.5, 1.2, 4.0, 0.15), T.bar(ci), 0, 0.12, 0.5)
    moan = [(57, 4), (58, 2), (57, 2), (57, 2), (55, 1), (53, 1), (52, 2), (49, 2)]
    b = 0.0
    for m, d in moan:
        s.add(choir(m - 12, T.beat(d) * 0.97, r, "u", 5, 0.4, 1.0, 9, 0.15, 20), T.beat(b), 0, 0.3, 0.5)
        b += d
    for bar in range(4):
        for bt, v in ((0, 1.0), (1, 0.6), (1.75, 0.4), (2, 0.75)):
            s.add(fft_filter(T.kit.get("taiko", pitch=0.7), None, 500), T.bar(bar, bt), 0, 0.4 * v, 0.3)
        if bar % 2 == 0:
            s.add(bell(50, r, 7.0), T.bar(bar), 0.2, 0.15, 0.7)
    return T


# ---------------------------------------------------------------- stingers (not looped, mono)

def _sting(name, length, seed, title, target=-19.0, out_rate=None):
    T = Track(name, 60, 1, seed=seed, loop=False, length=length, title=title, out_rate=out_rate)
    return T, T.stem("main", "stinger", IR_CATHEDRAL, target)


def t_victory():
    """Boss killed: boom, then an E-major organ plenum with choir and bells."""
    T, s = _sting("victory", 9.0, 71, "The Host Falls", -18.0, 11025)
    r = T.rng
    s.add(T.kit.get("boom"), 0.0, 0, 0.8, 0.3, 0)
    s.add(T.kit.get("taiko", pitch=0.8), 0.0, 0, 0.6, 0.3, 0)
    s.add(T.kit.get("crash"), 0.0, 0, 0.3, 0.4, 0)
    for j, m in enumerate([28, 40, 52, 56, 59, 64, 68, 71]):
        s.add(organ(m, 2.8, r, ORGAN_PLENUM, 0.25, 1.6, 0, 0, 3.0, 0.02), 0.05, 0, 0.13, 0.5, 0)
    for m in (64, 68, 71, 76):
        s.add(choir(m, 2.6, r, "a", 4, 0.3, 1.4, 16), 0.1, 0, 0.13, 0.6, 0)
    s.add(bell(52, r, 5.0), 0.05, 0, 0.3, 0.6, 0)
    s.add(bell(64, r, 3.5), 0.9, 0, 0.15, 0.7, 0)
    return T


def t_sting_objective():
    """Objective done: a short Bb - C - D cadence (dark plagal into a major chord), taiko, bell."""
    T, s = _sting("sting_objective", 5.0, 121, "Desecrated", -19.0)
    r = T.rng
    s.add(T.kit.get("taiko", pitch=0.8), 0.0, 0, 0.6, 0.3, 0)
    for t0, ch, d in ((0.0, [46, 58, 62, 65], 0.5), (0.55, [48, 60, 64, 67], 0.5), (1.1, [38, 50, 62, 66, 69, 74], 1.4)):
        for m in ch:
            s.add(organ(m, d, r, ORGAN_PRINCIPAL, 0.03, 0.9 if d > 1 else 0.2, 0, 0, 3.0, 0.03), t0, 0, 0.12, 0.45, 0)
    for m in (62, 66, 69):
        s.add(choir(m, 1.4, r, "a", 4, 0.1, 1.0, 14), 1.1, 0, 0.13, 0.5, 0)
    s.add(bell(62, r, 3.0), 1.1, 0, 0.18, 0.6, 0)
    return T


def _relic(name, seed, title, length, notes, gap, extra, target):
    T, s = _sting(name, length, seed, title, target)
    r = T.rng
    for i, m in enumerate(notes):
        s.add(harp(m, r, 1.8, 1.0), i * gap, 0, 0.25, 0.45, 0)
    extra(T, s, r)
    return T


def t_sting_relics():
    """Relic found, one stinger per rarity: more notes, more voices and more weight as it rises.
    The higher tiers get a low Eb under the D chord: the demon's corrupted take on a holy prize."""
    def none(T, s, r):
        pass

    def uncommon(T, s, r):
        s.add(music_box(81, r, 1.6), 0.36, 0, 0.18, 0.5, 0)

    def rare(T, s, r):
        for m in (62, 66, 69):
            s.add(choir(m, 1.3, r, "a", 4, 0.4, 1.0, 14), 0.0, 0, 0.1, 0.55, 0)
        s.add(bell(74, r, 2.5), 0.32, 0, 0.12, 0.6, 0)

    def epic(T, s, r):
        for m in (62, 66, 69, 73):
            s.add(choir(m, 1.8, r, "a", 4, 0.3, 1.2, 14), 0.1, 0, 0.1, 0.55, 0)
        s.add(organ(39, 2.0, r, ORGAN_FLUTE, 0.3, 1.0, 0, 0, 3.0, 0.0), 0.1, 0, 0.12, 0.4, 0)
        s.add(bell(62, r, 3.5), 0.0, 0, 0.16, 0.6, 0)

    def legendary(T, s, r):
        s.add(T.kit.get("boom"), 0.0, 0, 0.7, 0.3, 0)
        s.add(T.kit.get("crash"), 0.0, 0, 0.22, 0.4, 0)
        for m in (26, 38, 39, 50, 57, 62, 66, 69, 74):
            s.add(organ(m, 2.6, r, ORGAN_PLENUM, 0.15, 1.4, 0, 0, 3.0, 0.02), 0.05, 0, 0.1, 0.5, 0)
        for m in (66, 69, 74, 78):
            s.add(choir(m, 2.6, r, "a", 4, 0.2, 1.4, 16), 0.1, 0, 0.12, 0.55, 0)
        s.add(bell(50, r, 5.0), 0.05, 0, 0.25, 0.6, 0)
        s.add(bell(62, r, 3.5), 0.6, 0, 0.15, 0.7, 0)

    scale = [62, 64, 66, 67, 69, 71, 73, 74, 76, 78, 79, 81, 83, 86]
    return [
        _relic("sting_relic_common", 131, "Relic", 2.6, [69, 76, 81], 0.12, none, -24.0),
        _relic("sting_relic_uncommon", 132, "Relic", 3.2, [62, 66, 69, 74], 0.09, uncommon, -22.5),
        _relic("sting_relic_rare", 133, "Relic", 4.2, [74, 78, 81, 86, 90], 0.08, rare, -21.0),
        _relic("sting_relic_epic", 134, "Relic", 5.2, scale[:12], 0.045, epic, -20.0),
        _relic("sting_relic_legendary", 135, "Relic", 6.5, scale, 0.04, legendary, -18.5),
    ]


def t_sting_level_up():
    """Level-up: a soft rising choir fifth with a harp note; sits under Sfx's level_up."""
    T, s = _sting("sting_level_up", 3.0, 141, "Ascent", -22.0)
    r = T.rng
    for m in (57, 64):
        s.add(choir(m, 0.35, r, "a", 4, 0.05, 0.3, 10), 0.0, 0, 0.12, 0.5, 0)
    for m in (62, 69, 74):
        s.add(choir(m, 0.9, r, "a", 4, 0.08, 0.9, 14), 0.33, 0, 0.12, 0.55, 0)
    s.add(harp(74, r, 1.6), 0.33, 0, 0.2, 0.5, 0)
    return T


def t_sting_purchase():
    """Hub purchase: an organ 'devil's amen' (A -> D minor) and a small bell. A deal is struck."""
    T, s = _sting("sting_purchase", 3.0, 151, "A Deal Struck", -20.0)
    r = T.rng
    for m in (45, 57, 61, 64):
        s.add(organ(m, 0.25, r, ORGAN_PRINCIPAL, 0.02, 0.15, 0, 0, 3.0, 0.04), 0.0, 0, 0.13, 0.45, 0)
    for m in (38, 50, 57, 62, 65):
        s.add(organ(m, 0.8, r, ORGAN_PRINCIPAL, 0.02, 0.8, 4.5, 0.15, 3.0, 0.04), 0.3, 0, 0.13, 0.45, 0)
    s.add(bell(74, r, 2.0), 0.3, 0, 0.12, 0.5, 0)
    return T


# ---------------------------------------------------------------- round 3: new maps

def t_isles():
    """Map: The Gilded Isles (battle_isles). A floating 3/4 waltz in D Lydian (heaven's own
    cliche): harp, soprano choir, wind chimes, the last chord sagging; combat: waltz drums and
    pizzicato on a D pedal; frenzy: rubbing brass, falling shrieks, hats."""
    T = Track("battle_isles", 108, 16, bpb=3, seed=161, title="Waltz of the Gilded Isles")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_HALL, -20.0)
    combat = T.stem("combat", "combat", IR_ROOM, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_CATHEDRAL, -23.5, bars=4)
    calm.add(loop_drone(T, 38, [(1, 1.0), (2, 0.4)], r, 2, 2, 0.4), 0, 0, 0.12, 0.3, 0)
    chords = [[50, 54, 57, 62], [52, 56, 59, 62], [50, 54, 57, 62], [52, 56, 59, 62],
              [47, 50, 54, 59], [43, 47, 50, 55], [40, 47, 50, 55], [45, 49, 52, 57]]
    for ci, ch in enumerate(chords):
        bad = 0.6 if ci == 7 else 0.0
        for m in ch[1:]:
            calm.add(choir(m + 12, T.bar(2) - 0.15, r, "a", 4, 0.6, 1.0, 14, bad, 30 * bad), T.bar(ci * 2), 0, 0.1, 0.5)
        for half in (0, 1):
            bar = ci * 2 + half
            calm.add(harp(ch[0] - 12, r, 2.5, 0.6), T.bar(bar), -0.2, 0.3, 0.3)
            for bt, m in ((1, ch[1] + 12), (2, ch[2] + 12)):
                calm.add(harp(m, r, 1.8), T.bar(bar, bt), 0.3, 0.18, 0.35)
    for bar in range(16):
        if r.random() < 0.5:  # wind chimes
            calm.add(bell(int(r.choice([86, 88, 90, 93])), r, 1.2, 1.2), T.bar(bar, r.uniform(0, 3)), r.uniform(-0.8, 0.8), 0.04, 0.7)
    for bar, bt, m in ((3, 0, 86), (3, 1, 88), (3, 2, 90), (11, 0, 93), (11, 1, 90), (11, 2, 86)):
        calm.add(music_box(m, r, 1.6, 12 if bar > 8 else 2), T.bar(bar, bt), 0.5, 0.12, 0.6)
    for bar in range(4):
        combat.add(k.get("taiko"), T.bar(bar), 0, 0.55, 0.2)
        for bt in (1, 2):
            combat.add(k.get("taiko", pitch=1.6), T.bar(bar, bt), 0.3, 0.18, 0.15)
        combat.add(strings(38, T.beat(0.3), r, 3, 9, 0.004, 0.05, 0.12), T.bar(bar), -0.2, 0.25, 0.15)
        for bt, m in ((1, 57), (2, 62)):
            combat.add(strings(m, T.beat(0.25), r, 3, 9, 0.004, 0.05, 0.1), T.bar(bar, bt), -0.2, 0.15, 0.15)
        if bar % 2:
            combat.add(k.get("anvil", base=900.0), T.bar(bar, 2), 0.4, 0.1, 0.3)
        else:
            combat.add(k.get("boom"), T.bar(bar), 0, 0.4, 0.2)
    for bar, m in ((0, 86), (2, 83)):
        frenzy.add(choir(m, T.beat(2.5), r, "a", 4, 0.1, 0.5, 25, 0.5, 0, -700), T.bar(bar, 0.5), 0.4 if bar else -0.4, 0.18, 0.6)
    for bar in range(4):
        for m in (62, 63, 69):
            frenzy.add(brass(m, 0.35, r, 2, 12, 7, 0.02, 0.15, 10, 0.3), T.bar(bar), 0, 0.13, 0.3)
        for s8 in range(6):
            frenzy.add(k.get("hat"), T.bar(bar, s8 * 0.5), 0.5, 0.1 if s8 % 2 else 0.06, 0.05)
    frenzy.add(k.get("crash"), T.bar(0), -0.4, 0.22, 0.3)
    return T


def t_spire():
    """Map: The Storm Spire (battle_spire). C# minor at 132 BPM: storm wind, a low choir and
    distant thunder; combat: relentless 16th strings, 3-3-2 taiko; frenzy: brass, a choir power
    chord, chains, a thunder drop."""
    T = Track("battle_spire", 132, 8, seed=171, title="The Spire in the Storm")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_CATHEDRAL, -20.0)
    combat = T.stem("combat", "combat", IR_HALL, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_HALL, -23.5, bars=4)
    i = np.arange(T.L)
    wind = fft_filter(r.standard_normal(T.L), 200, 2500, 2)
    gust = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(TAU * 3 * i / T.L)) * (0.5 + 0.5 * np.sin(TAU * 7 * i / T.L + 2.0))
    calm.add(peak_norm(wind * gust), 0, 0, 0.1, 0.2, 0)
    calm.add(loop_drone(T, 25, [(1, 1.0), (2, 0.6), (3, 0.2)], r, 2, 2, 0.4), 0, 0, 0.18, 0.3, 0)
    chords = [[49, 52, 56], [45, 49, 52], [42, 45, 49], [44, 48, 51]]
    for ci, ch in enumerate(chords):
        for m in ch:
            calm.add(choir(m, T.bar(2) - 0.2, r, "o", 4, 0.8, 1.2, 10), T.bar(ci * 2), 0, 0.12, 0.5)
            calm.add(organ(m + 12, T.bar(2) - 0.2, r, ORGAN_FLUTE, 0.8, 1.0, 5.0, 0.2), T.bar(ci * 2), 0.3, 0.04, 0.5)
    for bar, bt in ((1, 2.5), (5, 1.0)):  # distant thunder
        calm.add(k.get("boom"), T.bar(bar, bt), 0.4, 0.35, 0.6)
        calm.add(peak_norm(fft_filter(r.standard_normal(int(3 * SR)), 30, 250) * np.exp(-np.arange(int(3 * SR)) / SR / 0.9)),
                 T.bar(bar, bt), 0.4, 0.2, 0.6)
    calm.add(bell(61, r, 5.0), 0, -0.5, 0.06, 0.8, 0)
    pat = [0, 0, 12, 0, 0, 0, 7, 0, 0, 0, 12, 0, 3, 0, 7, 0]
    for bar in range(4):
        for s16 in range(16):
            combat.add(strings(49 + pat[s16], T.beat(0.22), r, 3, 10, 0.004, 0.05, 0.1), T.step(bar, s16), -0.3,
                       0.15 if s16 % 4 == 0 else 0.09, 0.15)
        for s16 in range(0, 16, 2):
            acc = s16 in (0, 6, 12)
            combat.add(k.get("taiko", pitch=1.0 if acc else 1.4), T.step(bar, s16), 0.1, 0.5 if acc else 0.18, 0.2)
        for s16 in (4, 12):
            combat.add(k.get("snare", rattle=0.15), T.step(bar, s16), -0.2, 0.22, 0.3)
        combat.add(k.get("boom"), T.bar(bar), 0, 0.4, 0.2)
    for bar in range(4):
        for s16 in (0, 6, 12):
            for m in (49, 56):
                frenzy.add(brass(m, 0.3, r, 3, 12, 7, 0.02, 0.15, 10, 0.3), T.step(bar, s16), 0, 0.15, 0.3)
        for m in (61, 68, 73):
            frenzy.add(choir(m, T.bar(1) - 0.1, r, "a", 4, 0.15, 0.5, 18, 0.2), T.bar(bar), 0, 0.09, 0.5)
        for s16 in (2, 10):
            frenzy.add(k.get("chains"), T.step(bar, s16), r.uniform(-0.7, 0.7), 0.1, 0.2)
    frenzy.add(k.get("sub_drop"), 0, 0, 0.4, 0.05, 0)
    frenzy.add(k.get("crash"), 0, 0.4, 0.22, 0.3, 0)
    return T


def t_gate():
    """Map: Heaven's Gate (battle_gate, the finale map). G minor at 72 BPM: a vast organ and choir
    chorale before the Seventh Gate, low bells; combat: a processional march on a G pedal with a
    b6 bite; frenzy: a tritone fanfare, high choir, clanging bells."""
    T = Track("battle_gate", 72, 8, seed=181, title="Before the Seventh Gate")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_CATHEDRAL, -20.0)
    combat = T.stem("combat", "combat", IR_HALL, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_CATHEDRAL, -23.5, bars=4)
    calm.add(loop_drone(T, 31, [(1, 1.0), (2, 0.7), (3, 0.3), (4, 0.2)], r, 2, 2, 0.25), 0, 0, 0.2, 0.3, 0)
    chords = [[43, 55, 58, 62], [39, 55, 58, 63], [36, 55, 60, 63], [38, 54, 57, 62],
              [43, 55, 58, 62], [46, 53, 58, 62], [39, 55, 58, 63], [38, 54, 57, 60, 63]]
    for ci, ch in enumerate(chords):
        calm.add(organ(ch[0], T.bar(1) - 0.1, r, ORGAN_PRINCIPAL, 0.3, 1.0, 0, 0, 3.0, 0.02), T.bar(ci), 0, 0.14, 0.45)
        for m in ch[1:]:
            calm.add(organ(m, T.bar(1) - 0.1, r, ORGAN_PRINCIPAL, 0.4, 1.0, 4.0, 0.08), T.bar(ci), 0, 0.07, 0.5)
            calm.add(choir(m + (12 if m < 60 else 0), T.bar(1) - 0.1, r, "a" if ci % 2 == 0 else "o", 4, 0.5, 1.0, 12),
                     T.bar(ci), 0, 0.08, 0.55)
    for bar in (0, 2, 4, 6):
        calm.add(bell(31 + 12, r, 8.0), T.bar(bar), -0.3, 0.14, 0.7)
    for bar in range(4):
        for bt in (0, 2):
            combat.add(k.get("taiko", pitch=0.85), T.bar(bar, bt), 0, 0.5 if bt == 0 else 0.38, 0.25)
        for s16 in (13, 14, 15):
            combat.add(k.get("snare", rattle=0.12), T.step(bar, s16), 0.2, 0.08 + 0.03 * (s16 - 13), 0.3)
        for i, rel in enumerate([0, 0, 7, 0, 0, 0, 8, 7]):
            combat.add(strings(43 + rel, T.beat(0.45), r, 3, 8, 0.006, 0.08, 0.2), T.bar(bar, i * 0.5), -0.3,
                       0.2 if i % 2 == 0 else 0.13, 0.2)
        if bar % 2 == 0:
            combat.add(k.get("boom"), T.bar(bar), 0, 0.5, 0.25)
    fan = [(67, 0.5), (67, 0.5), (74, 1.0), (79, 1.5), (73, 2.5), (74, 2.0)]  # G .. C#: the tritone
    for start in (0, 2):
        b = 0.0
        for m, d in fan:
            frenzy.add(brass(m, T.beat(d) * 0.92, r, 4, 13, 8, 0.03, 0.3, 8, 0.1, 25, 8), T.bar(start, b), 0, 0.2, 0.4)
            b += d
    for bar in range(4):
        for m in (67, 74, 79):
            frenzy.add(choir(m, T.bar(1) - 0.1, r, "a", 4, 0.3, 0.6, 18, 0.15), T.bar(bar), 0, 0.08, 0.55)
        for bt in range(4):
            frenzy.add(bell([67, 73, 62, 68][bt], r, 2.2, 2.0), T.bar(bar, bt + 0.5), r.uniform(-0.6, 0.6), 0.07, 0.5)
    frenzy.add(k.get("crash"), 0, 0.3, 0.25, 0.3, 0)
    return T


def t_wastes():
    """Map: The Ashen Wastes (battle_wastes). A Phrygian desolation: ash wind, a detuned plucked
    dulcimer, a wordless moan sliding down, a low bell; combat: frame drums and a distorted A pedal
    bass rubbing against Bb; frenzy: chains, shrieks, brass rub."""
    T = Track("battle_wastes", 88, 8, seed=191, title="Where the Ash Falls")
    r = T.rng
    k = T.kit
    calm = T.stem("calm", "base", IR_HALL, -20.0)
    combat = T.stem("combat", "combat", IR_ROOM, -21.0, bars=4)
    frenzy = T.stem("frenzy", "frenzy", IR_CATHEDRAL, -23.5, bars=4)
    i = np.arange(T.L)
    ash = fft_filter(r.standard_normal(T.L), 80, 900, 2) * (0.5 + 0.5 * np.sin(TAU * 2 * i / T.L))
    calm.add(peak_norm(ash), 0, 0, 0.1, 0.2, 0)
    calm.add(loop_drone(T, 33, [(1, 1.0), (2, 0.5), (3, 0.3)], r, 3, 2, 0.35), 0, 0, 0.2, 0.3, 0)
    motif = [(69, 1), (70, 0.5), (72, 0.5), (70, 1), (69, 1), (67, 1.5), (69, 0.5), (65, 1), (64, 1),
             (69, 1), (70, 1), (72, 1), (74, 1), (72, 0.5), (70, 0.5), (69, 3), (67, 1), (65, 1), (64, 2),
             (62, 1), (64, 1), (65, 1), (64, 1), (69, 4)]
    b = 0.0
    for m, d in motif:
        for det in (0.0, 0.18):  # a detuned pair: an old, slack dulcimer
            calm.add(harp(m - 12 + det, r, 1.6, 1.0), T.beat(b) + det * 0.05, 0.2 - det, 0.16, 0.4)
        b += d
    for bar, m in ((2, 64), (6, 65)):
        calm.add(choir(m, T.bar(2) - 0.5, r, "u", 4, 1.0, 1.0, 8, 0.3, 0, -200), T.bar(bar), -0.3, 0.12, 0.6)
    calm.add(bell(45, r, 7.0), 0, 0.4, 0.08, 0.8, 0)
    for bar in range(4):
        for s16 in range(16):
            if s16 % 4 == 0 or s16 in (3, 6, 7, 10, 14):
                combat.add(k.get("taiko", pitch=1.7 if s16 % 4 else 1.2), T.step(bar, s16), 0.2, 0.25 if s16 % 4 == 0 else 0.12, 0.15)
        for s16 in (0, 6, 10):
            combat.add(k.get("taiko", pitch=0.9), T.step(bar, s16), 0, 0.5, 0.15)
        for i8 in range(8):
            accent = i8 in (0, 3, 6)
            combat.add(drive(strings(33, T.beat(0.42), r, 2, 16, 0.004, 0.06, 0.2, 0, 12) * 2.5, 2.0), T.bar(bar, i8 * 0.5),
                       0, 0.26 if accent else 0.16, 0.05)
            if i8 == 6:
                combat.add(drive(strings(34, T.beat(0.3), r, 1, 10, 0.004, 0.05, 0.15), 2), T.bar(bar, 3), 0.3, 0.08, 0.1)
        for s16 in (2, 6, 10, 14):
            combat.add(k.get("hat", decay=0.05), T.step(bar, s16), 0.4, 0.06, 0.1)
    for m in (81, 82):
        frenzy.add(choir(m, T.bar(4) - 0.4, r, "i", 4, 1.4, 1.0, 30, 0.6, 40), 0, 0.4 if m % 2 else -0.4, 0.16, 0.6)
    for bar in range(4):
        for s16 in (0, 10):
            for m in (57, 58):
                frenzy.add(brass(m, 0.35, r, 2, 12, 7, 0.02, 0.15, 10, 0.4), T.step(bar, s16), 0, 0.14, 0.3)
        for s16 in (2, 6, 10, 14):
            frenzy.add(k.get("chains"), T.step(bar, s16), r.uniform(-0.7, 0.7), 0.12, 0.2)
    frenzy.add(k.get("crash"), 0, -0.3, 0.22, 0.3, 0)
    return T


# ---------------------------------------------------------------- round 3: new bosses

def t_boss_archon():
    """Boss: Azrafel, the Gate Archon (the finale, the grandest track). C minor with a Neapolitan
    Db at 116 BPM: full organ plenum, SATB choir, a brass anthem, taiko and booms, the Gate's bells.
    'host' (frenzy, 4 bars): the heavenly host joins (high choir, fanfare stabs, snare). 'enrage'
    (4 bars, 'draws the light of the Throne'): tritone bells, shrieks, sub drops."""
    T = Track("boss_archon", 116, 8, seed=201, title="Azrafel, Warden of the Seventh Gate")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_CATHEDRAL, -18.0)
    host = T.stem("host", "frenzy", IR_CATHEDRAL, -22.0, bars=4)
    rage = T.stem("enrage", "enrage", IR_CATHEDRAL, -22.0, bars=4)
    chords = [[36, 48, 55, 60, 63], [32, 48, 56, 60, 63], [37, 49, 56, 61, 65], [31, 50, 55, 59, 62],
              [36, 48, 55, 60, 63], [39, 51, 55, 58, 63], [32, 48, 56, 60, 63], [31, 50, 53, 56, 59, 62]]
    for ci, ch in enumerate(chords):
        for m in ch:
            main.add(organ(m, T.bar(1) - 0.05, r, ORGAN_PLENUM, 0.03, 0.4, 0, 0, 3.0, 0.03), T.bar(ci), 0, 0.07, 0.4)
        for m in ch[2:]:
            for bt, v in ((0, "a"), (2, "o")):
                main.add(choir(m + 12 if m < 57 else m, T.beat(1.8), r, v, 5, 0.05, 0.4, 10), T.bar(ci, bt), 0, 0.09, 0.45)
    anthem = [(72, 1), (75, 1), (79, 2), (80, 1.5), (79, 0.5), (77, 1), (73, 1), (74, 4), (72, 1), (75, 1),
              (79, 2), (82, 1.5), (80, 0.5), (79, 1), (77, 1), (80, 2), (79, 2), (74, 2), (71, 2)]
    b = 0.0
    for m, d in anthem:
        main.add(brass(m - 12, T.beat(d) * 0.92, r, 4, 13, 8, 0.03, 0.25, 8, 0.15, 20, 8), T.beat(b), 0.15, 0.18, 0.35)
        b += d
    for bar in range(8):
        for s16 in range(0, 16, 2):
            acc = s16 in (0, 6, 12)
            main.add(k.get("taiko", pitch=0.95 if acc else 1.3), T.step(bar, s16), 0, 0.45 if acc else 0.16, 0.2)
        main.add(k.get("boom"), T.bar(bar), 0, 0.45, 0.2)
        main.add(k.get("anvil", base=600.0), T.bar(bar, 1), 0.3, 0.1, 0.3)
        main.add(k.get("anvil", base=600.0), T.bar(bar, 3), 0.3, 0.1, 0.3)
    for bar in (0, 4):
        main.add(bell(36, r, 7.0), T.bar(bar), -0.3, 0.18, 0.6)
        main.add(bell(48, r, 5.0), T.bar(bar) + 0.02, 0.3, 0.1, 0.6)
    for bar in range(4):
        for m in (79, 84, 87):
            host.add(choir(m, T.bar(1) - 0.1, r, "a", 4, 0.2, 0.5, 22, 0.1), T.bar(bar), 0, 0.09, 0.55)
        for s16 in (0, 3, 6, 10):
            for m in (60, 67, 72):
                host.add(brass(m, 0.25, r, 2, 13, 7, 0.015, 0.12, 8, 0.2), T.step(bar, s16), 0, 0.11, 0.3)
        for s16 in range(16):
            host.add(k.get("snare", rattle=0.1), T.step(bar, s16), -0.2, 0.1 if s16 % 4 == 0 else 0.04, 0.2)
    host.add(k.get("crash"), 0, 0.4, 0.22, 0.3, 0)
    for m in (84, 85):
        rage.add(choir(m, T.bar(4) - 0.3, r, "i", 4, 0.8, 0.8, 35, 0.8, 60), 0, 0.5 if m % 2 else -0.5, 0.18, 0.6)
    for bar in range(4):
        for bt in range(4):
            rage.add(bell([60, 66, 61, 67][bt], r, 2.5, 2.2), T.bar(bar, bt), r.uniform(-0.6, 0.6), 0.12, 0.5)
        if bar % 2 == 0:
            rage.add(k.get("sub_drop"), T.bar(bar), 0, 0.45, 0.05)
    return T


def t_boss_abbot():
    """Boss: Ysmir, the Frost Abbot. B Phrygian at 96 BPM: rhythmic oktavist chant stabs, ice
    bells in 8ths, 3-3-2 frame drums and taiko, tremolo low strings. 'phase2' (4 bars): shrieking
    sopranos, clanging bells, snare rolls."""
    T = Track("boss_abbot", 96, 8, seed=211, title="Ysmir's Matins")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_CATHEDRAL, -18.5)
    p2 = T.stem("phase2", "phase2", IR_CATHEDRAL, -22.0, bars=4)
    roots = [35, 35, 36, 35, 35, 35, 31, 30]
    for bar in range(8):
        root = roots[bar]
        for bt, v in ((0, "o"), (1.5, "a"), (3, "o")):
            for m in (root, root + 7, root + 12):
                main.add(choir(m, T.beat(1.2), r, v, 5, 0.03, 0.4, 6), T.bar(bar, bt), 0, 0.14, 0.45)
        for s16 in range(16):
            main.add(strings(root + 12, T.beat(0.24), r, 3, 8, 0.004, 0.05, 0.12), T.step(bar, s16), -0.3,
                     0.11 if s16 % 4 == 0 else 0.06, 0.15)
        for s8 in range(8):
            main.add(music_box([83, 86, 84, 90][s8 % 4], r, 1.2, 4), T.bar(bar, s8 * 0.5), r.uniform(-0.7, 0.7), 0.05, 0.5)
        for s16 in range(0, 16, 2):
            acc = s16 in (0, 6, 12)
            main.add(k.get("taiko", pitch=1.0 if acc else 1.5), T.step(bar, s16), 0, 0.45 if acc else 0.15, 0.2)
        if bar % 2 == 0:
            main.add(k.get("boom"), T.bar(bar), 0, 0.45, 0.2)
            main.add(bell(47, r, 6.0), T.bar(bar), -0.3, 0.12, 0.6)
    for m in (83, 84):
        p2.add(choir(m, T.bar(4) - 0.3, r, "i", 4, 1.0, 0.8, 30, 0.6, 40), 0, 0.5 if m % 2 else -0.5, 0.18, 0.6)
    for bar in range(4):
        for bt in range(4):
            p2.add(bell([71, 72, 66, 65][bt], r, 2.2, 2.0), T.bar(bar, bt + 0.5), r.uniform(-0.6, 0.6), 0.1, 0.5)
        for s16 in range(8, 16):
            p2.add(k.get("snare", rattle=0.1), T.step(bar, s16), -0.2, 0.05 + 0.02 * (s16 - 8), 0.2)
    p2.add(k.get("crash"), 0, 0.4, 0.2, 0.3, 0)
    return T


def t_boss_wyrm():
    """Boss: Aurelion, the Dawn Wyrm. A heroic D-major brass anthem curdled by a Lydian-dominant
    G# and C natural, harp sunrise glissandi, roaring low brass growls, big taiko at 126 BPM.
    'phase2' (4 bars): high brass trills, double-time hats, crash and sub drops."""
    T = Track("boss_wyrm", 126, 8, seed=221, title="The Second Sunrise")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_HALL, -18.5)
    p2 = T.stem("phase2", "phase2", IR_HALL, -22.0, bars=4)
    chords = [[38, 62, 66, 69], [38, 62, 66, 68], [36, 60, 64, 67], [38, 62, 66, 69],
              [34, 58, 62, 65], [36, 60, 64, 68], [38, 62, 66, 69], [33, 61, 64, 67]]
    for ci, ch in enumerate(chords):
        for m in ch[1:]:
            main.add(brass(m - 12, T.bar(1) - 0.1, r, 3, 8, 5, 0.1, 0.4, 6, 0, 10, 4), T.bar(ci), 0, 0.08, 0.35)
        main.add(choir(ch[0] + 12, T.bar(1) - 0.1, r, "o", 4, 0.2, 0.5, 8), T.bar(ci), 0, 0.12, 0.4)
    anthem = [(74, 1.5), (78, 0.5), (81, 2), (80, 1), (78, 1), (76, 2), (81, 2), (78, 1.5), (76, 0.5),
              (74, 2), (72, 2), (74, 1), (76, 1), (78, 2), (80, 2), (81, 4), (73, 2), (74, 2)]
    b = 0.0
    for m, d in anthem:
        main.add(brass(m - 12, T.beat(d) * 0.92, r, 4, 14, 9, 0.03, 0.25, 8, 0.1, 25, 10), T.beat(b), 0.1, 0.2, 0.35)
        b += d
    for bar in (0, 4):
        for j in range(12):  # sunrise harp glissando
            main.add(harp([62, 64, 66, 68, 69, 71, 73, 74, 76, 78, 80, 81][j], r, 1.5), T.bar(bar) + j * 0.035, 0.4, 0.12, 0.4)
        main.add(brass(26, T.beat(2), r, 3, 6, 4, 0.15, 0.5, 20, 0.9, 120, 0), T.bar(bar + 2), 0, 0.2, 0.4)  # the roar
    for bar in range(8):
        for s16, v in ((0, 1.0), (3, 0.5), (6, 0.8), (8, 0.9), (11, 0.5), (14, 0.7)):
            main.add(k.get("taiko"), T.step(bar, s16), 0, 0.5 * v, 0.2)
        for s16 in (4, 12):
            main.add(k.get("snare"), T.step(bar, s16), -0.2, 0.2, 0.3)
        if bar % 2 == 0:
            main.add(k.get("boom"), T.bar(bar), 0, 0.45, 0.2)
    for bar in range(4):
        for s16 in range(0, 16, 2):
            m = 86 if (s16 // 2) % 2 == 0 else 88
            p2.add(brass(m - 12, 0.12, r, 2, 12, 8, 0.01, 0.06, 8, 0, 5, 0), T.step(bar, s16), 0.3, 0.08, 0.3)
        for s16 in range(16):
            p2.add(k.get("hat"), T.step(bar, s16), 0.5, 0.09 if s16 % 2 == 0 else 0.05, 0.05)
        if bar % 2 == 0:
            p2.add(k.get("sub_drop"), T.bar(bar), 0, 0.4, 0.05)
    p2.add(k.get("crash"), 0, -0.4, 0.22, 0.3, 0)
    return T


def t_boss_verdance():
    """Boss: Mother Verdance. A creeping F-minor waltz (3/4, 120 BPM): harp, hollow log drums, a
    maternal lullaby in a sagging alto choir, chromatic low strings, a warped music box.
    'phase2' (4 bars): thorns: chains, rubbing brass, a falling shriek, heavy taiko."""
    T = Track("boss_verdance", 120, 16, bpb=3, seed=231, title="Lullaby of the Root Mother")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_HALL, -18.5)
    p2 = T.stem("phase2", "phase2", IR_CATHEDRAL, -22.0, bars=4)
    roots = [41, 41, 37, 37, 39, 39, 36, 36, 41, 41, 34, 34, 37, 39, 36, 36]
    triads = {41: [53, 56, 60], 37: [53, 56, 61], 39: [51, 55, 58], 36: [52, 55, 58], 34: [53, 58, 61]}
    for bar in range(16):
        root = roots[bar]
        main.add(harp(root, r, 2.4, 0.6), T.bar(bar), -0.2, 0.3, 0.3)
        for bt in (1, 2):
            for m in triads[root]:
                main.add(harp(m, r, 1.4), T.bar(bar, bt), 0.2, 0.08, 0.3)
        main.add(k.get("taiko", pitch=2.2), T.bar(bar), 0.3, 0.3, 0.2)  # hollow log drum
        main.add(k.get("taiko", pitch=2.6), T.bar(bar, 2), -0.3, 0.16, 0.2)
        main.add(strings(root, T.bar(1) - 0.05, r, 3, 6, 0.3, 0.4, None, 6), T.bar(bar), -0.3, 0.1, 0.3)
    lull = [(72, 2), (70, 1), (68, 3), (67, 2), (68, 1), (65, 3), (68, 2), (70, 1), (72, 2), (73, 1), (72, 3),
            (70, 3), (72, 2), (70, 1), (68, 3), (67, 2), (65, 1), (64, 3), (65, 6)]
    b = 0.0
    for i, (m, d) in enumerate(lull):
        main.add(choir(m - 12, T.beat(d) * 0.95, r, "u", 4, 0.2, 0.6, 12, 0.3, 25 if i > 9 else 0), T.beat(b), 0.1, 0.22, 0.5)
        b += d
    for bar, m in ((3, 84), (7, 80), (11, 85), (15, 79)):
        main.add(music_box(m, r, 1.8, 20), T.bar(bar, 1), 0.5, 0.12, 0.5)
    for bar in range(4):
        for bt in (0, 1, 2):
            main_v = 0.5 if bt == 0 else 0.25
            p2.add(k.get("taiko", pitch=0.9), T.bar(bar, bt), 0, main_v, 0.2)
        for m in (65, 66):
            p2.add(brass(m, 0.4, r, 2, 12, 7, 0.02, 0.2, 10, 0.4), T.bar(bar), 0, 0.13, 0.3)
        for bt in (0.5, 1.5, 2.5):
            p2.add(k.get("chains"), T.bar(bar, bt), r.uniform(-0.7, 0.7), 0.1, 0.2)
    p2.add(choir(84, T.beat(5), r, "a", 4, 0.1, 0.6, 25, 0.5, 0, -1000), T.bar(0, 0.5), 0.4, 0.18, 0.6)
    p2.add(k.get("crash"), 0, 0.4, 0.2, 0.3, 0)
    return T


# ---------------------------------------------------------------- round 3: endings and run won

def t_ending_climb():
    """The staged ending (scenes/dialogue/ending_stage.tscn): the climb past the seven kneeling
    Archons. 60 BPM, 8 bars: an organ pedal climbs one step per bar under a heartbeat and a
    drone. 'archons' (4 bars, after stage_archons): a male choir and bells. 'throne' (4 bars,
    after stage_throne): brass chorale, high choir, a crash on the downbeat."""
    T = Track("ending_climb", 60, 8, seed=241, title="Seven Steps")
    r = T.rng
    k = T.kit
    base = T.stem("main", "base", IR_CATHEDRAL, -20.0)
    arch = T.stem("archons", "archons", IR_CATHEDRAL, -22.0, bars=2)
    throne = T.stem("throne", "throne", IR_CATHEDRAL, -22.0, bars=2)
    base.add(loop_drone(T, 26, [(1, 1.0), (2, 0.7), (3, 0.3)], r, 2, 2, 0.3), 0, 0, 0.2, 0.3, 0)
    steps = [38, 40, 41, 43, 45, 46, 48, 49]
    uppers = [[50, 53, 57], [48, 52, 55], [48, 53, 57], [50, 55, 58], [49, 52, 57], [50, 53, 58], [48, 51, 55], [49, 52, 55, 57]]
    for bar in range(8):
        base.add(organ(steps[bar] - 12, T.bar(1) - 0.1, r, ORGAN_PRINCIPAL, 0.3, 1.0, 0, 0, 3.0, 0.02), T.bar(bar), 0, 0.2, 0.4)
        for m in uppers[bar]:
            base.add(organ(m, T.bar(1) - 0.1, r, ORGAN_FLUTE, 0.6, 1.0, 4.5, 0.15), T.bar(bar), 0, 0.07, 0.5)
        base.add(fft_filter(k.get("taiko", pitch=0.6), None, 350), T.bar(bar), 0, 0.25, 0.2)
        base.add(fft_filter(k.get("taiko", pitch=0.65), None, 350), T.bar(bar, 0.45), 0, 0.15, 0.2)
    for m in (38, 45, 50):
        arch.add(choir(m, T.bar(2) - 0.4, r, "o", 6, 1.5, 1.2, 6), 0, 0, 0.18, 0.5)
    arch.add(bell(50, r, 6.0), 0, -0.3, 0.12, 0.7)
    for bar in range(2):
        for m in (57, 62, 65):
            throne.add(brass(m - 12, T.bar(1) - 0.1, r, 3, 6, 4, 0.3, 0.6, 6, 0, 10, 4), T.bar(bar), 0, 0.1, 0.45)
        for m in (74, 77, 81):
            throne.add(choir(m, T.bar(1) - 0.1, r, "a", 4, 0.5, 0.8, 16), T.bar(bar), 0, 0.07, 0.6)
    throne.add(k.get("crash"), 0, 0, 0.18, 0.4, 0)
    return T


def t_ending_sit():
    """Ending resolution 'Sit': a dark coronation. A boom, the full organ on D minor, the crown
    bell, a choir that swells and darkens over a low b2 rumble, and a last tolling bell."""
    T, s = _sting("ending_sit", 20.0, 251, "The Throne Is Taken", -18.0, 11025)
    r = T.rng
    s.add(T.kit.get("boom"), 0.0, 0, 0.8, 0.3, 0)
    for j, m in enumerate([26, 38, 50, 53, 57, 62, 65, 69]):
        s.add(organ(m, 5.5, r, ORGAN_PLENUM, 1.2, 2.5, 0, 0, 3.0, 0.0), 0.1, 0, 0.11, 0.5, 0)
    for j, m in enumerate([22, 34, 46, 50, 53, 58, 62]):  # Bb/D: a shadow passes
        s.add(organ(m + (4 if j == 0 else 0), 3.5, r, ORGAN_PLENUM, 1.0, 2.5, 0, 0, 3.0, 0.0), 6.0, 0, 0.1, 0.5, 0)
    for m in [26, 38, 50, 53, 57, 62, 65]:
        s.add(organ(m, 5.0, r, ORGAN_PLENUM, 1.5, 3.0, 4.0, 0.12, 3.0, 0.0), 9.5, 0, 0.11, 0.5, 0)
    for t0, ch in ((0.3, (62, 65, 69, 74)), (6.0, (62, 65, 70, 74)), (9.5, (62, 65, 69, 75))):
        for m in ch:
            s.add(choir(m, 3.4 if t0 < 9 else 5.0, r, "a", 5, 1.0, 2.0, 12, 0.2 if t0 > 9 else 0.0), t0, 0, 0.1, 0.6, 0)
    s.add(organ(27, 6.0, r, ORGAN_FLUTE, 2.0, 2.5, 0, 0, 3.0, 0.0), 9.0, 0, 0.18, 0.4, 0)  # low Eb rumble
    s.add(bell(62, r, 5.0), 2.0, 0, 0.25, 0.7, 0)
    s.add(bell(50, r, 7.0), 14.0, 0, 0.3, 0.7, 0)
    return T


def t_ending_break():
    """Ending resolution 'Break': cataclysm. A crash and a sub drop, shattering bells, choirs
    screaming down an octave, thunder, then rubble and one last small bell."""
    T, s = _sting("ending_break", 17.0, 261, "The Throne Is Broken", -18.0, 11025)
    r = T.rng
    k = T.kit
    s.add(k.get("crash"), 0.0, 0, 0.5, 0.4, 0)
    s.add(k.get("boom"), 0.0, 0, 0.9, 0.3, 0)
    s.add(k.get("sub_drop"), 0.05, 0, 0.7, 0.1, 0)
    for _ in range(14):  # the bells of heaven shatter
        s.add(bell(int(r.integers(55, 92)), r, 2.0, 2.0), r.uniform(0.0, 3.0), 0, 0.12, 0.5, 0)
    for m in (88, 87, 81):
        s.add(choir(m, 3.0, r, "a", 4, 0.05, 1.0, 30, 0.8, 0, -1200), 0.2, 0, 0.14, 0.7, 0)
    for t0 in (1.6, 3.4):
        s.add(k.get("boom"), t0, 0, 0.5, 0.5, 0)
        s.add(k.get("crash"), t0, 0, 0.18, 0.5, 0)
    n = int(9.0 * SR)
    rubble = fft_filter(r.standard_normal(n), 25, 300) * np.exp(-np.arange(n) / SR / 2.5)
    s.add(peak_norm(rubble), 2.0, 0, 0.35, 0.3, 0)
    s.add(choir(38, 5.0, r, "u", 5, 2.0, 2.5, 6, 0.4, 40), 5.0, 0, 0.12, 0.6, 0)
    s.add(bell(74, r, 3.0), 11.0, 0, 0.12, 0.8, 0)
    return T


def t_basecamp_ended():
    """Basecamp Hell after the ending (Dialogue flag story.ended): the hub theme crowned. The same
    organ in C, but the cadences open into major chords, the crown bell answers and the heartbeat
    is gone. 60 BPM, 8 bars."""
    T = Track("basecamp_ended", 60, 8, seed=271, title="The Reconquest", out_rate=11025)
    r = T.rng
    s = T.stem("main", "base", IR_CATHEDRAL, -20.0)
    s.add(loop_drone(T, 24, [(1, 1.0), (2, 0.8), (3, 0.2), (4, 0.25)], r, 2, 2, 0.3), 0, 0, 0.28, 0.25, 0)
    chords = [[48, 52, 55, 60], [49, 53, 56, 61], [48, 51, 56, 60], [48, 53, 56, 60],
              [48, 52, 55, 64], [49, 53, 58, 61], [44, 48, 51, 56], [43, 47, 50, 55, 59]]
    for ci, ch in enumerate(chords):
        for m in ch:
            s.add(organ(m, T.bar(1) - 0.15, r, ORGAN_PRINCIPAL, 0.6, 1.3, 4.5, 0.12), T.bar(ci), 0, 0.14, 0.45)
        for m in ch[1:3]:
            s.add(choir(m + 12, T.bar(1), r, "a", 4, 0.8, 1.2, 12), T.bar(ci), 0, 0.09, 0.55)
    crown = [(72, 2), (76, 1), (79, 1), (77, 2), (76, 2), (73, 2), (72, 2), (68, 2), (67, 2)]
    b = 16.0
    for m, d in crown:
        s.add(organ(m, T.beat(d) * 0.95, r, ORGAN_REED, 0.08, 0.6, 5.0, 0.2, 4.0, 0.05), T.beat(b), 0.2, 0.08, 0.55)
        b += d
    for bar in (0, 4):
        s.add(bell(60, r, 6.0), T.bar(bar), -0.4, 0.14, 0.7)
        s.add(bell(67, r, 4.0), T.bar(bar, 1), 0.4, 0.08, 0.7)
    return T


def t_run_won():
    """Run won (ASCENDANT screen, loops): a dark processional triumph in E Mixolydian: organ
    plenum E - C - D - E, choir, tolling bells, soft processional drums. 72 BPM, 4 bars."""
    T = Track("run_won", 72, 4, seed=281, title="Ascendant", out_rate=11025)
    r = T.rng
    k = T.kit
    s = T.stem("main", "base", IR_CATHEDRAL, -19.0)
    chords = [[28, 40, 52, 56, 59, 64], [24, 36, 52, 55, 60, 64], [26, 38, 50, 54, 57, 62], [28, 40, 52, 56, 59, 64, 68]]
    for ci, ch in enumerate(chords):
        for m in ch:
            s.add(organ(m, T.bar(1) - 0.1, r, ORGAN_PLENUM, 0.15, 0.8, 0, 0, 3.0, 0.02), T.bar(ci), 0, 0.08, 0.5)
        for m in ch[3:]:
            s.add(choir(m + 12 if m < 60 else m, T.bar(1) - 0.1, r, "a", 4, 0.3, 0.8, 14), T.bar(ci), 0, 0.09, 0.55)
        for bt in (0, 2):
            s.add(k.get("taiko", pitch=0.8), T.bar(ci, bt), 0, 0.35 if bt == 0 else 0.22, 0.3)
    for bar in range(4):
        s.add(bell([64, 59, 62, 64][bar], r, 4.0), T.bar(bar), 0.3, 0.1, 0.7)
    return T


# ---------------------------------------------------------------- round 4: bosses from characters-new

def glitch(sig, T, rng, slice_beats=0.25, p_repeat=0.3, p_rev=0.15, p_drop=0.1, p_pitch=0.15, crush=0.35):
    """A broken record: cut a stereo signal into 16th-note slices and stutter, reverse, drop or
    re-pitch some of them, then blend in a bit-crushed copy. Each slice gets tiny fades (no clicks)."""
    sl = max(64, int(T.spb * slice_beats * SR))
    n = sig.shape[1]
    out = sig.copy()
    win = np.ones(sl)
    f = min(48, sl // 4)
    win[:f] = np.linspace(0, 1, f)
    win[-f:] = np.linspace(1, 0, f)
    prev = None
    for i in range(n // sl):
        seg = sig[:, i * sl:(i + 1) * sl].copy()
        u = rng.random()
        if prev is not None and u < p_repeat:
            seg = prev.copy()
        elif u < p_repeat + p_rev:
            seg = seg[:, ::-1]
        elif u < p_repeat + p_rev + p_drop:
            seg *= 0.0
        elif u < p_repeat + p_rev + p_drop + p_pitch:
            idx = (np.arange(sl) * float(rng.choice([0.5, 1.5, 2.0]))).astype(int) % sl
            seg = seg[:, idx]
        out[:, i * sl:(i + 1) * sl] = seg * win
        prev = seg
    if crush:
        out = out * (1.0 - crush) + np.round(out * 6.0) / 6.0 * crush
    return out


def t_boss_chariot():
    """Boss: Lord-Marshal Caddoc on his burning war-chariot. A minor (harmonic) at 140 BPM: a
    galloping war-drum pattern, military snare, a crusader horn march, a fire bed and a low string
    pedal rubbing against F. 'phase2' (4 bars): fanfare stabs, choir power chords, chariot chains."""
    T = Track("boss_chariot", 140, 8, seed=301, title="The Lord-Marshal Rides")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_HALL, -18.5)
    p2 = T.stem("phase2", "phase2", IR_HALL, -22.0, bars=4)
    main.add(crackle(T.L, r, 30.0), 0, 0, 0.08, 0.15, 0)
    gallop = [0, 3, 4, 6, 8, 11, 12, 14]
    for bar in range(8):
        for s16 in gallop:
            acc = s16 in (0, 8)
            main.add(k.get("taiko", pitch=0.95 if acc else 1.3), T.step(bar, s16), 0, 0.5 if acc else 0.22, 0.2)
        for s16 in (4, 12):
            main.add(k.get("snare", rattle=0.15), T.step(bar, s16), -0.2, 0.24, 0.3)
        if bar % 4 == 3:
            for s16 in range(8, 16):
                main.add(k.get("snare", rattle=0.1), T.step(bar, s16), -0.2, 0.06 + 0.02 * (s16 - 8), 0.3)
        if bar % 2 == 0:
            main.add(k.get("boom"), T.bar(bar), 0, 0.45, 0.2)
        for i8 in range(8):
            m = 33 + (8 if i8 == 6 else 0)  # A pedal, an F rub on the 7th eighth
            main.add(strings(m, T.beat(0.42), r, 3, 10, 0.004, 0.06, 0.16), T.bar(bar, i8 * 0.5), -0.2,
                     0.18 if i8 % 2 == 0 else 0.11, 0.15)
    march = [(69, 1), (69, 0.5), (72, 0.5), (76, 2), (74, 1), (72, 1), (71, 1), (68, 1),
             (69, 1), (76, 1), (77, 1.5), (76, 0.5), (74, 1), (72, 1), (71, 1), (69, 1),
             (72, 1), (72, 0.5), (74, 0.5), (76, 2), (77, 1), (76, 1), (74, 1), (71, 1),
             (69, 1), (71, 1), (72, 1), (68, 1), (69, 4)]
    b = 0.0
    for m, d in march:
        main.add(brass(m - 12, T.beat(d) * 0.9, r, 4, 12, 7, 0.03, 0.2, 8, 0.15, 25, 8), T.beat(b), 0.1, 0.2, 0.3)
        b += d
    for bar in range(4):
        for s16 in (0, 3, 6, 10):
            for m in (69, 76, 81):
                p2.add(brass(m, 0.22, r, 2, 13, 7, 0.015, 0.12, 8, 0.2), T.step(bar, s16), 0, 0.1, 0.3)
        for m in (57, 64, 69):
            p2.add(choir(m, T.bar(1) - 0.1, r, "a", 4, 0.1, 0.4, 16, 0.15), T.bar(bar), 0, 0.09, 0.45)
        for s16 in (2, 6, 10, 14):
            p2.add(k.get("chains"), T.step(bar, s16), r.uniform(-0.7, 0.7), 0.12, 0.2)
    p2.add(k.get("crash"), 0, 0.4, 0.22, 0.3, 0)
    return T


def t_boss_tempest():
    """Boss: Baraqiel, Archon of the Tempest (storm_spire). A layered variant: battle_spire's own
    calm/combat/frenzy stems (by reference) plus 'tempest' (phase2, 4 bars), the Archon
    conducting the storm: 3-3-2 choir hits on C# minor, rising b2 brass, lightning cracks and a
    thunder drop."""
    T = Track("boss_tempest", 132, 8, seed=311, title="Baraqiel Conducts the Storm")
    T.reuse("battle_spire", ("calm", "combat", "frenzy"))
    r = T.rng
    k = T.kit
    t = T.stem("tempest", "phase2", IR_CATHEDRAL, -21.0, bars=4)
    for bar in range(4):
        for s16 in (0, 6, 12):
            for m in (61, 64, 68):
                t.add(choir(m, T.beat(0.6), r, "a", 4, 0.02, 0.3, 8), T.step(bar, s16), 0, 0.12, 0.45)
        for m in (49 + bar, 56 + bar):
            t.add(brass(m, T.bar(1) - 0.1, r, 3, 10, 6, 0.2, 0.3, 8, 0.3, 10, 4), T.bar(bar), 0, 0.12, 0.35)
        for s16 in (3, 11):
            crack = k.get("crash")[: int(0.4 * SR)] * np.exp(-np.arange(int(0.4 * SR)) / SR / 0.08)
            t.add(crack, T.step(bar, s16), r.uniform(-0.7, 0.7), 0.25, 0.4)
    t.add(k.get("sub_drop"), 0, 0, 0.45, 0.05, 0)
    t.add(k.get("boom"), T.bar(2), 0, 0.4, 0.4)
    return T


def t_boss_aurum():
    """Boss: Aurum, the Gilded Seraph (gilded_isles). A layered variant over battle_isles' stems:
    'cage' (base, 4 bars) is the gilded-cage ostinato: music box and bells circling D Lydian's
    G#, warped organ major chords, a coin-bright bell on every downbeat. 'phase2' (4 bars): a
    pompous waltz fanfare in D major gone sour with an Eb, plus heavy waltz drums."""
    T = Track("boss_aurum", 108, 16, bpb=3, seed=321, title="The Gilded Cage")
    T.reuse("battle_isles", ("calm", "combat", "frenzy"))
    r = T.rng
    k = T.kit
    cage = T.stem("cage", "base", IR_HALL, -21.0, bars=4)
    p2 = T.stem("phase2", "phase2", IR_HALL, -22.0, bars=4)
    ost = [74, 80, 81, 86, 81, 80]  # D G# A D: the Lydian cage
    for bar in range(4):
        for i, m in enumerate(ost):
            cage.add(music_box(m, r, 1.3, 6 + 4 * bar), T.bar(bar, i * 0.5), 0.4 if i % 2 else -0.4, 0.2, 0.5)
        cage.add(bell(86, r, 1.6, 1.6), T.bar(bar), 0, 0.12, 0.6)
        for m in (62, 66, 69, 74):
            cage.add(organ(m, T.bar(1) - 0.1, r, ORGAN_FLUTE, 0.2, 0.5, 6.0, 0.3, 8.0), T.bar(bar), 0, 0.05, 0.5)
    for j in range(10):
        cage.add(harp([62, 66, 68, 69, 73, 74, 78, 80, 81, 86][j], r, 1.4), T.bar(3, 2) + j * 0.03, 0.3, 0.1, 0.4)
    fan = [(74, 1), (78, 1), (81, 1), (86, 2), (85, 0.5), (87, 0.5), (86, 3), (81, 1), (78, 1), (75, 1)]
    b = 0.0
    for m, d in fan:
        p2.add(brass(m - 12, T.beat(d) * 0.9, r, 4, 13, 8, 0.03, 0.25, 8, 0.1, 20, 8), T.beat(b), 0, 0.2, 0.35)
        b += d
    for bar in range(4):
        p2.add(k.get("taiko", pitch=0.85), T.bar(bar), 0, 0.5, 0.2)
        for bt in (1, 2):
            p2.add(k.get("snare", rattle=0.12), T.bar(bar, bt), 0.2, 0.15, 0.3)
    p2.add(k.get("crash"), 0, 0.4, 0.2, 0.3, 0)
    return T


def t_boss_cantor():
    """Boss: Cantor Seraphiel, the Broken Choir (ruined_sanctum). E minor at 100 BPM: organ
    chords under a detuned choir that is sliced into stutters, reversals, dropouts and octave
    jumps (glitch()), over a broken-clock tick and heavy hammers. 'phase2' (4 bars): a shrieking,
    bit-crushed cluster, reversed bells, sub drops."""
    T = Track("boss_cantor", 100, 4, seed=331, title="The Broken Choir")
    r = T.rng
    k = T.kit
    main = T.stem("main", "base", IR_CATHEDRAL, -18.5)
    p2 = T.stem("phase2", "phase2", IR_CATHEDRAL, -22.0)
    chords = [[52, 55, 59, 64], [48, 52, 55, 64], [45, 52, 57, 60], [47, 51, 54, 59]]
    sung = np.zeros((2, T.L))
    for ci, ch in enumerate(chords):
        for j, m in enumerate(ch):
            main.add(organ(m - 12, T.bar(1) - 0.1, r, ORGAN_PRINCIPAL, 0.05, 0.4, 0, 0, 6.0, 0.03), T.bar(ci), 0, 0.08, 0.4)
            c = choir(m + 12 if j else m, T.bar(1) - 0.05, r, "a" if ci % 2 == 0 else "o", 4, 0.05, 0.3, 14, 0.7, 30)
            st = int(T.bar(ci) * SR)
            n = min(c.shape[1], T.L - st)
            sung[:, st:st + n] += c[:, :n] * 0.3
    main.add(glitch(sung, T, r), 0, 0, 1.0, 0.45, 0)
    for bar in range(4):
        for bt in range(4):
            main.add(k.get("taiko", pitch=0.9), T.bar(bar, bt), 0, 0.42 if bt % 2 == 0 else 0.3, 0.2)
            main.add(k.get("anvil", base=560.0), T.bar(bar, bt + 0.5), 0.3, 0.06, 0.3)
        for s16 in range(16):
            if r.random() < 0.8:  # the clock skips
                main.add(k.get("hat", decay=0.015), T.step(bar, s16), -0.4, 0.06, 0.1)
    cl = np.zeros((2, T.L))
    for m in (76, 77, 82):
        c = choir(m, T.bar(4) - 0.3, r, "i", 4, 0.6, 0.3, 30, 0.9, 50)
        cl[:, : c.shape[1]] += c[:, : T.L] * 0.4
    p2.add(glitch(cl, T, r, 0.125, 0.35, 0.2, 0.15, 0.2, 0.6), 0, 0, 0.9, 0.5, 0)
    for bar in range(4):
        rb = bell([64, 70, 63, 71][bar], r, 2.5, 2.4)[::-1]
        p2.add(rb, T.bar(bar + 1) - len(rb) / SR, r.uniform(-0.6, 0.6), 0.14, 0.5, 0)
        if bar % 2 == 0:
            p2.add(k.get("sub_drop"), T.bar(bar), 0, 0.4, 0.05)
    return T


def t_breach():
    """Map: The Breach (battle_breach): hell has burst through a heaven island. A layered variant:
    battle_gate's holy G-minor chorale, march and fanfare (by reference) are overrun by 'hell'
    (base, 2 bars, 11.025 kHz): Basecamp Hell's heartbeat, its Phrygian b2 tremolo organ (Ab over
    G) and its reed motif transposed to G, over a lava rumble."""
    T = Track("battle_breach", 72, 8, seed=341, title="The Breach")
    T.reuse("battle_gate", ("calm", "combat", "frenzy"))
    r = T.rng
    k = T.kit
    hell = T.stem("hell", "base", IR_CATHEDRAL, -21.0, bars=2, out_rate=11025)
    hell.add(peak_norm(fft_filter(r.standard_normal(hell.L), 25, 140, 3)), 0, 0, 0.25, 0.0, 0)
    for bar in range(2):
        hell.add(fft_filter(k.get("taiko", pitch=0.55), None, 300), T.bar(bar), 0, 0.4, 0.15)
        hell.add(fft_filter(k.get("taiko", pitch=0.6), None, 300), T.bar(bar, 0.4), 0, 0.26, 0.15)
        for m in ((44, 48, 51, 56) if bar == 0 else (43, 47, 50, 55)):  # Ab -> G: the basecamp b2
            hell.add(organ(m, T.bar(1) - 0.1, r, ORGAN_PRINCIPAL, 0.3, 0.8, 5.1, 0.25), T.bar(bar), 0, 0.08, 0.4)
    b = 0.0
    for m, d in ((67, 1.5), (70, 0.5), (75, 2), (72, 1), (70, 1), (67, 2)):
        hell.add(organ(m, T.beat(d) * 0.95, r, ORGAN_REED, 0.08, 0.6, 5.6, 0.3, 4.0, 0.06), T.beat(b), 0.2, 0.12, 0.5)
        b += d
    return T


THEMES = {
    "basecamp": t_basecamp, "basecamp_ended": t_basecamp_ended, "title": t_title,
    "battle_sanctum": t_sanctum, "battle_city": t_city, "battle_monastery": t_monastery,
    "battle_gardens": t_gardens, "battle_citadel": t_citadel, "battle_isles": t_isles,
    "battle_spire": t_spire, "battle_gate": t_gate, "battle_wastes": t_wastes, "battle_breach": t_breach,
    "boss_sariel": t_boss_sariel, "boss_inquisitor": t_boss_inquisitor, "boss_archon": t_boss_archon,
    "boss_abbot": t_boss_abbot, "boss_wyrm": t_boss_wyrm, "boss_verdance": t_boss_verdance,
    "boss_chariot": t_boss_chariot, "boss_tempest": t_boss_tempest, "boss_aurum": t_boss_aurum,
    "boss_cantor": t_boss_cantor,
    "ending_climb": t_ending_climb, "ending_sit": t_ending_sit, "ending_break": t_ending_break,
    "defeat": t_defeat, "run_won": t_run_won, "victory": t_victory,
    "sting_objective": t_sting_objective, "sting_purchase": t_sting_purchase,
}
## Manifest being built (Track.reuse reads already rendered tracks from it).
MANIFEST = {"tracks": {}}

## Not rendered by default (the SFX role covers relics and level-ups); name them to render.
OPTIONAL = {"sting_relics": t_sting_relics, "sting_level_up": t_sting_level_up}


def main():
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:] or list(THEMES)
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = MANIFEST
    if os.path.exists(manifest_path) and sys.argv[1:]:
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest.update(json.load(f))
    for name in want:
        t0 = time.time()
        result = {**THEMES, **OPTIONAL}[name]()
        for T in (result if isinstance(result, list) else [result]):
            manifest["tracks"][T.name] = T.finish()
        print("    rendered in %.1fs" % (time.time() - t0))
    manifest["generator"] = "tools/music/gen_music.py"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
