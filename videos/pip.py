"""Court-métrage cartoon « Pip » : images dessinées en code + musique synthétisée."""
import math, subprocess, sys, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = sys.argv[1]
W, H, FPS, DUR = 1280, 720, 24, 12.0
SS = 2  # suréchantillonnage pour des bords lisses
N = int(FPS * DUR)
GROUND = 560
FONT = "/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf"

def lerp(a, b, t): return a + (b - a) * t
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def ease(t): t = clamp(t); return t * t * (3 - 2 * t)
def back_out(t):
    t = clamp(t); c = 1.70158
    return 1 + (c + 1) * (t - 1) ** 3 + c * (t - 1) ** 2

# ---------- décor fixe ----------
def make_background():
    w, h = W * SS, H * SS
    y = np.linspace(0, 1, h)[:, None]
    top, bot = np.array([90, 160, 235]), np.array([255, 205, 160])
    sky = (top * (1 - y) + bot * y)
    img = np.broadcast_to(sky[:, None, :] if sky.ndim == 2 else sky, (h, w, 3)).copy()
    im = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(im)
    s = SS
    # soleil avec halo
    for r, a in [(140, 40), (110, 70), (80, 255)]:
        halo = Image.new("RGBA", im.size)
        ImageDraw.Draw(halo).ellipse([(1040 - r) * s, (150 - r) * s, (1040 + r) * s, (150 + r) * s],
                                     fill=(255, 235, 150, a))
        im.paste(halo, (0, 0), halo)
    # collines lointaines
    for base, amp, freq, col, ph in [(470, 50, 0.006, (120, 190, 140), 0.0),
                                     (510, 40, 0.009, (95, 175, 105), 1.7)]:
        pts = [(0, H * s)]
        for x in range(0, W + 1, 8):
            pts.append((x * s, (base - amp * math.sin(x * freq + ph)) * s))
        pts.append((W * s, H * s))
        d.polygon(pts, fill=col)
    # sol
    d.rectangle([0, GROUND * s, W * s, H * s], fill=(110, 200, 95))
    d.rectangle([0, (GROUND + 60) * s, W * s, H * s], fill=(95, 180, 85))
    rng = np.random.default_rng(3)
    for _ in range(260):
        x, yy = rng.uniform(0, W), rng.uniform(GROUND + 5, H)
        d.line([x * s, yy * s, (x + rng.uniform(-3, 3)) * s, (yy - rng.uniform(6, 12)) * s],
               fill=(70, 150, 70), width=2 * s)
    return im.convert("RGBA")

def make_sphere(r, base):
    """Sprite de corps rond avec ombrage doux (lumière en haut à gauche)."""
    n = 2 * r
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    nx, ny = (xx - r) / r, (yy - r) / r
    d2 = nx ** 2 + ny ** 2
    mask = d2 <= 1
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    L = np.array([-0.5, -0.6, 0.62]); L /= np.linalg.norm(L)
    diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    rim = np.clip(1 - nz, 0, 1) ** 3
    spec = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1) ** 40
    col = np.array(base, float)
    rgb = col * (0.45 + 0.6 * diff)[..., None] + np.array([255, 140, 90]) * (0.25 * rim)[..., None]
    rgb = rgb + 255 * (0.55 * spec)[..., None]
    alpha = np.clip((1 - np.sqrt(d2)) * r, 0, 1) * 255
    out = np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")

BG = make_background()
BODY = make_sphere(90 * SS, (255, 150, 60))
CLOUDS = [(150, 120, 1.0), (520, 80, 0.7), (850, 200, 0.85)]
font_big = ImageFont.truetype(FONT, 150 * SS)
font_small = ImageFont.truetype(FONT, 40 * SS)

# ---------- chorégraphie ----------
HOPS = [(0.0, 1.0, -120, 160), (1.0, 2.0, 160, 420), (2.0, 3.0, 420, 600)]
LANDINGS = [h[1] for h in HOPS]
FLOWER_T, JUMP_T0, JUMP_T1 = 4.5, 8.0, 9.2

