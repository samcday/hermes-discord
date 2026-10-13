"""Run with Hermes' managed Python in the guest; no account credentials needed.

Downloads Whisper base if uncached. Sends only this fixed test sentence to
Microsoft Edge TTS. Exercises actual audio synthesis and local transcription,
not Discord transport or model inference.
"""

import asyncio
import os
import platform
import tempfile
from pathlib import Path

import discord
import edge_tts
from faster_whisper import WhisperModel

assert os.geteuid() != 0, "Run the check as the agent, not root."
# The provider SDK reads this too. A private host umask must not make generated
# image metadata root-only, even when audio libraries happen not to read it.
assert platform.freedesktop_os_release()["ID"] == "fedora"

discord.opus.load_opus("libopus.so.0")
assert discord.opus.is_loaded()

with tempfile.TemporaryDirectory() as directory:
    audio = Path(directory) / "speech.mp3"
    asyncio.run(
        edge_tts.Communicate(
            "The voice agent is running inside its own virtual machine.",
            "en-US-AriaNeural",
        ).save(str(audio))
    )
    model = WhisperModel("base", device="cpu", compute_type="int8")
    segments, _ = model.transcribe(str(audio), language="en")
    text = " ".join(segment.text.strip() for segment in segments)
    assert "virtual machine" in text.lower(), text
    print(f"Opus, Edge TTS and local Whisper passed: {text}")
