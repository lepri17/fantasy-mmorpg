"""Storage: accounts, login tokens, characters and guilds. SQLite by default
("sqlite:///server.db"); PostgreSQL with a "postgresql://..." URL (N13), which
needs the psycopg package. The same SQL runs on both."""

from __future__ import annotations

import datetime
import json
import sqlite3
import threading

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id {pk}, username TEXT NOT NULL, lower_name TEXT NOT NULL UNIQUE,
    salt TEXT NOT NULL, pass_hash TEXT NOT NULL, created TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL, expires {float} NOT NULL);
CREATE TABLE IF NOT EXISTS characters (
    id {pk}, account_id INTEGER NOT NULL, slot INTEGER NOT NULL,
    name TEXT NOT NULL, lower_name TEXT NOT NULL UNIQUE, class TEXT NOT NULL,
    level INTEGER NOT NULL DEFAULT 1, total_xp INTEGER NOT NULL DEFAULT 0,
    kills INTEGER NOT NULL DEFAULT 0, pvp_wins INTEGER NOT NULL DEFAULT 0,
    guild_id INTEGER, data TEXT NOT NULL, updated TEXT NOT NULL,
    UNIQUE (account_id, slot));
CREATE TABLE IF NOT EXISTS guilds (
    id {pk}, name TEXT NOT NULL, lower_name TEXT NOT NULL UNIQUE,
    leader_id INTEGER NOT NULL, created TEXT NOT NULL);
