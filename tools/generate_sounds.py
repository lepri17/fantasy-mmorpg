"""Synthesizes the prototype sound effects as small WAV files.

Everything is generated from math, so the sounds are original and fully owned.
Output: client/assets/audio/*.wav (22050 Hz, mono, 16-bit).

Run:  python tools/generate_sounds.py     (standard library only)
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

AUDIO = Path(__file__).resolve().parent.parent / "client" / "assets" / "audio"
RATE = 22050
VOLUME = 0.45


def tone(start_hz: float, end_hz: float, seconds: float, shape: str = "sine") -> list[float]:
    """A tone that slides from start_hz to end_hz and fades out."""
    samples, phase = [], 0.0
    count = int(RATE * seconds)
    for i in range(count):
        progress = i / count
        phase += 2 * math.pi * (start_hz + (end_hz - start_hz) * progress) / RATE
        value = math.sin(phase)
        if shape == "square":
            value = 0.6 if value > 0 else -0.6
        samples.append(value * (1.0 - progress) ** 1.5)
    return samples


def noise(seconds: float, smooth: float, rng: random.Random) -> list[float]:
    """Soft noise burst that swells and fades: a 'whoosh'."""
    samples, last = [], 0.0
    count = int(RATE * seconds)
    for i in range(count):
        progress = i / count
        last += (rng.uniform(-1, 1) - last) * smooth
        samples.append(last * math.sin(math.pi * progress) * 2.0)
    return samples


def mix(*layers: list[float]) -> list[float]:
    length = max(len(layer) for layer in layers)
    return [sum(layer[i] for layer in layers if i < len(layer)) for i in range(length)]


def sequence(*parts: list[float]) -> list[float]:
    return [sample for part in parts for sample in part]


def save(name: str, samples: list[float]) -> None:
    peak = max(1e-6, max(abs(s) for s in samples))
    frames = b"".join(struct.pack("<h", int(s / peak * VOLUME * 32767)) for s in samples)
    with wave.open(str(AUDIO / f"{name}.wav"), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(frames)


# ---------------------------------------------------------------- music
# Short original loops, one per map (maps.json "music"). Notes are MIDI
# numbers (60 = middle C) with a length in beats; None is a rest.


def _wave(phase: float, shape: str) -> float:
    if shape == "triangle":
        return 2.0 / math.pi * math.asin(math.sin(phase))
    if shape == "soft_square":
        return math.tanh(3.0 * math.sin(phase)) * 0.6
    return math.sin(phase)


def voice(notes, beat: float, shape: str = "sine", volume: float = 1.0) -> list[float]:
    """One line of notes with a quick attack and a soft release."""
    out: list[float] = []
    for midi, beats in notes:
        count = int(RATE * beats * beat)
        if midi is None:
            out += [0.0] * count
            continue
        hz = 440.0 * 2 ** ((midi - 69) / 12)
        phase = 0.0
        for i in range(count):
            phase += 2 * math.pi * hz / RATE
            envelope = min(1.0, i / (RATE * 0.012)) * max(0.0, 1.0 - i / count) ** 0.7
            out.append(_wave(phase, shape) * envelope * volume)
    return out


def chirps(seconds: float, rng: random.Random, every: float) -> list[float]:
    """A bird now and then: short high tones sliding up."""
    out = [0.0] * int(RATE * seconds)
    t = rng.uniform(0.5, every)
    while t < seconds - 0.3:
        start = int(t * RATE)
        for k in range(rng.randint(2, 3)):
            call = tone(2100 + rng.uniform(-200, 300), 2700, 0.07)
            at = start + int(k * 0.11 * RATE)
            for i, value in enumerate(call):
                if at + i < len(out):
                    out[at + i] += value * 0.25
        t += rng.uniform(every * 0.6, every * 1.4)
    return out


def drips(seconds: float, rng: random.Random, every: float) -> list[float]:
    """Water dripping in a cellar."""
    out = [0.0] * int(RATE * seconds)
    t = rng.uniform(0.3, every)
    while t < seconds - 0.2:
        drop = tone(1500, 800, 0.09)
        at = int(t * RATE)
        for i, value in enumerate(drop):
            if at + i < len(out):
                out[at + i] += value * 0.3
        t += rng.uniform(every * 0.5, every * 1.5)
    return out


def wind(seconds: float, rng: random.Random) -> list[float]:
    """Very soft, slowly changing wind."""
    samples, last = [], 0.0
    count = int(RATE * seconds)
    for i in range(count):
        last += (rng.uniform(-1, 1) - last) * 0.01
        swell = 0.5 + 0.5 * math.sin(2 * math.pi * i / count * 2)
        samples.append(last * 0.6 * swell)
    return samples


def bars(*chords) -> list:
    """Bass notes: each chord root held for 4 beats."""
    return [(root, 4) for root in chords]


def build_music(rng: random.Random) -> dict[str, list[float]]:
    tracks = {}
    beat = 60 / 96
    melody = [(72, 1), (76, 1), (79, 1), (76, 1), (77, 1), (81, 1), (79, 2),
              (76, 1), (74, 1), (72, 1), (74, 1), (76, 2), (None, 2),
              (72, 1), (76, 1), (79, 1), (81, 1), (79, 1), (77, 1), (76, 2),
              (74, 1), (76, 1), (74, 1), (71, 1), (72, 2), (None, 2)]
    bass = bars(48, 45, 41, 43, 48, 45, 41, 43)
    tracks["music_town"] = mix(voice(melody, beat, "triangle", 0.55), voice(bass, beat, "sine", 0.5))
    beat = 60 / 112
    melody = [(67, 0.5), (71, 0.5), (74, 0.5), (71, 0.5), (72, 1), (74, 1),
              (76, 0.5), (74, 0.5), (72, 0.5), (71, 0.5), (69, 1), (None, 1),
              (67, 0.5), (69, 0.5), (71, 0.5), (74, 0.5), (79, 1), (76, 1),
              (74, 0.5), (72, 0.5), (71, 0.5), (69, 0.5), (67, 1), (None, 1)] * 2
    bass = bars(43, 48, 43, 50, 43, 48, 50, 43)
    tracks["music_field"] = mix(
        voice(melody, beat, "soft_square", 0.32), voice(bass, beat, "triangle", 0.45)
    )
    beat = 60 / 80
    melody = [(69, 2), (72, 1), (71, 1), (69, 3), (None, 1), (64, 2), (67, 1), (65, 1), (64, 4),
              (69, 2), (72, 1), (76, 1), (74, 3), (None, 1), (72, 2), (71, 2), (69, 4)]
    bass = bars(45, 41, 43, 40, 45, 41, 43, 45)
    seconds = 32 * beat
    tracks["music_forest"] = mix(
        voice(melody, beat, "sine", 0.45), voice(bass, beat, "triangle", 0.35),
        wind(seconds, rng), chirps(seconds, rng, 3.5),
    )
    beat = 60 / 70
    arpeggio = [(62, 1), (65, 1), (69, 1), (65, 1), (61, 1), (64, 1), (69, 1), (64, 1)] * 3
    drone = [(38, 24)]
    seconds = 24 * beat
    tracks["music_cellar"] = mix(
        voice(arpeggio, beat, "triangle", 0.3), voice(drone, beat, "sine", 0.55),
        voice([(45, 24)], beat, "sine", 0.25), drips(seconds, rng, 2.5),
    )
    return tracks


def main() -> None:
    AUDIO.mkdir(parents=True, exist_ok=True)
    rng = random.Random(3)
    save("swing", noise(0.16, 0.35, rng))
    save("hit", mix(tone(190, 70, 0.14), noise(0.05, 0.8, rng)))
    save("hurt", tone(240, 110, 0.22, "square"))
    save("coin", sequence(tone(988, 988, 0.07), tone(1319, 1319, 0.14)))
    save("potion", tone(380, 920, 0.28))
    save("skill", mix(noise(0.38, 0.2, rng), tone(140, 320, 0.38)))
    save("levelup", sequence(*(tone(hz, hz, 0.11) for hz in (523, 659, 784)), tone(1047, 1047, 0.3)))
    save("defeat", sequence(tone(392, 370, 0.18), tone(311, 294, 0.18), tone(233, 196, 0.4)))
    for name, samples in build_music(random.Random(11)).items():
        save(name, samples)
    print("Sounds written to", AUDIO)


if __name__ == "__main__":
    main()
