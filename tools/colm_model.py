# SPDX-License-Identifier: GPL-2.0-only


import math
import sys

FS = 48000
QONE = 32768
SMAX = 8388607
SMIN = -8388608

def sat24(v):
    if v > SMAX:
        return SMAX
    if v < SMIN:
        return SMIN
    return int(v)

def q315(v):

    x = v * QONE
    q = int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))
    if q > 131071:
        q = 131071
    if q < -131072:
        q = -131072
    return q

def mac(terms):

    acc = 0
    for c, x in terms:
        acc += c * x
    return sat24(acc >> 15)

def sadd(a, b):

    return sat24(a + b)

def depth_gain(strength):

    if strength == 0:
        return 0.0, False
    g = 10.0 ** (((strength / 1000.0) * 10.0 - 15.0) / 20.0)
    if g > 1.0:
        g = 1.0
    return g, (strength >= 500)

def hp800_v4a(fs, freq=800.0, db_gain=-11.0, q=0.72):

    omega = 2.0 * math.pi * freq / fs
    so, co = math.sin(omega), math.cos(omega)
    A = 10.0 ** (db_gain / 40.0)
    sqrtA = math.sqrt(A)
    z = so / 2.0 * math.sqrt((1.0 / A + A) * (1.0 / q - 1.0) + 2.0)
    a0 = (A + 1.0) - (A - 1.0) * co + (sqrtA * 2.0) * z
    a1 = ((A - 1.0) - (A + 1.0) * co) * 2.0
    a2 = (A + 1.0) - (A - 1.0) * co - (sqrtA * 2.0) * z
    b0 = ((A + 1.0) + (A - 1.0) * co + (sqrtA * 2.0) * z) * A * omega
    b1 = A * -2.0 * ((A - 1.0) + (A + 1.0) * co) * omega
    b2 = ((A + 1.0) + (A - 1.0) * co - (sqrtA * 2.0) * z) * A * omega
    return (b0 / a0, b1 / a0, b2 / a0, -(a1 / a0), -(a2 / a0)), (a0, a1, a2, b0, b1, b2)

def stereo3d_coeffs(widen, mid_image):

    tmp = widen + 1.0
    x = tmp + 1.0
    y = 0.5 if x < 2.0 else 1.0 / x
    cL = mid_image * y
    cR = tmp * y
    return cL + cR, cL - cR

def rbj_lowpass(freq, q, fs=FS):

    w = 2.0 * math.pi * freq / fs
    alpha = math.sin(w) / (2.0 * q)
    co = math.cos(w)
    b0 = (1.0 - co) / 2.0
    b1 = 1.0 - co
    b2 = (1.0 - co) / 2.0
    a0 = 1.0 + alpha
    a1 = -2.0 * co
    a2 = 1.0 - alpha
    return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)

def delay_samps(delay):
    return int(FS * delay)

class Biquad:

    def __init__(self, c):
        self.b0, self.b1, self.b2, self.a1, self.a2 = c
        self.x1 = self.x2 = self.y1 = self.y2 = 0

    def step(self, x):

        acc = (self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2
               - self.a1 * self.y1 - self.a2 * self.y2)
        y = sat24(acc >> 15)
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y

class HP800:

    def __init__(self, c):
        self.b0, self.b1, self.b2, self.a1, self.a2 = c
        self.x1 = self.x2 = self.y1 = self.y2 = 0

    def step(self, x):
        y = mac([(self.b0, x), (self.b1, self.x1), (self.b2, self.x2),
                 (self.a1, self.y1), (self.a2, self.y2)])
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y

class IntDelay:

    def __init__(self, n):
        self.n = n
        self.buf = [0] * n
        self.i = 0

    def step(self, x):
        v = self.buf[self.i]
        self.buf[self.i] = x
        self.i = (self.i + 1) % self.n
        return v

class DepthSurround:

    def __init__(self, strength, fs=FS, hp=None):
        g, neg = depth_gain(strength)
        self.g = q315(g)
        self.g1 = q315(-g) if neg else q315(g)
        self.neg = neg
        self.d0 = IntDelay(delay_samps(0.02))
        self.d1 = IntDelay(delay_samps(0.014))

        self.hp = HP800([q315(v) for v in (hp if hp else hp800_v4a(fs)[0])])
        self.p0 = 0
        self.p1 = 0

    def step(self, L, R):
        a = sadd(L, self.p1)
        d0 = self.d0.step(a)
        self.p0 = mac([(self.g, d0)])
        b = sadd(R, self.p0)
        d1 = self.d1.step(b)
        self.p1 = mac([(self.g1, d1)])
        l = sadd(self.p0, L)
        r = sadd(self.p1, R)

        diff = sadd(l, -r) >> 1
        avg = sadd(l, r) >> 1
        y = self.hp.step(diff)
        e = sat24(diff - y)
        return sadd(avg, e), sadd(avg, -e)

class Stereo3D:

    def __init__(self, ca, cb):
        self.ca = ca
        self.cb = cb

    def step(self, L, R):
        outL = mac([(self.ca, L), (self.cb, R)])
        outR = mac([(self.cb, L), (self.ca, R)])
        return outL, outR

def run_chain(frames, jsd, js3, pre=None, post=None):

    jd = (0, 0)
    out = []
    for (L, R) in frames:
        pl = pre[0].step(L) if pre else L

        out.append(post[0].step(jd[0]) if post else jd[0])
        pr = pre[1].step(R) if pre else R
        old = jd
        jd = js3.step(*jsd.step(pl, pr))

        out.append(post[1].step(old[1]) if post else old[1])
    return out