"""
CHARACTER_FIELDS = "id, account_id, slot, name, class, level, total_xp, kills, pvp_wins, guild_id, data"
TOP_ORDER = {
    "level": "level DESC, total_xp DESC",
    "kills": "kills DESC, level DESC",
    "pvp": "pvp_wins DESC, level DESC",
}


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


class Database:
    def __init__(self, url: str = "sqlite:///:memory:") -> None:
        self._lock = threading.Lock()
        if url.startswith(("postgres://", "postgresql://")):
            import psycopg
            from psycopg.rows import dict_row

            self.kind = "postgres"
            self._conn = psycopg.connect(url, autocommit=True, row_factory=dict_row)
            self._integrity = psycopg.IntegrityError
            types = {"pk": "BIGSERIAL PRIMARY KEY", "float": "DOUBLE PRECISION"}
        else:
            path = url.removeprefix("sqlite:///") if url.startswith("sqlite:///") else url
            self.kind = "sqlite"
            self._conn = sqlite3.connect(path, isolation_level=None, check_same_thread=False)
            self._conn.row_factory = sqlite3.Row
            if path != ":memory:":
                self._conn.execute("PRAGMA journal_mode=WAL")
            self._integrity = sqlite3.IntegrityError
            types = {"pk": "INTEGER PRIMARY KEY AUTOINCREMENT", "float": "REAL"}
        for statement in SCHEMA.format(**types).split(";"):
            if statement.strip():
                self._run(statement)

    def close(self) -> None:
        self._conn.close()

    # --- plumbing

    def _run(self, sql: str, params: tuple = ()):
        if self.kind == "postgres":
            sql = sql.replace("?", "%s")
        with self._lock:
            cursor = self._conn.execute(sql, params)
            rows = cursor.fetchall() if cursor.description else []
        return [dict(row) for row in rows]

    def _one(self, sql: str, params: tuple = ()) -> dict | None:
        rows = self._run(sql, params)
        return rows[0] if rows else None

    def _insert(self, sql: str, params: tuple) -> int | None:
        """INSERT ... RETURNING id; None when a UNIQUE rule stops it."""
        try:
            row = self._one(sql + " RETURNING id", params)
        except self._integrity:
            return None
        return int(row["id"]) if row else None

    # --- accounts and login tokens

    def create_account(self, username: str, salt: str, pass_hash: str) -> int | None:
        return self._insert(
            "INSERT INTO accounts (username, lower_name, salt, pass_hash, created) VALUES (?, ?, ?, ?, ?)",
            (username, username.lower(), salt, pass_hash, _now()),
        )

    def account_by_name(self, username: str) -> dict | None:
        return self._one("SELECT * FROM accounts WHERE lower_name = ?", (username.lower(),))

    def save_token(self, token_hash: str, account_id: int, expires: float) -> None:
        self._run(
            "INSERT INTO sessions (token_hash, account_id, expires) VALUES (?, ?, ?)",
            (token_hash, account_id, expires),
        )

    def account_for_token(self, token_hash: str, now: float) -> int | None:
        self._run("DELETE FROM sessions WHERE expires < ?", (now,))
        row = self._one("SELECT account_id FROM sessions WHERE token_hash = ?", (token_hash,))
        return int(row["account_id"]) if row else None

    def delete_token(self, token_hash: str) -> None:
        self._run("DELETE FROM sessions WHERE token_hash = ?", (token_hash,))

    def account_name(self, account_id: int) -> str:
        row = self._one("SELECT username FROM accounts WHERE id = ?", (account_id,))
        return row["username"] if row else ""

    # --- characters

    def characters(self, account_id: int) -> list[dict]:
        return self._run(
            f"SELECT {CHARACTER_FIELDS} FROM characters WHERE account_id = ? ORDER BY slot",
            (account_id,),
        )

    def character(self, char_id: int) -> dict | None:
        return self._one(f"SELECT {CHARACTER_FIELDS} FROM characters WHERE id = ?", (char_id,))

    def character_by_name(self, name: str) -> dict | None:
        return self._one(
            f"SELECT {CHARACTER_FIELDS} FROM characters WHERE lower_name = ?", (name.lower(),)
        )

    def create_character(
        self, account_id: int, slot: int, name: str, class_id: str, data: dict
    ) -> int | None:
        return self._insert(
            "INSERT INTO characters (account_id, slot, name, lower_name, class, level, data, updated)"
            " VALUES (?, ?, ?, ?, ?, 1, ?, ?)",
            (account_id, slot, name, name.lower(), class_id, json.dumps(data), _now()),
        )

    def delete_character(self, account_id: int, slot: int) -> int | None:
        row = self._one(
            "SELECT id FROM characters WHERE account_id = ? AND slot = ?", (account_id, slot)
        )
        if row is None:
            return None
        self._run("DELETE FROM characters WHERE id = ?", (row["id"],))
        return int(row["id"])

    def save_character(
        self, char_id: int, level: int, total_xp: int, kills: int, pvp_wins: int, data: dict
    ) -> None:
        self._run(
            "UPDATE characters SET level = ?, total_xp = ?, kills = ?, pvp_wins = ?, data = ?,"
            " updated = ? WHERE id = ?",
            (level, total_xp, kills, pvp_wins, json.dumps(data), _now(), char_id),
        )

    def top(self, by: str, limit: int = 20) -> list[dict]:
        order = TOP_ORDER.get(by, TOP_ORDER["level"])
        return self._run(
            f"SELECT name, class, level, total_xp, kills, pvp_wins FROM characters"
            f" ORDER BY {order}, id LIMIT ?",
            (limit,),
        )

    # --- guilds

    def create_guild(self, name: str, leader_id: int) -> int | None:
        return self._insert(
            "INSERT INTO guilds (name, lower_name, leader_id, created) VALUES (?, ?, ?, ?)",
            (name, name.lower(), leader_id, _now()),
        )

    def guild(self, guild_id: int) -> dict | None:
        return self._one("SELECT * FROM guilds WHERE id = ?", (guild_id,))

    def guild_members(self, guild_id: int) -> list[dict]:
        return self._run(
            "SELECT id, name, class, level FROM characters WHERE guild_id = ? ORDER BY level DESC, id",
            (guild_id,),
        )

    def set_guild(self, char_id: int, guild_id: int | None) -> None:
        self._run("UPDATE characters SET guild_id = ? WHERE id = ?", (guild_id, char_id))

    def set_guild_leader(self, guild_id: int, leader_id: int) -> None:
        self._run("UPDATE guilds SET leader_id = ? WHERE id = ?", (leader_id, guild_id))

    def delete_guild(self, guild_id: int) -> None:
        self._run("UPDATE characters SET guild_id = NULL WHERE guild_id = ?", (guild_id,))
        self._run("DELETE FROM guilds WHERE id = ?", (guild_id,))
