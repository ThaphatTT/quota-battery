#!/usr/bin/env python3
"""Synthesizes the promo music bed and sound effects from scratch (stdlib only, no samples, no downloads).
Usage: python3 synth.py <output_dir>   -> writes music.wav and sfx.wav (44.1 kHz, 16-bit, stereo, 60 s)."""
import math, random, struct, sys, wave

SR = 44100
DUR = 60.0
N = int(SR * DUR)
BPM = 120
BEAT = 60.0 / BPM
PI2 = 2 * math.pi
FRAME = 1 / 30  # the sound lands one frame after its picture


def buf():
    return [[0.0] * N, [0.0] * N]


def add(b, start, samples, gain=1.0, pan=0.0):
    i0 = int(start * SR)
    gl = gain * (1 - max(0.0, pan))
    gr = gain * (1 + min(0.0, pan))
    L, R = b
    for k, v in enumerate(samples):
        i = i0 + k
        if i >= N:
            break
        if i >= 0:
            L[i] += v * gl
            R[i] += v * gr


def env_exp(n, attack, decay):
    out = []
    for i in range(n):
        t = i / SR
        a = min(1.0, t / attack) if attack > 0 else 1.0
        out.append(a * math.exp(-t / decay))
    return out


def lowpass(x, cutoff_fn):
    y, s = [], 0.0
    for i, v in enumerate(x):
        c = cutoff_fn(i / SR)
        a = 1 - math.exp(-PI2 * c / SR)
        s += a * (v - s)
        y.append(s)
    return y


def highpass(x, cutoff):
    a = 1 - math.exp(-PI2 * cutoff / SR)
    y, s = [], 0.0
    for v in x:
        s += a * (v - s)
        y.append(v - s)
    return y


def noise(n, rnd):
    return [rnd.uniform(-1, 1) for _ in range(n)]


def sine_sweep(n, f0, f1, curve=1.0):
    out, ph = [], 0.0
    for i in range(n):
        p = (i / n) ** curve
        f = f0 + (f1 - f0) * p
        ph += PI2 * f / SR
        out.append(math.sin(ph))
    return out


# ---------------------------------------------------------------- effects
def fx_tick(rnd, f=1800):
    n = int(0.05 * SR)
    e = env_exp(n, 0.0005, 0.008)
    nz = highpass(noise(n, rnd), 2500)
    return [(0.5 * nz[i] + 0.5 * math.sin(PI2 * f * i / SR)) * e[i] for i in range(n)]


def fx_pop(rnd, f0=700, f1=260, dur=0.12):
    n = int(dur * SR)
    e = env_exp(n, 0.001, dur / 4)
    s = sine_sweep(n, f0, f1, 0.6)
    return [s[i] * e[i] for i in range(n)]


def fx_alert(rnd):
    # dull double pulse with a rough edge: a warning, not a chime
    n = int(0.28 * SR)
    out = [0.0] * n
    for off in (0.0, 0.13):
        m = int(0.1 * SR)
        e = env_exp(m, 0.002, 0.03)
        for i in range(m):
            ph = PI2 * 210 * i / SR
            sq = 1.0 if math.sin(ph) > 0 else -1.0
            v = (0.55 * sq + 0.45 * math.sin(ph * 2.01)) * e[i]
            j = int(off * SR) + i
            if j < n:
                out[j] += v
    return lowpass(out, lambda t: 1400)


def fx_whoosh(rnd, dur=0.8, lo=300, hi=5000, rise=True):
    n = int(dur * SR)
    x = noise(n, rnd)
    def cf(t):
        p = t / dur
        p = p if rise else 1 - p
        return lo + (hi - lo) * (p ** 2)
    y = lowpass(lowpass(x, cf), cf)
    out = []
    for i in range(n):
        p = i / n
        a = math.sin(math.pi * p) ** 1.6
        out.append(y[i] * a * 3.0)
    return out


