#!/usr/bin/env python3
"""Generates placeholder lo-fi music loops into assets/audio/music/ (16-bit mono WAV, 22.05 kHz).

    python3 tools/make_music.py              # every track
    python3 tools/make_music.py parity.wav   # one track

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
        out = lowpass(out[-4000:] + out, 4200)[4000:]  # pre-roll with the loop's end, so the filter has no start-up jump at the seam
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


def pluck(freq, seconds, damping=0.995, rng=None):
    """Karplus-Strong plucked string (guitar licks)."""
    rng = rng or random.Random(int(freq))
    n = int(seconds * RATE)
    period = max(2, int(RATE / freq))
    buf = lowpass([rng.uniform(-1, 1) for _ in range(period)], 2500)
    out = []
    for i in range(n):
        j = i % period
        value = buf[j]
        buf[j] = damping * 0.5 * (buf[j] + buf[(j + 1) % period])
        out.append(value)
    return out


def kalimba(freq, seconds):
    """Kalimba / vibraphone-like: a sine with a quick metallic overtone and a long soft decay."""
    n = int(seconds * RATE)
    return [(math.sin(TWO_PI * freq * i / RATE) + 0.35 * math.sin(TWO_PI * freq * 4.2 * i / RATE) * math.exp(-i / (RATE * 0.05)))
            * min(1.0, i / 60) * math.exp(-i / (RATE * 0.9)) for i in range(n)]


def lead(freq, seconds):
    """A soft synth lead: a few harmonics, gentle attack and vibrato."""
    n = int(seconds * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += TWO_PI * freq * (1.0 + 0.004 * math.sin(TWO_PI * 5.0 * t)) / RATE
        tone = math.sin(phase) + 0.4 * math.sin(2 * phase) + 0.2 * math.sin(3 * phase)
        env = min(1.0, t / 0.04) * min(1.0, (seconds - t) / 0.08)
        out.append(tone * env * 0.6)
    return out


def melody(track, notes, start_s, step_s, instrument, gain):
    """notes: note names or None (rest), one per step."""
    for i, name in enumerate(notes):
        if name:
            track.add(instrument(note(name), step_s * 1.8), start_s + i * step_s, gain)


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


def parity():
    """4×4 track: warmer, ~84 BPM, walking bass, guitar licks, tape wobble. Am7 - D9 - Gmaj7 - Cmaj7."""
    track = Track(bpm=84, bars=8, seed=3)
    bar = 4 * track.beat
    chords = [["G3", "C4", "E4", "A4"], ["F#3", "C4", "E4", "A4"], ["F#3", "B3", "D4", "G4"], ["E3", "G3", "B3", "E4"]]
    walks = [["A2", "C3", "E3", "G3"], ["D2", "F#2", "A2", "C3"], ["G2", "B2", "D3", "F#3"], ["C2", "E2", "G2", "B2"]]
    licks = [["E4", None, "G4", "A4", None, "C5", None, "A4"], [None, "D5", None, "C5", "A4", None, "G4", None]]
    for rep in range(2):
        for i, notes in enumerate(chords):
            start = (rep * 4 + i) * bar
            chord(track, notes, start, bar * 0.9, 0.5, strum=0.02)
            pad(track, notes, start, bar, 0.14)
            for k, name in enumerate(walks[i]):
                track.add(bass(note(name), track.beat * 0.9), start + k * track.beat, 0.42)
            melody(track, licks[(rep + i) % 2], start, track.beat / 2, pluck, 0.22)
    pattern = ["kh", "", "h", "", "sh", "", "h", "k", "kh", "", "h", "", "sh", "", "h", "h"]
    drums(track, 8, pattern, swing=0.3, gains={"k": 0.6, "s": 0.26, "h": 0.07})
    crackle(track, 0.0005, 0.18)
    return track.finish()


def big_cube_energy():
    """5×5 track: the most upbeat, ~92 BPM, brighter drums, a soft synth lead. Fmaj7 - G6 - Em7 - Am9."""
    track = Track(bpm=92, bars=8, seed=4)
    bar = 4 * track.beat
    chords = [["F3", "A3", "C4", "E4"], ["G3", "B3", "D4", "E4"], ["E3", "G3", "B3", "D4"], ["A3", "C4", "E4", "B4"]]
    roots = ["F2", "G2", "E2", "A2"]
    tune = ["C5", None, "E5", "D5", None, "C5", "A4", None, "G4", None, "A4", "C5", None, "D5", None, None]
    for rep in range(2):
        for i, notes in enumerate(chords):
            start = (rep * 4 + i) * bar
            chord(track, notes, start, bar * 0.6, 0.45, strum=0.008)
            chord(track, notes, start + 2.5 * track.beat, bar * 0.3, 0.3, strum=0.006)
            pad(track, notes, start, bar, 0.12)
            track.add(bass(note(roots[i]), track.beat * 0.8), start, 0.5)
            track.add(bass(note(roots[i]), track.beat * 0.6), start + 1.5 * track.beat, 0.35)
            track.add(bass(note(roots[i]) * 1.5, track.beat * 0.6), start + 3 * track.beat, 0.3)
        melody(track, tune, rep * 4 * bar + 2 * bar, track.beat / 2, lead, 0.16)
    pattern = ["kh", "h", "h", "kh", "sh", "h", "h", "h", "kh", "h", "kh", "h", "sh", "h", "h", "h"]
    drums(track, 8, pattern, swing=0.2, gains={"k": 0.65, "s": 0.3, "h": 0.08})
    crackle(track, 0.0004, 0.15)
    return track.finish()


def long_solve():
    """7×7 track: spacious ambient lo-fi, ~66 BPM, long pads, a slow beat. Dmaj9 - Bm11 - Gmaj9 - Aadd9."""
    track = Track(bpm=66, bars=8, seed=5)
    bar = 4 * track.beat
    chords = [["D3", "F#3", "A3", "E4"], ["B2", "E3", "A3", "D4"], ["G2", "B2", "F#3", "A3"], ["A2", "C#3", "E3", "B3"]]
    roots = ["D2", "B1", "G1", "A1"]
    for i, notes in enumerate(chords):
        start = i * 2 * bar
        pad(track, notes, start, 2 * bar, 0.4)
        chord(track, notes[1:], start + track.beat, bar, 0.28, strum=0.06)
        track.add(bass(note(roots[i]), bar * 1.5), start, 0.4)
    pattern = ["k", "", "", "", "", "", "h", "", "s", "", "", "", "", "", "h", ""]
    drums(track, 8, pattern, swing=0.2, gains={"k": 0.45, "s": 0.18, "h": 0.05})
    crackle(track, 0.0005, 0.16, rain=0.04)
    return track.finish()


def twelve_faces():
    """Megaminx track: lo-fi with a twist, ~78 BPM, a kalimba melody over Cmaj7 - Bm7 - Am9 - Gsus."""
    track = Track(bpm=78, bars=8, seed=6)
    bar = 4 * track.beat
    chords = [["E3", "G3", "B3", "C4"], ["D3", "F#3", "A3", "B3"], ["C3", "E3", "G3", "B3"], ["D3", "G3", "A3", "C4"]]
    roots = ["C2", "B1", "A1", "G1"]
    phrase = ["E5", "G5", "B5", None, "A5", "G5", None, "E5", "D5", None, "E5", "G5", None, None, "B4", None]
    for rep in range(2):
        for i, notes in enumerate(chords):
            start = (rep * 4 + i) * bar
            chord(track, notes, start, bar * 0.8, 0.38, strum=0.015)
            pad(track, notes, start, bar, 0.14)
            track.add(bass(note(roots[i]), track.beat * 1.6), start, 0.45)
            track.add(bass(note(roots[i]), track.beat * 0.8), start + 2.5 * track.beat, 0.3)
        melody(track, phrase, rep * 4 * bar, track.beat / 2, kalimba, 0.2)
        melody(track, phrase[::-1], rep * 4 * bar + 2 * bar, track.beat / 2, kalimba, 0.16)
    pattern = ["k", "", "h", "", "s", "", "h", "", "", "k", "h", "", "s", "", "h", ""]
    drums(track, 8, pattern, swing=0.28, gains={"k": 0.55, "s": 0.22, "h": 0.06})
    crackle(track, 0.0005, 0.16)
    return track.finish()


def finals():
    """World Championship track: celebratory, fuller, ~88 BPM, a bigger groove. Fmaj9 - Em7 - Dm9 - G13 - C."""
    track = Track(bpm=88, bars=8, seed=7)
    bar = 4 * track.beat
    chords = [["F3", "A3", "E4", "G4"], ["E3", "G3", "D4", "B4"], ["D3", "F3", "C4", "E4"], ["F3", "B3", "E4", "A4"]]
    roots = ["F2", "E2", "D2", "G2"]
    hook = ["A4", "C5", "E5", None, "D5", "C5", "D5", "E5", None, "G5", "E5", None, "D5", None, "C5", None]
    for rep in range(2):
        for i, notes in enumerate(chords):
            start = (rep * 4 + i) * bar
            chord(track, notes, start, bar * 0.7, 0.5, strum=0.01)
            chord(track, notes, start + 2 * track.beat, bar * 0.4, 0.35, strum=0.008)
            pad(track, notes, start, bar, 0.18)
            for k in range(4):
                track.add(bass(note(roots[i]) * (1.0 if k % 2 == 0 else 1.5), track.beat * 0.7), start + k * track.beat, 0.4)
        melody(track, hook, rep * 4 * bar, track.beat / 2, lead, 0.15)
        melody(track, hook, rep * 4 * bar + 2 * bar, track.beat / 2, kalimba, 0.14)
    pattern = ["kh", "h", "h", "kh", "sh", "h", "kh", "h", "kh", "h", "kh", "h", "sh", "h", "h", "sh"]
    drums(track, 8, pattern, swing=0.22, gains={"k": 0.7, "s": 0.32, "h": 0.09})
    crackle(track, 0.0004, 0.15)
    return track.finish()


TRACKS = {
    "practice_room.wav": practice_room,
    "first_sub_20.wav": first_sub_20,
    "parity.wav": parity,
    "big_cube_energy.wav": big_cube_energy,
    "long_solve.wav": long_solve,
    "twelve_faces.wav": twelve_faces,
    "finals.wav": finals,
}


if __name__ == "__main__":
    # python3 tools/make_music.py              -> every track
    # python3 tools/make_music.py parity.wav   -> just that one
    import sys
    os.makedirs(OUT, exist_ok=True)
    for name in sys.argv[1:] or TRACKS:
        write(name, TRACKS[name]())
