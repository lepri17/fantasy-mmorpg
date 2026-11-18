"""The WebSocket side: one Session per connection, JSON messages in and out,
a rate limit (N12), and the 10-per-second tick of the game. GET /health
answers "OK" for cloud hosts that check the server is up (N13)."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from http import HTTPStatus

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

TICK = 0.1
MAX_MESSAGE = 8192
QUEUE_LIMIT = 600  # messages waiting for a slow client before it is dropped
RATE = 40.0  # messages per second, with bursts up to BURST
BURST = 80.0
STRIKES = 40  # bad or flooding messages before the connection is closed

log = logging.getLogger("mmo")


class Session:
    def __init__(self, ws, ip: str) -> None:
        self.ws = ws
        self.ip = ip
        self.account_id = None
        self.username = ""
        self.token = None
        self.hero = None
        self.closed = False
        self.reason = ""
        self.queue: asyncio.Queue = asyncio.Queue()
        self._tokens = BURST
        self._refill = time.monotonic()
        self.strikes = 0

    def send(self, message: dict) -> None:
        if self.closed:
            return
        if self.queue.qsize() > QUEUE_LIMIT:
            self.close("too slow")
            return
        self.queue.put_nowait(json.dumps(message, separators=(",", ":"), ensure_ascii=False))

    def close(self, reason: str) -> None:
        if not self.closed:
            self.closed = True
            self.reason = reason
            self.queue.put_nowait(None)
            log.info("closing %s (%s): %s", self.username or "?", self.ip, reason)

    def strike(self, reason: str) -> None:
        self.strikes += 1
        log.debug("strike %s: %s", self.username or self.ip, reason)
        if self.strikes > STRIKES:
            self.close("too many bad messages")

    def allow(self) -> bool:
        now = time.monotonic()
        self._tokens = min(BURST, self._tokens + (now - self._refill) * RATE)
        self._refill = now
        if self._tokens < 1.0:
            return False
        self._tokens -= 1.0
        return True


class Server:
    def __init__(self, game, host: str = "0.0.0.0", port: int = 8765) -> None:
        self.game = game
        self.host = host
        self.port = port
        self.stop = asyncio.Event()

    async def handler(self, ws) -> None:
        address = ws.remote_address[0] if ws.remote_address else "?"
        session = Session(ws, str(address))
        writer = asyncio.create_task(self._writer(session))
        try:
            async for raw in ws:
                if session.closed:
                    continue  # keep reading until the close handshake is through
                if not isinstance(raw, str) or len(raw) > MAX_MESSAGE:
                    session.strike("too big")
                    continue
                if not session.allow():
                    session.strike("flood")
                    continue
                try:
                    message = json.loads(raw)
                except ValueError:
                    session.strike("not JSON")
                    continue
                self.game.handle(session, message)
        except ConnectionClosed:
            pass
        finally:
            session.closed = True
            self.game.disconnected(session)
            if not writer.done():
                session.queue.put_nowait(None)
            await asyncio.gather(writer, return_exceptions=True)

    @staticmethod
    async def _writer(session: Session) -> None:
        try:
            while True:
                text = await session.queue.get()
                if text is None:
                    await session.ws.close(1000, session.reason[:100])
                    return
                await session.ws.send(text)
        except ConnectionClosed:
            pass

    @staticmethod
    def _http(connection, request):
        if request.path == "/health":
            return connection.respond(HTTPStatus.OK, "OK\n")
        return None

    async def _ticker(self) -> None:
        loop = asyncio.get_running_loop()
        next_time = loop.time()
        while True:
            next_time += TICK
            try:
                self.game.tick(TICK)
            except Exception:  # one bad tick must not stop the world
                log.exception("tick failed")
            await asyncio.sleep(max(0.0, next_time - loop.time()))

    async def run(self, ready: asyncio.Event | None = None) -> None:
        async with serve(
            self.handler, self.host, self.port, max_size=MAX_MESSAGE * 2,
            ping_interval=20, ping_timeout=30, close_timeout=3, process_request=self._http,
        ) as server:
            self.port = server.sockets[0].getsockname()[1]
            log.info("listening on %s:%d", self.host, self.port)
            ticker = asyncio.create_task(self._ticker())
            if ready is not None:
                ready.set()
            try:
                await self.stop.wait()
            finally:
                ticker.cancel()
                self.game.shutdown()
                log.info("stopped; everyone saved")