def fx_glitch(rnd, dur=0.28):
    n = int(dur * SR)
    out = [0.0] * n
    i = 0
    while i < n:
        seg = int(rnd.uniform(0.012, 0.045) * SR)
        crush = rnd.choice([4, 8, 16, 32])
        val = 0.0
        for k in range(min(seg, n - i)):
            if k % crush == 0:
                val = rnd.uniform(-1, 1) if rnd.random() < 0.7 else math.sin(PI2 * rnd.choice([220, 880, 1760]) * k / SR)
            out[i + k] = val * 0.7
        i += seg + int(rnd.uniform(0.004, 0.02) * SR)
    return highpass(out, 300)


def fx_spark(rnd, dur=0.45):
    n = int(dur * SR)
    out = [0.0] * n
    for _ in range(26):
        t0 = int(rnd.random() ** 1.8 * n * 0.9)
        m = int(0.006 * SR)
        a = rnd.uniform(0.2, 1.0)
        for k in range(m):
            if t0 + k < n:
                out[t0 + k] += a * rnd.uniform(-1, 1) * math.exp(-k / (m / 3))
    return highpass(out, 3000)


def fx_rumble(rnd, dur=0.9):
    n = int(dur * SR)
    x = lowpass(noise(n, rnd), lambda t: 120 + 200 * t / dur)
    return [x[i] * (i / n) ** 1.5 * 5.0 for i in range(n)]


def fx_crash(rnd, dur=1.4):
    n = int(dur * SR)
    nz = highpass(noise(n, rnd), 1500)
    e = env_exp(n, 0.0005, 0.22)
    out = [nz[i] * e[i] for i in range(n)]
    for _ in range(40):  # tinkles
        t0 = int(rnd.random() ** 1.5 * 0.9 * SR)
        f = rnd.uniform(2400, 7000)
        m = int(0.12 * SR)
        a = rnd.uniform(0.1, 0.35)
        for k in range(m):
            if t0 + k < n:
                out[t0 + k] += a * math.sin(PI2 * f * k / SR) * math.exp(-k / (SR * 0.03))
    boom = env_exp(n, 0.001, 0.12)
    sw = sine_sweep(n, 110, 40, 0.3)
    return [out[i] + 0.9 * sw[i] * boom[i] for i in range(n)]


def fx_riser(rnd, dur=1.2, f0=200, f1=1800):
    n = int(dur * SR)
    sw = sine_sweep(n, f0, f1, 2.0)
    nz = highpass(noise(n, rnd), 1200)
    return [(0.35 * sw[i] + 0.35 * nz[i]) * (i / n) ** 2.2 for i in range(n)]


def fx_impact(rnd, dur=1.1):
    n = int(dur * SR)
    e = env_exp(n, 0.001, 0.3)
    sw = sine_sweep(n, 90, 38, 0.25)
    nz = lowpass(noise(n, rnd), lambda t: 2500 * math.exp(-t * 7) + 150)
    e2 = env_exp(n, 0.0005, 0.06)
    return [1.0 * sw[i] * e[i] + 0.8 * nz[i] * e2[i] for i in range(n)]


def fx_shimmer(rnd, dur=0.9):
    n = int(dur * SR)
    out = [0.0] * n
    for f in (1760, 2349, 3136, 4186):
        ph = rnd.random() * 6
        for i in range(n):
            p = i / n
            out[i] += math.sin(PI2 * f * i / SR + ph) * math.sin(math.pi * p) ** 2 * 0.18
    return out


def fx_drain(rnd, dur=4.0, f0=520, f1=150):
    n = int(dur * SR)
    sw = sine_sweep(n, f0, f1, 1.0)
    return [sw[i] * math.sin(math.pi * i / n) ** 1.5 * 0.35 for i in range(n)]