NFRAMES = 1800
SEED = 20260921

def gen_input(n):
    s = SEED
    out = []

    def rnd():
        nonlocal s
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        return s

    for k in range(n):
        if k == 0:
            L, R = 3000000, -1500000
        elif k % 97 == 5:
            L, R = (SMAX if (k // 97) % 2 else SMIN), (SMIN if (k // 97) % 2 else SMAX)
        else:
            L = (rnd() % 4000001) - 2000000
            R = (rnd() % 4000001) - 2000000
        out.append((L, R))
    return out

def hex24(v):
    return "%06x" % (int(v) & 0xFFFFFF)

def wr(path, vals):
    with open(path, "w") as f:
        for v in vals:
            f.write(hex24(v) + "\n")

def main():
    frames = gen_input(NFRAMES)
    flat = [v for fr in frames for v in fr]
    wr("colm_in.hex", flat)

    WIDEN, MID = 0.5, 0.8
    ca, cb = stereo3d_coeffs(WIDEN, MID)
    hp_f, hp_raw = hp800_v4a(FS)
    print("== ColorfulMusic fixed-point reference model ==")
    print("  D0 = %d samples (fs*0.02), D1 = %d samples (fs*0.014)" % (delay_samps(0.02), delay_samps(0.014)))
    print("  HP800 raw coefficients a0..b2 = %s" % ["%.6f" % v for v in hp_raw])
    print("  HP800 in V4A convention (b0,b1,b2,a1,a2) = %s" % ["%.6f" % v for v in hp_f])
    print("  HP800 Q3.15 = %s" % [q315(v) for v in hp_f])
    tmp = WIDEN + 1.0
    yy = 0.5 if (tmp + 1.0) < 2.0 else 1.0 / (tmp + 1.0)
    print("  stereo3d widen=%.2f midImage=%.2f ⇒ y=%.4f cL=%.6f cR=%.6f ⇒ ca=%d cb=%d (Q3.15)"
          % (WIDEN, MID, yy, MID * yy, tmp * yy, q315(ca), q315(cb)))

    cases = [("1", 1000), ("2", 300), ("3", 700)]
    for tag, strength in cases:
        g, neg = depth_gain(strength)
        jsd = DepthSurround(strength)
        js3 = Stereo3D(q315(ca), q315(cb))

        jsd_c = [jsd.g, jsd.g1, delay_samps(0.02), delay_samps(0.014),
                 q315(hp_f[0]), q315(hp_f[1]), q315(hp_f[2]), q315(hp_f[3]), q315(hp_f[4])]
        assert len(jsd_c) == 9
        wr("colm_jsd%s.hex" % tag, jsd_c)
        wr("colm_js3%s.hex" % tag, [q315(ca), q315(cb)])
        if tag == "3":
            pre_c = [q315(v) for v in rbj_lowpass(1200.0, 0.707)]
            post_c = [q315(v) for v in rbj_lowpass(3000.0, 0.707)]
            wr("colm_pre.hex", pre_c)
            wr("colm_post.hex", post_c)
            pre = (Biquad(pre_c), Biquad(pre_c))
            post = (Biquad(post_c), Biquad(post_c))

            jsd = DepthSurround(strength)
            js3 = Stereo3D(q315(ca), q315(cb))
            exp = run_chain(frames, jsd, js3, pre, post)
        else:
            exp = run_chain(frames, jsd, js3)
        wr("colm_exp%s.hex" % tag, exp)
        print("  phase %s: strength=%d => g=%.6f (%s) Q3.15=%d, first 6 expected outputs = %s"
              % (tag, strength, g, "negative branch" if neg else "positive branch", jsd.g, exp[:6]))
        nz = [i for i, v in enumerate(exp) if v != 0]
        print("        first non-zero index = %s, sample count = %d (%d of them non-zero)"
              % (nz[0] if nz else "-", len(exp), len(nz)))

    half = [16384, 0, 0, 0, 0]
    wr("colm_half.hex", half)
    bq = Biquad([16384, 0, 0, 0, 0])
    exp4 = []
    for (L, R) in frames:
        exp4.append(L)
        exp4.append(bq.step(R))
    wr("colm_exp4.hex", exp4)
    print("  phase 4: the x0.5 stage of FL_R_ONLY => left channel passes through (first 6 outputs = %s)" % exp4[:6])

    def first_diff(a, b):
        for i in range(min(len(a), len(b))):
            if a[i] != b[i]:
                return i
        return -1

    e1 = [int(l, 16) for l in open("colm_exp1.hex")]
    e1 = [v - (1 << 24) if v >= (1 << 23) else v for v in e1]
    e2 = [int(l, 16) for l in open("colm_exp2.hex")]
    e2 = [v - (1 << 24) if v >= (1 << 23) else v for v in e2]
    print("  self-check 1, the two strength branches: first sample where exp1 and exp2 differ = %d (-1 = identical => branch not covered)"
          % first_diff(e1, e2))

    jd0 = DepthSurround(1000)
    jd0.d0.step = lambda x: 0
    jd0.d1.step = lambda x: 0
    e_nodelay = run_chain(frames, jd0, Stereo3D(q315(ca), q315(cb)))
    print("  self-check 2, the delay lines: first differing sample after pinning D0/D1 to 0 = %d (-1 = the delay is not involved at all => the test has no teeth)"
          % first_diff(e1, e_nodelay))
    print("== vectors written to the current directory (build/sim) ==")
    return 0

if __name__ == "__main__":
    sys.exit(main())
