#!/usr/bin/env python3
"""Laver alle lyde og musik til Outland Patrol som WAV-filer i sounds/.

Alt er syntetiseret (ingen samples), i retro-stil: firkant-, savtak- og trekantbølger,
filtreret støj og simple ekko-effekter. Kør igen efter ændringer:

    python3 tools/make_sounds.py

Kræver numpy og scipy.
"""
import os
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- byggesten

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def phase(freq, dur):
    """Fase (i cyklusser) for en frekvens, der kan være et tal eller et array."""
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.cumsum(f) / SR


def square(freq, dur, duty=0.5):
    return np.where((phase(freq, dur) % 1.0) < duty, 1.0, -1.0)


def saw(freq, dur):
    return 2.0 * (phase(freq, dur) % 1.0) - 1.0


def tri(freq, dur):
    return 2.0 * np.abs(2.0 * (phase(freq, dur) % 1.0) - 1.0) - 1.0


def sine(freq, dur):
    return np.sin(2 * np.pi * phase(freq, dur))


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def sweep(f0, f1, dur, curve=1.0):
    k = np.linspace(0, 1, int(dur * SR)) ** curve
    return f0 * (f1 / f0) ** k


def env(dur, a=0.005, d=None, power=1.0):
    """Hurtigt anslag og eksponentielt-agtigt henfald."""
    n = int(dur * SR)
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    rest = np.linspace(1, 0, n - na) ** (power * 2.0)
    e[na:] = rest
    return e


def adsr(n, a, d, s, r):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    sus = max(0, n - a - d - r)
    return np.concatenate([np.linspace(0, 1, a, endpoint=False), np.linspace(1, s, d, endpoint=False),
                           np.full(sus, s), np.linspace(s, 0, r)])[:n]


def lp(x, cutoff, order=2):
    b, a = butter(order, min(cutoff, SR * 0.45) / (SR / 2), "low")
    return lfilter(b, a, x)


def hp(x, cutoff, order=2):
    b, a = butter(order, cutoff / (SR / 2), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], "band")
    return lfilter(b, a, x)


def crush(x, steps=16):
    """Bitcrush for ekstra retro-knas."""
    return np.round(x * steps) / steps


def echo(x, delay, fb, mix, tail=0.0):
    d = int(delay * SR)
    y = np.concatenate([x, np.zeros(int(tail * SR))])
    out = y.copy()
    for k in range(1, 8):
        g = mix * fb ** (k - 1)
        if g < 0.01:
            break
        out[k * d:] += y[:len(y) - k * d] * g
    return out


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def fade_out(x, dur=0.01):
    n = min(len(x), int(dur * SR))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


def save(name, x, peak=0.9):
    os.makedirs(OUT, exist_ok=True)
    x = norm(fade_out(np.asarray(x, dtype=float)), peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"{name}.wav  {len(x) / SR:.2f}s")


# ---------------------------------------------------------------- lydeffekter