# ---------------------------------------------------------------- score of effects
def make_sfx():
    rnd = random.Random(1234)
    b = buf()
    ev = []  # (time, samples, gain, pan)
    def put(t, s, g=1.0, p=0.0):
        add(b, t + FRAME, s, g, p)
    # scene 1 (0-6): alert pulses on the blinks, sparks, glitches
    for i, t in enumerate([0, 0.9, 1.8, 2.7, 3.6, 4.5]):
        put(t, fx_alert(rnd), 0.55)
    for t in (0, 0.9, 2.7, 4.5):
        put(t, fx_spark(rnd), 0.5, 0.2)
    for t, d in ((0.12, 0.28), (3.0, 0.24), (5.0, 0.3)):
        put(t, fx_glitch(rnd, d), 0.45)
    put(5.78, fx_whoosh(rnd, 0.35, 400, 6000, True), 0.5)
    # scene 2 (6-14): tabs pop in, tension, shatter
    put(6.1, fx_tick(rnd, 1500), 0.5)
    for i in range(9):
        put(6.0 + 0.8 + 0.36 * i + 0.12, fx_pop(rnd, 520 + 40 * (i % 3), 220), 0.5, (-0.3 if i % 2 else 0.3))
    put(10.5, fx_rumble(rnd, 0.9), 0.8)
    put(11.4, fx_crash(rnd), 0.95)
    put(13.72, fx_whoosh(rnd, 0.3, 300, 5000, True), 0.45)
    # scene 3 (14-22): rise, light sweep, typing
    put(14.3, fx_whoosh(rnd, 1.0, 200, 3500, True), 0.6)
    put(14.3, fx_riser(rnd, 1.0, 180, 900), 0.4)
    put(15.4, fx_impact(rnd), 0.7)
    put(15.5, fx_shimmer(rnd), 0.55)
    for i in range(13):
        if i == 5:
            continue
        put(16.8 + 0.1 * i, fx_tick(rnd, 1300 + 40 * (i % 4)), 0.4)
    put(18.3, fx_pop(rnd, 600, 300, 0.14), 0.45)
    put(19.0, fx_shimmer(rnd), 0.45)
    # scene 4 (22-34): card arrives, batteries drain, threshold alerts
    put(22.15, fx_whoosh(rnd, 0.9, 250, 4500, True), 0.55)
    put(23.2, fx_shimmer(rnd, 0.9), 0.4)
    put(23.6, fx_drain(rnd, 4.2, 560, 180), 0.35, -0.3)
    put(24.0, fx_drain(rnd, 6.4, 480, 150), 0.3, 0.0)
    put(24.4, fx_drain(rnd, 8.2, 420, 120), 0.3, 0.3)
    put(28.8, fx_whoosh(rnd, 0.7, 300, 2500, False), 0.35)
    put(29.3, fx_alert(rnd), 0.55)
    put(30.3, fx_alert(rnd), 0.6)
    put(30.8, fx_shimmer(rnd, 0.9), 0.4)
    put(32.5, fx_alert(rnd), 0.7)
    put(32.75, fx_alert(rnd), 0.7)
    put(33.75, fx_whoosh(rnd, 0.3, 300, 5000, True), 0.4)
    # scene 5 (34-42): menu bar, popover, notifications, push-in
    put(34.45, fx_whoosh(rnd, 0.5, 400, 3000, False), 0.35)
    put(35.5, fx_tick(rnd, 1100), 0.7)
    put(35.6, fx_whoosh(rnd, 0.5, 300, 2500, False), 0.4)
    put(35.75, fx_pop(rnd, 420, 140, 0.2), 0.7)
    put(37.2, fx_pop(rnd, 900, 330, 0.14), 0.65)
    put(38.9, fx_pop(rnd, 760, 260, 0.14), 0.4)
    put(39.0, fx_pop(rnd, 900, 330, 0.14), 0.7)
    put(39.0, fx_whoosh(rnd, 1.0, 250, 3500, True), 0.4)
    put(41.75, fx_whoosh(rnd, 0.3, 300, 5000, True), 0.4)
    # scene 6 (42-50): split-screen wipe, language switch
    put(42.3, fx_whoosh(rnd, 0.9, 300, 4500, True), 0.55, -0.4)
    put(42.3, fx_whoosh(rnd, 0.9, 300, 4500, True), 0.55, 0.4)
    put(43.2, fx_pop(rnd, 420, 140, 0.2), 0.7)
    put(43.3, fx_pop(rnd, 800, 320, 0.12), 0.45)
    put(43.9, fx_tick(rnd, 1700), 0.55)
    put(45.0, fx_tick(rnd, 1700), 0.55)
    put(46.6, fx_tick(rnd, 1200), 0.8)
    put(46.7, fx_pop(rnd, 700, 300, 0.1), 0.4)
    put(48.4, fx_tick(rnd, 1200), 0.8)
    put(48.5, fx_pop(rnd, 700, 300, 0.1), 0.4)
    put(49.75, fx_whoosh(rnd, 0.3, 300, 5000, True), 0.4)
    # scene 7 (50-60): charge, full flash, lockup, link
    put(50.5, fx_whoosh(rnd, 0.7, 250, 3500, True), 0.45)
    put(51.2, fx_riser(rnd, 3.0, 160, 1400), 0.75)
    put(54.2, fx_impact(rnd, 1.4), 0.95)
    put(54.2, fx_shimmer(rnd, 1.0), 0.6)
    put(54.5, fx_whoosh(rnd, 0.6, 300, 3000, True), 0.4)
    put(55.5, fx_pop(rnd, 780, 300, 0.14), 0.6)
    put(56.1, fx_shimmer(rnd, 0.9), 0.35)
    put(56.6, fx_pop(rnd, 700, 280, 0.14), 0.55)
    put(58.2, fx_shimmer(rnd, 0.9), 0.25)
    return b


