#!/usr/bin/env python3
"""Generates placeholder lo-fi music loops into assets/audio/music/ (16-bit mono WAV, 22.05 kHz).

    python3 tools/make_music.py

Made for Cube Idle, released as CC0. Standard library only, so it runs anywhere; slow-ish (~1 min).
These are PLACEHOLDERS until the final soundtrack (open decision D8). Style follows PLAN §4.3: lo-fi hip-hop,
soft drums, electric-piano chords, bass, vinyl crackle. Each file is an 8-bar loop whose tail is folded back
into its start, so it loops without a gap or click.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "music")
TWO_PI = 2 * math.pi


def note(name):
    """'C4' / 'F#3' / 'Bb2' -> frequency in Hz."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    semis = names[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        semis, rest = semis + 1, rest[1:]
    elif rest[0] == "b":
        semis, rest = semis - 1, rest[1:]
    midi = 12 * (int(rest) + 1) + semis
    return 440.0 * 2 ** ((midi - 69) / 12)


class Track:
    def __init__(self, bpm, bars, seed):
        self.beat = 60.0 / bpm
        self.length = int(bars * 4 * self.beat * RATE)
        self.buf = [0.0] * (self.length + RATE * 4)  # room for tails, folded back at the end
        self.rng = random.Random(seed)

    def add(self, samples, start_s, gain):
        start = int(start_s * RATE)
        buf = self.buf
        for i, s in enumerate(samples):
            j = start + i
            if j >= len(buf):
                break
            buf[j] += s * gain

    def finish(self):
        """Fold the tail into the start (seamless loop), then soften and normalise."""
        out = self.buf[:self.length]
        for i, s in enumerate(self.buf[self.length:]):
            out[i % self.length] += s
        out = lowpass(out, 4200)
        out = [math.tanh(s * 1.2) for s in out]  # gentle tape saturation
        rms = math.sqrt(sum(s * s for s in out) / len(out)) or 1.0
        target = 10 ** (-20 / 20)  # about -20 dBFS RMS, so music sits under the SFX
        return [max(-0.95, min(0.95, s * target / rms)) for s in out]


