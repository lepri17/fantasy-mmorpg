"""Shared test setup. Set TEST_DATABASE_URL (postgresql://...) to run the
database tests on PostgreSQL too."""

import os

import pytest

os.environ.setdefault("MMO_SCRYPT_N", "16")  # fast password hashing in tests

from server.db import Database  # noqa: E402

DATABASES = ["sqlite:///:memory:"]
if os.environ.get("TEST_DATABASE_URL"):
    DATABASES.append(os.environ["TEST_DATABASE_URL"])


def _clean(db: Database) -> None:
    if db.kind == "postgres":
        for name in ("sessions", "characters", "guilds", "accounts"):
            db._run(f"DELETE FROM {name}")


@pytest.fixture(params=DATABASES, ids=lambda url: url.split(":")[0])
def db(request):
    database = Database(request.param)
    _clean(database)
    yield database
    _clean(database)
    database.close()