def pip_state(t):
    x, lift, sx, sy = 600, 0.0, 1.0, 1.0
    for t0, t1, x0, x1 in HOPS:
        if t0 <= t < t1:
            u = (t - t0) / (t1 - t0)
            x = lerp(x0, x1, ease(u))
            lift = 150 * 4 * u * (1 - u)
            st = 1 + 0.18 * math.sin(u * math.pi) * (1 if 0.1 < u < 0.9 else 0)
            sx, sy = 1 / st, st
    for tl in LANDINGS:  # écrasement à l'atterrissage
        dt = t - tl
        if 0 <= dt < 0.35:
            k = math.exp(-dt * 10) * math.cos(dt * 28)
            sy, sx = 1 - 0.28 * k, 1 + 0.28 * k
    if JUMP_T0 <= t < JUMP_T1:  # saut de joie
        u = (t - JUMP_T0) / (JUMP_T1 - JUMP_T0)
        lift = 260 * 4 * u * (1 - u)
        sy, sx = 1 + 0.15 * math.sin(u * math.pi), 1 - 0.1 * math.sin(u * math.pi)
    dt = t - JUMP_T1
    if 0 <= dt < 0.5:
        k = math.exp(-dt * 9) * math.cos(dt * 26)
        sy, sx = 1 - 0.3 * k, 1 + 0.3 * k
    if t >= 3.35 and not (JUMP_T0 <= t < JUMP_T1 + 0.5):  # respiration
        b = 0.025 * math.sin(t * 4)
        sy, sx = sy * (1 + b), sx * (1 - b)
    return x, lift, sx, sy

def draw_pip(im, t):
    s = SS
    x, lift, sx, sy = pip_state(t)
    r = 90
    w, h = int(2 * r * sx * s), int(2 * r * sy * s)
    cx, bottom = x * s, (GROUND + 10 - lift) * s
    top = bottom - h
    # ombre
    sh = Image.new("RGBA", im.size)
    shr = r * (1 - 0.4 * clamp(lift / 260)) * s
    ImageDraw.Draw(sh).ellipse([cx - shr, (GROUND + 2) * s, cx + shr, (GROUND + 22) * s], fill=(30, 80, 30, 90))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(6 * s)))
    d = ImageDraw.Draw(im)
    # pieds
    for fx in (-38, 38):
        d.ellipse([cx + (fx - 22) * s * sx, bottom - 18 * s, cx + (fx + 22) * s * sx, bottom + 6 * s], fill=(200, 95, 35))
    # bras (vague pendant la joie)
    for side in (-1, 1):
        # angle mesuré depuis l'horizontale vers l'extérieur ; positif = vers le bas
        ang = 0.9
        if side == 1 and 6.6 <= t < JUMP_T0:  # salut de la main
            ang = -0.9 + 0.5 * math.sin((t - 6.6) * 14)
        if JUMP_T0 - 0.2 <= t < 10.5:  # bras en l'air de joie
            ang = -1.0 + 0.25 * math.sin(t * 20 + side)
        ax, ay = cx + side * r * 0.85 * sx * s, top + h * 0.6
        ex, ey = ax + side * 48 * s * math.cos(ang), ay + 48 * s * math.sin(ang)
        d.line([ax, ay, ex, ey], fill=(220, 110, 40), width=16 * s)
        d.ellipse([ex - 12 * s, ey - 12 * s, ex + 12 * s, ey + 12 * s], fill=(235, 125, 50))
    im.alpha_composite(BODY.resize((w, h), Image.LANCZOS), (int(cx - w / 2), int(top)))
    # antenne
    d.line([cx, top + 6 * s, cx + 10 * s, top - 40 * s], fill=(200, 95, 35), width=6 * s)
    glow = 1 if t > FLOWER_T + 1.5 else 0
    d.ellipse([cx - 4 * s, top - 56 * s, cx + 24 * s, top - 28 * s], fill=(255, 230, 90) if glow else (255, 120, 120))
    # yeux
    look = 0.0
    if 3.4 < t < 4.5: look = math.sin((t - 3.4) * 5) * 8
    if t >= 5.2: look = 9
    if t >= JUMP_T0: look = 0
    blink = any(abs(t - b) < 0.07 for b in (3.6, 5.6, 7.4, 10.6))
    wonder = 1.0 + 0.25 * ease((t - 5.6) / 0.4) * (1 - ease((t - 8.0) / 0.3))
    ey_c = top + h * 0.42
    for ex_off in (-30, 30):
        ex = cx + ex_off * s * sx
        rw, rh = 22 * s * wonder, 28 * s * wonder * sy
        if blink:
            d.line([ex - rw, ey_c, ex + rw, ey_c], fill=(60, 30, 20), width=5 * s)
            continue
        d.ellipse([ex - rw, ey_c - rh, ex + rw, ey_c + rh], fill="white")
        px = ex + look * s
        pr = 13 * s * wonder
        d.ellipse([px - pr, ey_c - pr, px + pr, ey_c + pr], fill=(40, 30, 60))
        d.ellipse([px - pr * 0.2 - 6 * s, ey_c - pr * 0.6 - 4 * s, px - pr * 0.2 + 2 * s, ey_c - pr * 0.6 + 4 * s], fill="white")
    # joues
    blush = ease((t - 5.8) / 0.5)
    if blush > 0:
        bl = Image.new("RGBA", im.size)
        bd = ImageDraw.Draw(bl)
        for bx in (-55, 55):
            bd.ellipse([cx + (bx - 16) * s, ey_c + 22 * s, cx + (bx + 16) * s, ey_c + 36 * s], fill=(255, 90, 110, int(140 * blush)))
        im.alpha_composite(bl.filter(ImageFilter.GaussianBlur(3 * s)))
    # bouche
    my = ey_c + 45 * s
    smile = 10 + 18 * ease((t - 5.8) / 0.6)
    if t >= JUMP_T0 - 0.2:
        d.chord([cx - 26 * s, my - 14 * s, cx + 26 * s, my + 26 * s], 0, 180, fill=(120, 30, 40))
        d.chord([cx - 14 * s, my + 8 * s, cx + 14 * s, my + 24 * s], 180, 360, fill=(255, 110, 120))
    else:
        d.arc([cx - 22 * s, my - smile * s, cx + 22 * s, my + smile * 0.6 * s], 20, 160, fill=(90, 35, 30), width=5 * s)

