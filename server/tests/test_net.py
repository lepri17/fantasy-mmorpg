"""The real thing over WebSocket: two clients log in, play and see each other."""

import asyncio
import json
import urllib.request

from websockets.asyncio.client import connect

from server.db import Database
from server.game import Game
from server.net import Server


async def _next(ws, kind: str, timeout: float = 3.0) -> dict:
    async def wait() -> dict:
        while True:
            message = json.loads(await ws.recv())
            if message.get("t") == kind:
                return message

    return await asyncio.wait_for(wait(), timeout)


async def _join(port: int, name: str):
    ws = await connect(f"ws://127.0.0.1:{port}")
    await ws.send(json.dumps({"t": "hello", "v": 1}))
    assert (await _next(ws, "hello"))["v"] == 1
    await ws.send(json.dumps({"t": "register", "user": name, "pass": "secret1"}))
    assert (await _next(ws, "auth"))["ok"]
    await ws.send(json.dumps({"t": "create", "slot": 1, "class": "warrior", "name": name + "Hero"}))
    await _next(ws, "chars")
    await ws.send(json.dumps({"t": "play", "slot": 1}))
    return ws, await _next(ws, "enter")


def test_two_clients_over_websocket():
    async def scenario() -> None:
        server = Server(Game(Database()), "127.0.0.1", 0)
        ready = asyncio.Event()
        task = asyncio.create_task(server.run(ready))
        await ready.wait()
        health = await asyncio.to_thread(
            lambda: urllib.request.urlopen(f"http://127.0.0.1:{server.port}/health", timeout=3).read()
        )
        assert health == b"OK\n"
        a, enter_a = await _join(server.port, "netone")
        b, enter_b = await _join(server.port, "nettwo")
        assert (await _next(a, "pjoin"))["p"]["name"] == "nettwoHero"
        await asyncio.sleep(0.25)
        await a.send(json.dumps({"t": "move", "x": enter_a["x"] + 25, "y": enter_a["y"], "f": "right", "a": "walk"}))
        while True:  # the first snapshots may still show where A arrived
            snap = await _next(b, "snap")
            if any(r[0] == enter_a["you"] and r[1] == enter_a["x"] + 25 for r in snap["p"]):
                break
        await a.send("not json")
        await a.send(json.dumps({"t": "ping", "c": 5}))
        assert (await _next(a, "pong"))["c"] == 5
        await a.close()
        assert (await _next(b, "pgone"))["id"] == enter_a["you"]
        await b.close()
        server.stop.set()
        await task

    asyncio.run(scenario())


def test_flooding_closes_the_connection():
    async def scenario() -> None:
        server = Server(Game(Database()), "127.0.0.1", 0)
        ready = asyncio.Event()
        task = asyncio.create_task(server.run(ready))
        await ready.wait()
        ws = await connect(f"ws://127.0.0.1:{server.port}")
        for _ in range(400):
            await ws.send(json.dumps({"t": "nonsense"}))
        try:
            await asyncio.wait_for(ws.wait_closed(), 3.0)
        finally:
            server.stop.set()
            await task
        assert ws.close_code == 1000

    asyncio.run(scenario())
