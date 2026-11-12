#!/usr/bin/env python3
"""Generates the game's sound effects into assets/audio/sfx/ (16-bit mono WAV, 44.1 kHz).

    python3 tools/make_sfx.py

Made for Cube Idle, released as CC0. Standard library only. Style (PLAN §4.3): soft and warm, to sit
under lo-fi music: a plastic cube "clack", a mellow electric-piano chime, a soft pluck, an arpeggio sting.
Tweak the numbers here and re-run; the WAVs are committed so the game doesn't need Python.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "sfx")
random.seed(7)  # same files every run


def lowpass(samples, cutoff):
    """One-pole low-pass filter: takes the edge off, for warmth."""
    rc = 1.0 / (2 * math.pi * cutoff)
    alpha = (1.0 / RATE) / (rc + 1.0 / RATE)
    out, y = [], 0.0
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [x - l for x, l in zip(samples, low)]


def envelope(n, attack, decay):
    """Short linear attack, exponential decay (times in seconds)."""
    a = max(1, int(attack * RATE))
    return [(i / a) if i < a else math.exp(-(i - a) / (decay * RATE)) for i in range(n)]


def rhodes(freq, seconds, decay=0.9, brightness=1.4):
    """Electric-piano-ish FM tone: a sine carrier, a 1:1 modulator whose depth decays (bright attack, mellow tail)."""
    n = int(seconds * RATE)
    env = envelope(n, 0.004, decay)
    out = []
    for i in range(n):
        t = i / RATE
        index = brightness * math.exp(-t * 6.0)
        mod = math.sin(2 * math.pi * freq * t) * index
        tone = math.sin(2 * math.pi * freq * t + mod)
        tone += 0.25 * math.sin(2 * math.pi * freq * 2.0 * t + mod * 0.5) * math.exp(-t * 4.0)  # bell overtone
        out.append(tone * env[i])
    return out


def pluck(freq, seconds, damping=0.996):
    """Karplus-Strong plucked string: soft and woody."""
    n = int(seconds * RATE)
    period = int(RATE / freq)
    buf = [random.uniform(-1, 1) for _ in range(period)]
    buf = lowpass(buf, 3000)
    out = []
    for i in range(n):
        j = i % period
        value = buf[j]
        buf[j] = damping * 0.5 * (buf[j] + buf[(j + 1) % period])
        out.append(value)
    return out


def mix(*tracks):
    n = max(len(t) for t, _, _ in tracks)
    out = [0.0] * n
    for samples, offset_s, gain in tracks:
        offset = int(offset_s * RATE)
        for i, s in enumerate(samples):
            if offset + i < n:
                out[offset + i] += s * gain
            else:
                out.append(s * gain)
    return out


def pad(samples, seconds):
    return samples + [0.0] * int(seconds * RATE)


def normalize(samples, peak):
    top = max(1e-9, max(abs(s) for s in samples))
    return [s / top * peak for s in samples]


def fade_out(samples, seconds=0.02):
    n = min(len(samples), int(seconds * RATE))
    for i in range(n):
        samples[-1 - i] *= i / n
    return samples


def write(name, samples, peak):
    samples = fade_out(normalize(highpass(samples, 30), peak))  # high-pass removes any DC offset
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print("wrote", os.path.relpath(path), "%.2f s" % (len(samples) / RATE))


def click():
    """A cube turn: a short band-limited plastic clack plus a tiny low knock."""
    n = int(0.07 * RATE)
    noise = [random.uniform(-1, 1) for _ in range(n)]
    clack = highpass(lowpass(noise, 4200), 900)
    clack = [s * e for s, e in zip(clack, envelope(n, 0.0008, 0.012))]
    knock = [math.sin(2 * math.pi * 210 * i / RATE) * e for i, e in enumerate(envelope(n, 0.001, 0.018))]
    second = [s * 0.5 for s in clack]  # the layer settling a moment later
    return lowpass(mix((clack, 0.0, 1.0), (knock, 0.0, 0.55), (second, 0.018, 0.6)), 6000)


def chime():
    """A solve: a mellow Rhodes major third (E5 + G#5) with a soft low root."""
    return lowpass(mix(
        (rhodes(659.25, 1.4, decay=0.55), 0.0, 1.0),
        (rhodes(830.61, 1.4, decay=0.5), 0.012, 0.55),
        (rhodes(329.63, 1.4, decay=0.45, brightness=0.8), 0.0, 0.35),
    ), 5000)


def buy():
    """A purchase: two quick soft plucks going up a fourth."""
    return lowpass(pad(mix((pluck(523.25, 0.45), 0.0, 1.0), (pluck(698.46, 0.5), 0.07, 0.9)), 0.05), 4500)


def unlock():
    """Something new: a rising Rhodes arpeggio C-E-G-C with a long tail."""
    notes = [523.25, 659.25, 783.99, 1046.5]
    tracks = [(rhodes(f, 1.6, decay=0.7), i * 0.09, 1.0 - i * 0.12) for i, f in enumerate(notes)]
    return lowpass(mix(*tracks), 5200)


def hover():
    """A button under the pointer (V.9): a tiny, high, very short tick, felt more than heard."""
    n = int(0.03 * RATE)
    tick = [math.sin(2 * math.pi * 2400 * i / RATE) * e for i, e in enumerate(envelope(n, 0.0005, 0.006))]
    return lowpass(tick, 7000)


def press():
    """A button pressed (V.9): a soft rounded tap, the cube clack's quieter, rounder sibling."""
    n = int(0.06 * RATE)
    noise = [random.uniform(-1, 1) for _ in range(n)]
    tap = highpass(lowpass(noise, 2600), 500)
    tap = [s * e for s, e in zip(tap, envelope(n, 0.0008, 0.008))]
    body = [math.sin(2 * math.pi * 330 * i / RATE) * e for i, e in enumerate(envelope(n, 0.001, 0.02))]
    return lowpass(mix((tap, 0.0, 0.8), (body, 0.0, 0.7)), 4000)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("click.wav", click(), 0.55)
    write("chime.wav", chime(), 0.5)
    write("buy.wav", buy(), 0.55)
    write("unlock.wav", unlock(), 0.55)
    write("hover.wav", hover(), 0.18)
    write("press.wav", press(), 0.4)