def draw_flower(im, t):
    g = back_out((t - FLOWER_T) / 1.2)
    if g <= 0: return
    s = SS
    d = ImageDraw.Draw(im)
    fx, h = 930, 140 * g
    sway = math.sin(t * 2.5) * 6 * g
    top = (fx + sway, GROUND - h)
    d.line([fx * s, GROUND * s, top[0] * s, top[1] * s], fill=(50, 140, 60), width=8 * s)
    lf = 30 * g
    d.ellipse([(fx - lf - 4) * s, (GROUND - h * 0.45 - 10) * s, (fx - 4) * s, (GROUND - h * 0.45 + 8) * s], fill=(70, 170, 70))
    pr = 26 * g
    for k in range(6):
        a = k * math.pi / 3 + t * 0.6
        px, py = top[0] + math.cos(a) * pr * 1.1, top[1] + math.sin(a) * pr * 1.1
        d.ellipse([(px - pr * 0.75) * s, (py - pr * 0.75) * s, (px + pr * 0.75) * s, (py + pr * 0.75) * s], fill=(255, 110, 170))
    d.ellipse([(top[0] - pr * 0.6) * s, (top[1] - pr * 0.6) * s, (top[0] + pr * 0.6) * s, (top[1] + pr * 0.6) * s], fill=(255, 215, 70))

def draw_sparkles(im, t):
    u = (t - JUMP_T0) / 2.0
    if not 0 < u < 1: return
    s = SS
    d = ImageDraw.Draw(im)
    x, lift, *_ = pip_state(t)
    rng = np.random.default_rng(7)
    for i in range(14):
        a = rng.uniform(0, 2 * math.pi); sp = rng.uniform(120, 260)
        px = x + math.cos(a) * sp * u
        py = GROUND - 100 - lift + math.sin(a) * sp * u - 60 * u
        r = 20 * (1 - u) + 4
        col = [(255, 230, 90), (255, 120, 170), (140, 220, 255)][i % 3]
        if i % 2:  # petit coeur
            d.ellipse([(px - r) * s, (py - r) * s, px * s, py * s], fill=col)
            d.ellipse([px * s, (py - r) * s, (px + r) * s, py * s], fill=col)
            d.polygon([((px - r) * s, (py - r * 0.4) * s), ((px + r) * s, (py - r * 0.4) * s), (px * s, (py + r) * s)], fill=col)
        else:  # étoile
            pts = []
            for k in range(10):
                rr = r * (1.3 if k % 2 == 0 else 0.5); aa = k * math.pi / 5 - math.pi / 2
                pts.append(((px + math.cos(aa) * rr) * s, (py + math.sin(aa) * rr) * s))
            d.polygon(pts, fill=col)

def draw_clouds(im, t):
    s = SS
    layer = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(layer)
    for x0, y, sc in CLOUDS:
        x = (x0 + t * 12 * sc) % (W + 300) - 150
        for dx, dy, r in [(0, 0, 40), (40, -18, 48), (85, 0, 38), (42, 12, 40)]:
            r *= sc
            d.ellipse([(x + dx * sc - r) * s, (y + dy * sc - r) * s, (x + dx * sc + r) * s, (y + dy * sc + r) * s], fill=(255, 255, 255, 235))
    im.alpha_composite(layer)

