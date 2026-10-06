#!/usr/bin/env python3
"""MEWD — the pickups' sounds (assets/sfx/pickup.wav, powerup.wav,
noammo.wav), made here, at the user's request for the pickups: every
synthesised sound in the game is muted (Sound.MUTED), so a take, a big
take and an empty trigger each want a recording. Three small ones,
written out of sines and noise: a two-note blip for a pickup, a rising
four-note run for a big one (and IDDQD), a dry click for nothing in the
gun.

    python3 -I tools/pickup-sounds.py
"""
import wave

import numpy as np

RATE = 44100


def tone(f, dur, amp=0.5, decay=8.0, square=0.25):
    t = np.arange(int(RATE * dur)) / RATE
    s = np.sin(2 * np.pi * f * t) + square * np.sign(np.sin(2 * np.pi * f * t))
    env = np.minimum(1.0, t / 0.004) * np.exp(-t * decay)
    return amp * s * env


def write(path, x):
    x = np.clip(x / max(1e-6, np.abs(x).max()) * 0.8, -1, 1)
    pcm = (x * 32767).astype(np.int16)
    st = np.stack([pcm, pcm], -1).reshape(-1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(st.tobytes())
    print(path, len(x) / RATE, "s")


# a pickup: two quick notes, a fifth apart
a = tone(988.0, 0.07, decay=30.0)
b = tone(1480.0, 0.11, decay=22.0)
write("assets/sfx/pickup.wav", np.concatenate([a, b]))

# a big one: a run up a major arpeggio, the last note held a little
notes = [523.25, 659.25, 783.99, 1046.5]
parts = [tone(f, 0.065 if i < 3 else 0.22, decay=18.0 if i < 3 else 7.0) for i, f in enumerate(notes)]
run = np.concatenate(parts)
# (and the same an octave up, quietly, for shine)
shine = np.concatenate([tone(f * 2, len(p) / RATE, amp=0.15, decay=12.0) for f, p in zip(notes, parts)])
write("assets/sfx/powerup.wav", run + shine)

# an empty trigger: a click and a dull knock
rng = np.random.default_rng(7)
n = int(RATE * 0.06)
t = np.arange(n) / RATE
click = rng.standard_normal(n) * np.exp(-t * 400.0)
knock = np.sin(2 * np.pi * 180.0 * t) * np.exp(-t * 60.0) * 0.6
write("assets/sfx/noammo.wav", click + knock)
