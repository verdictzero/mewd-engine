#!/usr/bin/env python3
"""MEWD — the fetus launcher's sounds (assets/sfx/fetus_launch.wav,
fetus_cry_1..4.wav, fetus_splat.wav), the user's own:

THE LAUNCH is the user's goop_12.wav ("launch sound effect",
tools/art/sfx/goop_12.wav), copied as it came: 0.66 s, 44.1 kHz stereo,
its peak at -5 dB.

THE CRIES are cut from the user's "cut this up into distinct SFX"
(tools/art/sfx/fetus_launcher_takes.wav as it came: 6.9 s, 48 kHz
stereo).

THE TAKES. The file is four takes of the one sound, back to back with a
breath of room noise between them — a cry, a voice's harmonics bending
at its start and end over a hiss with a hard band near 2.7 kHz — and
nothing between them falls to silence, so they are cut where the room
noise is lowest (CUTS, found off the loudness in 5 ms steps: each gap
bottoms out 25 to 30 dB under the takes). Each one: the two channels
mixed down (they are 0.9 alike, and the game does not pan), 4 ms in and
40 ms out so no cut clicks, and one gain for all four — the loudest
peak of the four to -1 dB — so they keep their loudness to each other.
Each fetus cries one of them as it flies (FetusLauncher.CRIES), never the
same one twice running, from where it is (Sound.voice): it fades as the
fetus goes away and stops when it lands.

THE SPLAT is made here, out of noise and sines, as the pickups' were
(tools/pickup-sounds.py), until the user's own: a thump with its pitch
falling away, a wet tearing burst, and a patter of drops after.

    python3 -I tools/fetus-sounds.py
"""
import shutil
import wave

import numpy as np

SRC = "tools/art/sfx/fetus_launcher_takes.wav"
# (start, end) in seconds, each take's
CUTS = [(0.120, 1.560), (1.565, 3.700), (3.770, 5.400), (5.435, 6.900)]
FADE_IN = 0.004
FADE_OUT = 0.040
PEAK = 10 ** (-1.0 / 20.0)


def read(path):
    with wave.open(path) as w:
        rate = w.getframerate()
        ch = w.getnchannels()
        a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, ch).astype(np.float64) / 32768.0
    return a.mean(axis=1), rate


def write(path, x, rate):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())
    print(path, "%.3f s" % (len(x) / rate), "peak %.1f dB" % (20 * np.log10(np.abs(x).max() + 1e-9)))


shutil.copyfile("tools/art/sfx/goop_12.wav", "assets/sfx/fetus_launch.wav")
print("assets/sfx/fetus_launch.wav (goop_12.wav as it came)")

x, rate = read(SRC)
takes = []
for t0, t1 in CUTS:
    s = x[int(t0 * rate):int(t1 * rate)].copy()
    n_in = int(FADE_IN * rate)
    n_out = int(FADE_OUT * rate)
    s[:n_in] *= np.linspace(0.0, 1.0, n_in)
    s[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    takes.append(s)
gain = PEAK / max(np.abs(s).max() for s in takes)
for i, s in enumerate(takes):
    write("assets/sfx/fetus_cry_%d.wav" % (i + 1), s * gain, rate)

# THE SPLAT
RATE = 44100
rng = np.random.default_rng(23)
dur = 1.1
t = np.arange(int(RATE * dur)) / RATE
# the thump: a low sine falling from 95 to 38 Hz, gone in a quarter second
f = 38.0 + 57.0 * np.exp(-t * 18.0)
thump = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 14.0)


def band(noise, lo, hi):
    # a band of noise, cut in the spectrum (brick-wall, soft at the edges)
    spec = np.fft.rfft(noise)
    fr = np.fft.rfftfreq(len(noise), 1.0 / RATE)
    k = np.clip((fr - lo) / (lo * 0.5), 0, 1) * np.clip((hi - fr) / (hi * 0.3), 0, 1)
    return np.fft.irfft(spec * k, len(noise))


# the tearing: wet grains of band noise, thick at first and thinning out
tear = np.zeros_like(t)
for _ in range(220):
    at = rng.exponential(0.07)
    if at > 0.6:
        continue
    n = int(RATE * rng.uniform(0.004, 0.022))
    i = int(at * RATE)
    if i + n >= len(t):
        continue
    g = band(rng.standard_normal(n), rng.uniform(250, 700), rng.uniform(1500, 4200))
    g *= np.hanning(n) * rng.uniform(0.3, 1.0) * np.exp(-at * 5.0)
    tear[i:i + n] += g
tear /= max(1e-9, np.abs(tear).max())
# the first slap: a short broad burst
slap_n = int(RATE * 0.05)
slap = band(rng.standard_normal(slap_n), 180, 6000) * np.exp(-np.arange(slap_n) / RATE * 70.0)
slap /= max(1e-9, np.abs(slap).max())
# the drops: little rising plips scattered after
drops = np.zeros_like(t)
for _ in range(14):
    at = rng.uniform(0.15, 1.0)
    n = int(RATE * 0.05)
    i = int(at * RATE)
    if i + n >= len(t):
        continue
    tt = np.arange(n) / RATE
    f0 = rng.uniform(500, 1100)
    drops[i:i + n] += np.sin(2 * np.pi * (f0 * tt + f0 * 6.0 * tt * tt)) * np.exp(-tt * 90.0) * rng.uniform(0.15, 0.45) * np.exp(-(at - 0.15) * 1.5)
mix = thump * 0.7 + tear * 0.95 + drops * 0.6
mix[:slap_n] += slap * 0.7
mix *= np.minimum(1.0, (len(t) - np.arange(len(t))) / (RATE * 0.05))
write("assets/sfx/fetus_splat.wav", mix / np.abs(mix).max() * PEAK, RATE)