def draw_title(im, t):
    a = ease((t - 10.0) / 0.8)
    if a <= 0: return
    s = SS
    layer = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(layer)
    y = (130 - 30 * (1 - a)) * s
    d.text((W * s / 2 + 6 * s, y + 6 * s), "Pip", font=font_big, anchor="mm", fill=(120, 50, 20, int(150 * a)))
    d.text((W * s / 2, y), "Pip", font=font_big, anchor="mm", fill=(255, 245, 230, int(255 * a)), stroke_width=6 * s, stroke_fill=(230, 110, 40, int(255 * a)))
    d.text((W * s / 2, y + 100 * s), "et la petite fleur", font=font_small, anchor="mm", fill=(255, 255, 255, int(255 * a)), stroke_width=3 * s, stroke_fill=(200, 90, 40, int(255 * a)))
    im.alpha_composite(layer)

def frame(i):
    t = i / FPS
    im = BG.copy()
    draw_clouds(im, t)
    draw_flower(im, t)
    draw_pip(im, t)
    draw_sparkles(im, t)
    draw_title(im, t)
    fade = min(ease(t / 0.5), ease((DUR - t) / 0.6))
    out = im.convert("RGB").resize((W, H), Image.LANCZOS)
    if fade < 1:
        out = Image.blend(Image.new("RGB", (W, H)), out, fade)
    return out

# ---------- musique & bruitages ----------
SR = 44100
def synth_audio(path):
    n = int(SR * DUR)
    mix = np.zeros(n)
    tt = np.arange(n) / SR
    def note(f, t0, d, vol, kind="pluck"):
        i0 = int(t0 * SR); m = min(int(d * SR), n - i0)
        if m <= 0: return
        x = np.arange(m) / SR
        ph = 2 * np.pi * f * x
        if kind == "pluck":
            w = np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)
            env = np.exp(-x * 5) * np.minimum(1, x * 200)
        elif kind == "bass":
            w = np.sin(ph) + 0.2 * np.sin(2 * ph)
            env = np.exp(-x * 2.5) * np.minimum(1, x * 100)
        else:  # bell
            w = np.sin(ph) + 0.4 * np.sin(2.76 * ph) + 0.2 * np.sin(5.4 * ph)
            env = np.exp(-x * 3) * np.minimum(1, x * 300)
        mix[i0:i0 + m] += vol * w * env
    hz = lambda m: 440 * 2 ** ((m - 69) / 12)
    beat = 0.5  # 120 bpm
    chords = [(60, 64, 67), (57, 60, 64), (65, 69, 72), (67, 71, 74)]  # C Am F G
    melody = [72, 74, 76, 79, 76, 74, 72, 76, 74, 72, 69, 72, 77, 76, 74, 72,
              79, 77, 76, 74, 76, 79, 84, 79]
    for b in range(int(DUR / beat)):
        t0 = b * beat
        ch = chords[(b // 4) % 4]
        if b % 2 == 0: note(hz(ch[0] - 24), t0, 1.0, 0.25, "bass")
        note(hz(ch[(b % 3)]), t0 + 0.25, 0.4, 0.06)
        if b < len(melody) and t0 < 10.0: note(hz(melody[b]), t0, 0.5, 0.12)
    for tl in LANDINGS + [JUMP_T1]:  # « boing »
        i0 = int(tl * SR); m = int(0.35 * SR); x = np.arange(m) / SR
        f = 180 + 300 * np.exp(-x * 12) + 40 * np.sin(x * 60)
        mix[i0:i0 + m] += 0.3 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x * 9)
    for k, m in enumerate([84, 88, 91, 96]):  # carillon de la fleur
        note(hz(m), FLOWER_T + 0.08 * k, 1.5, 0.1, "bell")
    i0 = int(JUMP_T0 * SR); m = int(0.6 * SR); x = np.arange(m) / SR  # « youpi » montant
    mix[i0:i0 + m] += 0.18 * np.sin(2 * np.pi * np.cumsum(300 + 900 * x) / SR) * np.exp(-x * 4)
    for k, m in enumerate([72, 76, 79, 84]):  # accord final
        note(hz(m), 10.0 + 0.05 * k, 2.0, 0.12, "bell")
    mix *= np.minimum(1, (DUR - tt) / 0.6)
    mix = mix / np.max(np.abs(mix)) * 0.85
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(SR)
        wf.writeframes((mix * 32767).astype(np.int16).tobytes())

if __name__ == "__main__":
    wav = OUT + ".wav"
    synth_audio(wav)
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-i", wav,
                           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                           "-c:a", "aac", "-b:a", "160k", "-shortest", OUT], stdin=subprocess.PIPE)
    for i in range(N):
        ff.stdin.write(frame(i).tobytes())
    ff.stdin.close(); ff.wait()
    print("ok", OUT)