def sfx():
    # Spillerens laser: kort firkant-pew, der falder i tone
    d = 0.16
    f = sweep(1500, 260, d, 0.6)
    save("laser", lp(square(f, d, 0.3) * env(d, 0.002, power=1.2), 6000) + 0.15 * sine(f * 0.5, d) * env(d))
    # Opgraderet laser: lysere og dobbelt
    f = sweep(2100, 420, d, 0.5)
    x = square(f, d, 0.25) + 0.6 * square(f * 1.5, d, 0.5)
    save("laser_tung", lp(x * env(d, 0.002, power=1.0), 7000))
    # Piratlaser: lavere, savtak, knurrende
    d = 0.22
    f = sweep(700, 140, d, 0.7)
    save("laser_pirat", crush(lp(saw(f, d) * env(d, 0.003, power=0.9), 3200), 10), 0.8)
    # Forsvarstårn: dyb puls
    d = 0.25
    save("taarn", lp(square(sweep(420, 90, d), d, 0.5) * env(d, 0.002), 2200) * 0.9)
    # Træf på pirat: kort knæk
    d = 0.09
    save("traef", hp(noise(d), 1200) * env(d, 0.001, power=1.5) + 0.5 * square(sweep(900, 400, d), d) * env(d))
    # Skjold rammes: elektrisk zap
    d = 0.3
    f = sweep(300, 1400, d, 0.5)
    save("skjold", bp(noise(d), 800, 5000) * env(d, 0.002) * 0.6 + sine(f, d) * env(d, 0.002) * 0.7)
    # Skrog rammes: dumpt bump
    d = 0.35
    save("skrog", lp(noise(d), 600) * env(d, 0.001, power=0.8) * 1.4 + sine(sweep(120, 45, d), d) * env(d))
    # Eksplosion (lille) og stor
    for name, d, cut in (("eksplosion", 0.9, 1800), ("eksplosion_stor", 1.6, 1300)):
        n = noise(d)
        c = sweep(cut, 120, d, 0.6)
        y = np.zeros_like(n)
        # Tidsvarierende lavpas: bloksvis filtrering
        blk = 512
        zi_b, zi_a = None, None
        for k in range(0, len(n), blk):
            b, a = butter(2, c[min(k, len(c) - 1)] / (SR / 2), "low")
            y[k:k + blk] = lfilter(b, a, n[k:k + blk])
        boom = sine(sweep(90, 30, d), d) * env(d, 0.002, power=0.7)
        save(name, crush(y * env(d, 0.003, power=0.6) * 2.2 + boom * 1.2, 24))
    # Asteroide knuses: grus
    d = 0.6
    save("sten", lp(noise(d), 2500) * env(d, 0.002, power=0.9) + 0.3 * crush(noise(d), 4) * env(d, 0.001, power=2))
    # Opsamling: stigende arpeggio
    notes = [880, 1109, 1319, 1760]
    x = np.concatenate([square(n, 0.05, 0.5) * env(0.05, 0.001, power=0.5) for n in notes])
    save("opsamling", lp(x, 6000), 0.6)
    # Lock-on: "låser" (to korte bip) og "låst" (høj tone)
    x = np.concatenate([square(1200, 0.05) * env(0.05, 0.001, power=0.3), np.zeros(int(0.05 * SR)),
                        square(1200, 0.05) * env(0.05, 0.001, power=0.3)])
    save("laaser", lp(x, 5000), 0.45)
    d = 0.22
    save("laast", lp(square(1760, d, 0.5) * adsr(int(d * SR), 0.003, 0.03, 0.7, 0.05) + 0.5 * square(2637, d), 6000), 0.45)
    save("lock_tabt", lp(square(sweep(900, 400, 0.18), 0.18) * env(0.18, 0.002), 4000), 0.4)
    # Brugerflade
    save("klik", square(1600, 0.03, 0.5) * env(0.03, 0.001, power=1.5), 0.35)
    x = np.concatenate([square(988, 0.06) * env(0.06, 0.001, power=0.4), square(1319, 0.1) * env(0.1, 0.001, power=0.6)])
    save("bekraeft", lp(x, 5000), 0.4)
    save("besked", lp(tri(1319, 0.08) * env(0.08, 0.002, power=0.6), 5000), 0.35)
    save("kort", lp(echo(square(sweep(600, 1200, 0.12), 0.12, 0.25) * env(0.12, 0.002), 0.07, 0.4, 0.4, 0.3), 4500), 0.4)
    save("markering", lp(echo(tri(1760, 0.08) * env(0.08, 0.001), 0.09, 0.45, 0.5, 0.4), 6000), 0.45)
    # Scanner: sonar-ping, der breder sig ud
    d = 1.6
    ping = sine(sweep(700, 1500, d, 0.3), d) * env(d, 0.004, power=0.5) * 0.6 + tri(sweep(350, 750, d, 0.3), d) * env(d, 0.004, power=0.8) * 0.4
    save("scan", lp(echo(ping, 0.22, 0.45, 0.45, 1.0), 5000), 0.55)
    # Fund: lille klokkespil
    x = np.concatenate([tri(n, 0.09) * env(0.09, 0.002, power=0.4) for n in (1319, 1760, 2093)])
    save("fund", lp(echo(x, 0.12, 0.4, 0.4, 0.5), 7000), 0.45)
    # Alarm (lavt skrog)
    x = np.concatenate([square(880, 0.12, 0.5) * adsr(int(0.12 * SR), 0.002, 0.02, 0.8, 0.02),
                        np.zeros(int(0.05 * SR)),
                        square(660, 0.12, 0.5) * adsr(int(0.12 * SR), 0.002, 0.02, 0.8, 0.02)])
    save("alarm", lp(x, 3500), 0.4)
    # Dock/landing: faldende sus + klonk
    d = 1.4
    w = bp(noise(d), 300, 2500) * adsr(int(d * SR), 0.3, 0.5, 0.5, 0.6) * 0.6
    k = np.zeros(int(d * SR))
    clonk = (square(220, 0.2) + square(110, 0.2)) * env(0.2, 0.001)
    k[int(1.15 * SR):int(1.15 * SR) + len(clonk)] = lp(clonk, 1500)[:len(k) - int(1.15 * SR)]
    save("dock", w + k)
    # Afgang: stigende motorbrøl
    d = 1.3
    f = sweep(60, 220, d, 0.8)
    save("afgang", lp(saw(f, d) + 0.5 * noise(d), 1500) * adsr(int(d * SR), 0.2, 0.3, 0.8, 0.6))
    # Trade lane: sus der stiger
    d = 1.6
    save("lane", echo(bp(noise(d), 500, 4000) * adsr(int(d * SR), 0.4, 0.2, 0.7, 0.8) + 0.3 * sine(sweep(200, 800, d), d) * env(d, 0.3), 0.12, 0.3, 0.3, 0.3))
    # Jump gate: stort sweep op og et brag
    d = 2.2
    f = sweep(80, 2400, d, 2.0)
    up = (saw(f, d) * 0.5 + square(f * 0.5, d) * 0.3) * adsr(int(d * SR), 0.3, 0.5, 0.9, 0.3)
    up = lp(up, 5000) + bp(noise(d), 1000, 6000) * np.linspace(0, 1, int(d * SR)) ** 3 * 0.6
    save("hop", echo(up, 0.15, 0.4, 0.4, 0.6))
    # Missionsjingles
    def jingle(notes, step, wave_fn=square):
        parts = [lp(wave_fn(n, step * l) * adsr(int(step * l * SR), 0.004, 0.05, 0.6, 0.06), 5000) for n, l in notes]
        return echo(np.concatenate(parts), 0.18, 0.35, 0.3, 0.6)
    save("mission_start", jingle([(659, 1), (880, 1), (988, 1), (1319, 3)], 0.09), 0.5)
    save("mission_ok", jingle([(523, 1), (659, 1), (784, 1), (1047, 2), (988, 1), (1047, 4)], 0.1), 0.5)
    save("mission_fejl", jingle([(659, 2), (622, 2), (587, 2), (440, 5)], 0.12, saw), 0.45)
    save("rang", jingle([(784, 1), (988, 1), (1175, 1), (1568, 1), (1175, 1), (1568, 5)], 0.08), 0.5)


