"""Runs the server: python -m server [--port 8765] [--db sqlite:///server.db].
Settings can also come from the environment: PORT (or MMO_PORT), MMO_HOST,
DATABASE_URL and MMO_CHANNELS. Stop it with Ctrl+C; everyone is saved."""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal

from .db import Database
from .game import Game
from .net import Server


def main() -> None:
    parser = argparse.ArgumentParser(description="Fantasy MMORPG server")
    parser.add_argument("--host", default=os.environ.get("MMO_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", os.environ.get("MMO_PORT", 8765))))
    parser.add_argument("--db", default=os.environ.get("DATABASE_URL", "sqlite:///server.db"))
    parser.add_argument("--channels", type=int, default=int(os.environ.get("MMO_CHANNELS", 3)))
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    server = Server(Game(Database(args.db), channels=args.channels), args.host, args.port)

    async def run() -> None:
        loop = asyncio.get_running_loop()
        for name in ("SIGINT", "SIGTERM"):
            if hasattr(signal, name):
                try:
                    loop.add_signal_handler(getattr(signal, name), server.stop.set)
                except NotImplementedError:  # Windows
                    pass
        await server.run()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
