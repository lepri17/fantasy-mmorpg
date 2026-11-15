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
    print("Sounds written to", AUDIO)


if __name__ == "__main__":
    main()