def engine_loop():
    """Motorbrum, 2 sekunder, sømløs loop (heltalige cyklusser og krydsfadet støj)."""
    d = 2.0
    t = t_axis(d)
    x = saw(55, d) * 0.6 + square(110, d, 0.3) * 0.25 + sine(27.5, d) * 0.6
    x = x * (1.0 + 0.15 * np.sin(2 * np.pi * 4 * t))   # let pulsering, 4 Hz = heltal i 2 s
    n = noise(d + 0.2)
    n = lp(n, 900)
    m = int(0.2 * SR)
    body = n[m:].copy()
    body[:m] = body[:m] * np.linspace(0, 1, m) + n[:m] * np.linspace(1, 0, m)
    x = lp(x, 700) + body[:len(x)] * 0.8
    # Ingen udtoning i enden: den skal loope
    x = norm(x, 0.8)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, "motor.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("motor.wav  2.00s (loop)")


# ---------------------------------------------------------------- musik

NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name):
    """'A3' -> 220 Hz."""
    n, o = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[n] + 12 * (o - 4) - 9) / 12)


def place(buf, start, x):
    s = int(start * SR)
    e = min(len(buf), s + len(x))
    buf[s:e] += x[:e - s]
    # Det, der rækker ud over enden, lægges ind i starten, så loopet er sømløst.
    if s + len(x) > len(buf):
        over = x[e - s:]
        buf[:len(over)] += over


def note(fn, f, dur, a=0.005, d=0.08, s=0.6, r=0.08, cut=4000):
    n = int(dur * SR)
    return lp(fn(f, dur) * adsr(n, a, d, s, r), cut)