# ---------------------------------------------------------------- music
def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


CH = {  # bars of two seconds
    'Am': [45, 57, 60, 64], 'F': [41, 53, 57, 60], 'C': [48, 55, 60, 64], 'G': [43, 55, 59, 62],
    'Cmaj': [48, 55, 60, 64, 67], 'Fmaj': [41, 53, 57, 60, 65],
}


def make_music():
    rnd = random.Random(99)
    b = buf()
    bars = int(DUR / (4 * BEAT))
    prog = ['Am', 'F', 'C', 'G']
    # section gains by bar start time
    def lvl(t):
        # 0-14 dark and sparse, 14-22 builds, 22-50 full groove, 50-60 resolve
        if t < 14: return 0.0
        if t < 22: return (t - 14) / 8
        if t < 50: return 1.0
        return 1.0
    for bar in range(bars):
        t0 = bar * 4 * BEAT
        if t0 < 50:
            name = prog[bar % 4]
        else:
            name = ['Cmaj', 'Fmaj', 'Cmaj', 'Cmaj'][(bar - 25) % 4] if bar >= 25 else prog[bar % 4]
        notes = CH[name]
        major = t0 >= 50
        # pad: soft sines with slow attack, present from the start (dark), brighter later
        padn = int(4 * BEAT * SR)
        pad = [0.0] * padn
        for k, m in enumerate(notes[1:]):
            f = mtof(m)
            for i in range(padn):
                t = i / SR
                a = min(1.0, t / 0.8) * min(1.0, (4 * BEAT - t) / 0.6)
                pad[i] += math.sin(PI2 * f * t) * 0.5 * a + math.sin(PI2 * f * 1.004 * t) * 0.3 * a
        pg = 0.07 if t0 < 14 else 0.09
        if t0 >= 56: pg = 0.09
        add(b, t0, pad, pg, 0.0)
        # bass: root every beat (sub), sparse early
        root = mtof(notes[0])
        for beat in range(4):
            tb = t0 + beat * BEAT
            if tb < 14 and beat % 2:
                continue
            n = int(0.42 * SR)
            e = env_exp(n, 0.005, 0.2)
            s = [math.sin(PI2 * root * i / SR) * e[i] + 0.25 * math.sin(PI2 * root * 2 * i / SR) * e[i] for i in range(n)]
            g = 0.22 if tb < 14 else 0.3
            if tb >= 58.5: g *= max(0.0, (60 - tb) / 1.5)
            add(b, tb, s, g)
        # kick on every beat from scene 3, drops in the last 6 s
        if 14 <= t0 < 57:
            for beat in range(4):
                tb = t0 + beat * BEAT
                if 50 <= tb < 54.2:
                    continue  # silence under the charge, the impact brings it back
                n = int(0.28 * SR)
                e = env_exp(n, 0.001, 0.07)
                sw = sine_sweep(n, 130, 46, 0.35)
                g = 0.55 * (min(1.0, (t0 - 14) / 6) if t0 < 20 else 1.0)
                if tb >= 54.2 + 0: g *= 0.8
                add(b, tb, [sw[i] * e[i] for i in range(n)], g)
        # hats on offbeats
        if t0 >= 18 and t0 < 58:
            for step in range(8):
                if step % 2 == 0:
                    continue
                tb = t0 + step * BEAT / 2
                if 50 <= tb < 54.2:
                    continue
                n = int(0.04 * SR)
                e = env_exp(n, 0.0005, 0.01)
                nz = highpass(noise(n, rnd), 6000)
                add(b, tb, [nz[i] * e[i] for i in range(n)], 0.16, 0.25 if step % 4 == 1 else -0.25)
        # arp: eighth-note plucks from scene 3
        if 14 <= t0 < 58:
            pat = [0, 2, 3, 2, 1, 2, 3, 2] if not major else [0, 2, 4, 2, 1, 3, 4, 3]
            for step in range(8):
                tb = t0 + step * BEAT / 2
                if 50 <= tb < 54.2:
                    continue
                m = notes[1 + (pat[step] % (len(notes) - 1))] + 12
                f = mtof(m)
                n = int(0.3 * SR)
                e = env_exp(n, 0.002, 0.09)
                s = [(math.sin(PI2 * f * i / SR) + 0.35 * math.sin(PI2 * 2 * f * i / SR)) * e[i] for i in range(n)]
                g = 0.13 * (min(1.0, (t0 - 14) / 8))
                if tb >= 58.5: g *= max(0.0, (60 - tb) / 1.5)
                add(b, tb, s, g, -0.35 + 0.1 * step % 0.7)
        # S2 tension: filtered noise swell in the last 4 s of scene 2
    n = int(3.6 * SR)
    nz = highpass(noise(n, rnd), 900)
    add(b, 10.0, [nz[i] * (i / n) ** 2 * 0.12 for i in range(n)], 1.0)
    # heartbeat in scene 1/2: soft double thump every 2 s
    for t in [x * 2.0 for x in range(0, 7)]:
        for off in (0.0, 0.22):
            n = int(0.2 * SR)
            e = env_exp(n, 0.003, 0.06)
            sw = sine_sweep(n, 75, 42, 0.5)
            add(b, t + off, [sw[i] * e[i] for i in range(n)], 0.35)
    # final fade
    fade_start = int(58.0 * SR)
    for ch in b:
        for i in range(fade_start, N):
            ch[i] *= max(0.0, 1 - (i - fade_start) / (N - fade_start))
    return b


def write(path, b, gain):
    pk = max(max(abs(v) for v in b[0]), max(abs(v) for v in b[1]))
    print(path, 'raw peak', round(pk, 3))
    with wave.open(path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        frames = bytearray()
        for i in range(N):
            for ch in (0, 1):
                v = max(-1.0, min(1.0, b[ch][i] * gain))
                frames += struct.pack('<h', int(v * 32767))
        w.writeframes(bytes(frames))


if __name__ == '__main__':
    out = sys.argv[1]
    mg = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    sg = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
    write(out + '/music.wav', make_music(), mg)
    write(out + '/sfx.wav', make_sfx(), sg)