def lowpass(samples, cutoff):
    rc = 1.0 / (TWO_PI * cutoff)
    alpha = (1.0 / RATE) / (rc + 1.0 / RATE)
    out, y = [], 0.0
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def rhodes(freq, seconds, decay=1.6, brightness=1.1, wobble=0.0025):
    """Electric piano: FM with a decaying index, plus a slow tape-wobble vibrato."""
    n = int(seconds * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq * (1.0 + wobble * math.sin(TWO_PI * 0.6 * t))
        phase += TWO_PI * f / RATE
        index = brightness * math.exp(-t * 5.0)
        env = min(1.0, t / 0.006) * math.exp(-t / decay)
        out.append(math.sin(phase + index * math.sin(phase)) * env)
    return out


def pad(track, notes, start_s, seconds, gain):
    """A soft sustained bed under the chords (slow attack and release), so the music never drops out."""
    n = int(seconds * RATE)
    attack, release = int(0.4 * RATE), int(0.8 * RATE)
    for name in notes:
        freq = note(name)
        out = []
        for i in range(n + release):
            env = min(1.0, i / attack) if i < n else max(0.0, 1.0 - (i - n) / release)
            t = i / RATE
            out.append((math.sin(TWO_PI * freq * t) + 0.3 * math.sin(TWO_PI * freq * 2.003 * t)) * env)
        track.add(out, start_s, gain / len(notes))


def chord(track, notes, start_s, seconds, gain, strum=0.018):
    for k, name in enumerate(notes):
        track.add(rhodes(note(name), seconds + 1.5), start_s + k * strum, gain / len(notes) ** 0.5)


def bass(freq, seconds):
    n = int(seconds * RATE)
    return [math.tanh(1.6 * math.sin(TWO_PI * freq * i / RATE)) * min(1.0, i / 200) * math.exp(-i / (RATE * seconds * 0.8))
            for i in range(n)]


def kick(rng):
    n = int(0.35 * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 48 + 90 * math.exp(-t * 30)
        phase += TWO_PI * f / RATE
        out.append(math.sin(phase) * math.exp(-t * 9))
    return out


def snare(rng):
    n = int(0.25 * RATE)
    noise = lowpass([rng.uniform(-1, 1) for _ in range(n)], 3500)
    return [(noise[i] * 0.8 + 0.4 * math.sin(TWO_PI * 185 * i / RATE)) * math.exp(-i / (RATE * 0.055)) for i in range(n)]


def hat(rng):
    n = int(0.06 * RATE)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    low = lowpass(noise, 6000)
    return [(noise[i] - low[i]) * math.exp(-i / (RATE * 0.012)) for i in range(n)]


def crackle(track, density, gain, rain=0.0):
    """Vinyl crackle (sparse clicks) and, optionally, soft rain (filtered noise)."""
    rng = track.rng
    for i in range(track.length):
        if rng.random() < density:
            track.buf[i] += rng.uniform(-1, 1) * gain
    if rain > 0:
        noise = lowpass(lowpass([rng.uniform(-1, 1) for _ in range(track.length)], 1800), 1800)
        for i, s in enumerate(noise):
            track.buf[i] += s * rain


def drums(track, bars, pattern, swing, gains):
    """pattern: per 16th step (16 per bar) a string of k/s/h."""
    rng = track.rng
    sixteenth = track.beat / 4
    sounds = {"k": kick, "s": snare, "h": hat}
    for bar in range(bars):
        for step in range(16):
            t = (bar * 16 + step) * sixteenth
            if step % 2 == 1:
                t += swing * sixteenth  # swung off-beats
            for hit in pattern[step]:
                if hit == "h" and rng.random() < 0.15:
                    continue  # human: skip a few hats
                vel = rng.uniform(0.8, 1.0)
                track.add(sounds[hit](rng), t + rng.uniform(-0.004, 0.004), gains[hit] * vel)


def write(name, samples):
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", os.path.relpath(path), "%.1f s" % (len(samples) / RATE))


def practice_room():
    """2×2 track: sparse, ~70 BPM, soft kick, Rhodes, rain. Fmaj7 - Em7 - Dm7 - Cmaj7, two bars each."""
    track = Track(bpm=70, bars=8, seed=1)
    bar = 4 * track.beat
    chords = [["F3", "A3", "C4", "E4"], ["E3", "G3", "B3", "D4"], ["D3", "F3", "A3", "C4"], ["C3", "E3", "G3", "B3"]]
    roots = ["F2", "E2", "D2", "C2"]
    for i, notes in enumerate(chords):
        start = i * 2 * bar
        chord(track, notes, start, bar * 1.2, 0.55)
        chord(track, notes[1:], start + bar + 2.5 * track.beat, bar * 0.6, 0.35)
        pad(track, notes, start, 2 * bar, 0.22)
        track.add(bass(note(roots[i]), bar * 0.9), start, 0.5)
        track.add(bass(note(roots[i]), bar * 0.7), start + bar + 2 * track.beat, 0.4)
    pattern = ["k", "", "h", "", "s", "", "h", "", "", "", "kh", "", "s", "", "h", ""]
    drums(track, 8, pattern, swing=0.25, gains={"k": 0.55, "s": 0.22, "h": 0.06})
    crackle(track, 0.0006, 0.2, rain=0.05)
    return track.finish()


def first_sub_20():
    """3×3 track: classic chillhop, ~80 BPM, swung drums, jazzy ii-V-I-vi: Dm9 - G13 - Cmaj9 - A7b9."""
    track = Track(bpm=80, bars=8, seed=2)
    bar = 4 * track.beat
    chords = [["F3", "A3", "C4", "E4"], ["F3", "B3", "E4", "A4"], ["E3", "G3", "B3", "D4"], ["G3", "C#4", "E4", "Bb4"]]
    roots = ["D2", "G2", "C2", "A2"]
    for rep in range(2):
        for i, notes in enumerate(chords):
            start = (rep * 4 + i) * bar
            chord(track, notes, start, bar * 0.9, 0.55, strum=0.012)
            pad(track, notes, start, bar, 0.16)
            chord(track, notes, start + 1.5 * track.beat, bar * 0.4, 0.3, strum=0.006)
            track.add(bass(note(roots[i]), track.beat * 1.4), start, 0.5)
            track.add(bass(note(roots[i]) * 1.5, track.beat * 0.8), start + 2.5 * track.beat, 0.35)
    pattern = ["kh", "", "h", "k", "sh", "", "h", "", "kh", "", "kh", "", "sh", "", "h", "h"]
    drums(track, 8, pattern, swing=0.33, gains={"k": 0.6, "s": 0.28, "h": 0.08})
    crackle(track, 0.0005, 0.18)
    return track.finish()


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("practice_room.wav", practice_room())
    write("first_sub_20.wav", first_sub_20())