def kick():
    d = 0.25
    return sine(sweep(150, 40, d, 0.4), d) * env(d, 0.001, power=0.6) * 1.2


def snare():
    d = 0.2
    return bp(noise(d), 1000, 7000) * env(d, 0.001, power=1.0) * 0.6 + tri(sweep(300, 180, d), d) * env(d, 0.001, power=2) * 0.4


def hat():
    d = 0.05
    return hp(noise(d), 6000) * env(d, 0.001, power=1.5) * 0.35


def music_space():
    """Rolig rummusik: pad, arpeggio med ekko og blød bas. 84 BPM, 16 takter."""
    bpm = 84
    beat = 60 / bpm
    bars = 16
    total = bars * 4 * beat
    buf = np.zeros(int(total * SR))
    chords = [("A", ["A3", "C4", "E4", "B4"]), ("F", ["F3", "A3", "C4", "E4"]),
              ("C", ["C3", "G3", "C4", "E4"]), ("G", ["G3", "B3", "D4", "F#4"])]
    seq = [0, 0, 1, 1, 2, 2, 3, 3, 0, 0, 1, 1, 2, 3, 0, 0]
    for bar, ci in enumerate(seq):
        root, tones = chords[ci]
        t0 = bar * 4 * beat
        # Pad: to detunede savtakker, langsomt anslag, meget lavpas
        for tn in tones[:3]:
            f = hz(tn)
            n = int(4 * beat * SR)
            pad = (saw(f * 0.997, 4 * beat) + saw(f * 1.003, 4 * beat)) * adsr(n, 0.6, 0.5, 0.7, 0.8)
            place(buf, t0, lp(pad, 900) * 0.11)
        # Bas: hel og halv node
        bass_f = hz(tones[0]) / 2
        place(buf, t0, note(tri, bass_f, 2 * beat, 0.01, 0.2, 0.7, 0.2, 800) * 0.45)
        place(buf, t0 + 2.5 * beat, note(tri, bass_f, 1.5 * beat, 0.01, 0.2, 0.6, 0.2, 800) * 0.35)
        # Arpeggio i ottendedele, stigende/faldende
        pattern = [0, 1, 2, 3, 2, 1, 2, 3] if bar % 2 == 0 else [3, 2, 1, 2, 0, 1, 2, 1]
        for k, idx in enumerate(pattern):
            f = hz(tones[idx]) * 2
            place(buf, t0 + k * beat / 2, note(square, f, beat / 2 * 0.9, 0.003, 0.06, 0.3, 0.05, 3000) * 0.07)
    # Ekko på hele mixet (wrappet rundt, så loopet passer)
    d = int(beat * 0.75 * SR)
    out = buf.copy()
    for k in range(1, 4):
        out += np.roll(buf, k * d) * (0.28 * 0.5 ** (k - 1))
    # Blid "stjernefnug": høje bjældetoner med ekko i nogle takter
    for bar in (3, 7, 11, 15):
        t0 = bar * 4 * beat + 2 * beat
        for k, tn in enumerate(["E6", "B5", "A5"]):
            place(out, t0 + k * beat / 3, note(sine, hz(tn), 0.6, 0.002, 0.2, 0.2, 0.3, 8000) * 0.06)
    return out


def music_combat():
    """Kampmusik: drivende bas, trommer og en firkantbølge-melodi. 132 BPM, 16 takter."""
    bpm = 132
    beat = 60 / bpm
    bars = 16
    total = bars * 4 * beat
    buf = np.zeros(int(total * SR))
    prog = ["A2", "A2", "F2", "F2", "G2", "G2", "E2", "E2"] * 2
    lead = [  # (takt, slag, tone, længde i slag)
        (0, 0, "A4", 1.5), (0, 1.5, "C5", 0.5), (0, 2, "E5", 1), (0, 3, "D5", 1),
        (1, 0, "C5", 1.5), (1, 1.5, "B4", 0.5), (1, 2, "A4", 2),
        (2, 0, "F4", 1), (2, 1, "A4", 1), (2, 2, "C5", 1.5), (2, 3.5, "D5", 0.5),
        (3, 0, "E5", 3), (3, 3, "C5", 1),
        (4, 0, "G4", 1.5), (4, 1.5, "B4", 0.5), (4, 2, "D5", 1), (4, 3, "E5", 1),
        (5, 0, "D5", 1.5), (5, 1.5, "C5", 0.5), (5, 2, "B4", 2),
        (6, 0, "G#4", 1), (6, 1, "B4", 1), (6, 2, "E5", 1), (6, 3, "G#5", 1),
        (7, 0, "A5", 2), (7, 2, "E5", 2),
    ]
    for bar in range(bars):
        t0 = bar * 4 * beat
        root = hz(prog[bar])
        # Bas i ottendedele med oktavspring
        for k in range(8):
            f = root * (2 if k % 4 == 3 else 1)
            place(buf, t0 + k * beat / 2, note(saw, f, beat / 2 * 0.85, 0.002, 0.05, 0.5, 0.03, 1200) * 0.32)
        # Trommer
        for k in range(4):
            place(buf, t0 + k * beat, kick() * 0.7 if k in (0, 2) else snare() * 0.8)
            if bar % 4 == 3 and k == 3:
                place(buf, t0 + (k + 0.5) * beat, snare() * 0.6)
        for k in range(8):
            place(buf, t0 + k * beat / 2, hat() * (1.0 if k % 2 else 0.6))
        # Akkordstik på 2 og 4 (firkant, kort)
        third = 3 if prog[bar][0] in "AE" and prog[bar][0] != "E" else 4
        for k in (1, 3):
            for semis in (0, third, 7):
                place(buf, t0 + k * beat + beat / 2, note(square, root * 4 * 2 ** (semis / 12), beat * 0.3, 0.002, 0.05, 0.3, 0.03, 2500) * 0.035)
    # Melodi i anden halvdel og gentaget
    for rep in (0, 8):
        for bar, b, tn, ln in lead:
            if rep == 0 and bar < 4:
                continue    # første gang starter melodien halvvejs
            t0 = (bar + rep) * 4 * beat + b * beat
            place(buf, t0, note(square, hz(tn), ln * beat * 0.92, 0.004, 0.08, 0.55, 0.05, 3500) * 0.14)
            place(buf, t0, note(square, hz(tn) * 1.005, ln * beat * 0.92, 0.004, 0.08, 0.55, 0.05, 3500) * 0.05)
    d = int(beat * 0.75 * SR)
    out = buf + np.roll(buf, d) * 0.15
    return out


def save_loop(name, x, peak=0.8):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"{name}.wav  {len(x) / SR:.1f}s (loop)")


# ---------------------------------------------------------------- vejr

def loop_noise(dur, fade=0.25):
    """Støj, der kan loope sømløst (enden krydsfades ind i starten)."""
    n = noise(dur + fade)
    m = int(fade * SR)
    body = n[m:].copy()
    body[:m] = body[:m] * np.linspace(0, 1, m) + n[:m] * np.linspace(1, 0, m)
    return body


def weather_sounds():
    global rng
    rng = np.random.default_rng(99)
    # Vind (sandstorm): båndpasset støj med langsomme vindstød. 4 s loop.
    d = 4.0
    t = t_axis(d)
    w = bp(loop_noise(d + 0.3), 250, 1800)
    w = np.concatenate([w[int(0.3 * SR):], w[:int(0.3 * SR)]])[:len(t)]   # skub filterets indsvingning væk
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t) * np.sin(2 * np.pi * 0.25 * t + 1.0)
    hiss = hp(loop_noise(d), 3000) * 0.25
    save_loop("vind", w * gust + hiss * (0.5 + 0.5 * gust), 0.6)
    # Regn: tæt, lys støj med små dryp. 3 s loop.
    d = 3.0
    r = hp(loop_noise(d), 1500) * 0.6 + bp(loop_noise(d), 400, 1200) * 0.3
    drops = np.zeros(int(d * SR))
    for k in range(90):
        i = rng.integers(0, len(drops) - 300)
        drops[i:i + 300] += np.sin(np.linspace(0, 40, 300)) * np.linspace(1, 0, 300) * rng.uniform(0.1, 0.4)
    save_loop("regn", r + lp(drops, 4000), 0.5)
    # Torden: skarpt knald og lang rumlen
    d = 3.2
    crack = hp(noise(0.12), 1500) * env(0.12, 0.001, power=0.8)
    rumble = lp(noise(d), 220) * adsr(int(d * SR), 0.05, 0.6, 0.6, 2.2) * 3.0
    x = rumble.copy()
    x[:len(crack)] += crack * 1.5
    save("torden", crush(x, 32), 0.9)
    # Knitren: elektrisk opladning før et lynnedslag
    d = 1.0
    cr = np.zeros(int(d * SR))
    for k in range(70):
        i = rng.integers(0, len(cr) - 200)
        cr[i:i + 200] += hp(noise(200 / SR), 2500) * rng.uniform(0.3, 1.0) * (i / len(cr))
    hum = sine(sweep(80, 160, d), d) * np.linspace(0, 1, int(d * SR)) * 0.3
    save("knitren", cr + hum, 0.6)
    # Lavabombe affyres: dybt "whump" og susen
    d = 0.9
    save("lava", lp(noise(d), 600) * env(d, 0.01, power=0.7) * 1.5 + sine(sweep(90, 40, d), d) * env(d, 0.005) * 0.8, 0.8)
    # Syden/varme: knitrende hvæsen, loop
    d = 2.0
    sz = hp(loop_noise(d), 2500) * (0.7 + 0.3 * np.sin(2 * np.pi * 3 * t_axis(d)))
    save_loop("varme", sz, 0.45)


def weapon_sounds():
    """Lyde til de FTL-inspirerede våben og gadgets (egen rng, så de andre lyde ikke ændres)."""
    global rng
    rng = np.random.default_rng(42)
    # Ionkanon: blød, elektrisk "vwoom" med summen
    d = 0.32
    f = sweep(900, 180, d, 0.5)
    x = sine(f, d) * 0.8 + 0.4 * square(f * 2.01, d, 0.5) * env(d, 0.002, power=2.0) + bp(noise(d), 1500, 6000) * 0.25
    save("ion", lp(x * env(d, 0.004, power=0.8), 5000))
    # Flak: hult "thunk" ved affyring
    d = 0.28
    save("flak", lp(noise(d), 1400) * env(d, 0.001, power=1.6) * 1.2 + square(sweep(220, 70, d), d, 0.5) * env(d, 0.001) * 0.6)
    # Strålelaser: kort, lys summen (spilles igen og igen, mens strålen er tændt)
    d = 0.14
    t = t_axis(d)
    x = saw(1200 + 40 * np.sin(2 * np.pi * 60 * t), d) * 0.5 + sine(2400, d) * 0.3
    save("straale", lp(x, 6000) * (0.8 + 0.2 * np.sin(2 * np.pi * 30 * t)), 0.55)
    # Kædekanon: tørt, kort knald
    d = 0.07
    save("kaede", hp(noise(d), 900) * env(d, 0.0005, power=2.0) + square(sweep(700, 300, d), d, 0.4) * env(d, 0.0005, power=2.0) * 0.6, 0.75)
    # Krystalkanon: klokkeagtig, høj
    d = 0.4
    x = sine(sweep(2600, 1800, d), d) + 0.6 * sine(sweep(3900, 2700, d), d) + 0.3 * tri(sweep(1300, 900, d), d)
    save("krystal", x * env(d, 0.001, power=1.4), 0.8)
    # Kappe: opadgående susen, der forsvinder
    d = 0.8
    save("kappe", bp(noise(d), 300, 3000) * env(d, 0.05, power=0.8) * 0.7 + sine(sweep(200, 1200, d), d) * env(d, 0.02) * 0.4, 0.7)
    # EMP: dyb pulsbølge med knitren
    d = 1.0
    x = sine(sweep(160, 40, d), d) * env(d, 0.002, power=0.6) + hp(noise(d), 3000) * env(d, 0.001, power=2.5) * 0.6
    save("emp", crush(x, 24), 0.9)
    # Drone: lille "pip-pew"
    d = 0.1
    save("drone", lp(square(sweep(2400, 900, d), d, 0.25) * env(d, 0.001, power=1.3), 7000), 0.6)
    # Skjoldbatteri: stigende akkord
    d = 0.7
    x = sum(sine(sweep(f0, f0 * 1.5, d), d) for f0 in (330, 415, 495)) / 3
    save("batteri", x * env(d, 0.01, power=0.7), 0.7)


if __name__ == "__main__":
    sfx()
    engine_loop()
    save_loop("musik_rum", music_space(), 0.7)
    save_loop("musik_kamp", music_combat(), 0.75)
    weather_sounds()
    weapon_sounds()
