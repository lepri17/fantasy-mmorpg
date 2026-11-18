"""Accounts, tokens, characters, guilds and the leaderboard in the database."""

from server import accounts


def test_accounts_and_tokens(db):
    salt, digest = accounts.hash_password("secret1")
    first = db.create_account("Mor_1", salt, digest)
    assert first is not None
    assert db.create_account("mor_1", salt, digest) is None  # names ignore case
    row = db.account_by_name("MOR_1")
    assert row["id"] == first and accounts.check_password("secret1", row["salt"], row["pass_hash"])
    assert not accounts.check_password("wrong!", row["salt"], row["pass_hash"])
    token = accounts.new_token()
    db.save_token(accounts.token_hash(token), first, 100.0)
    assert db.account_for_token(accounts.token_hash(token), 50.0) == first
    assert db.account_for_token(accounts.token_hash(token), 150.0) is None  # expired


def test_characters_slots_and_names(db):
    owner = db.create_account("owner", "aa", "bb")
    other = db.create_account("other", "aa", "bb")
    hero = db.create_character(owner, 1, "Doran", "warrior", {"level": 1})
    assert hero is not None
    assert db.create_character(owner, 1, "Elin", "archer", {}) is None  # slot taken
    assert db.create_character(other, 1, "doran", "archer", {}) is None  # name taken
    assert db.create_character(other, 1, "דורון", "archer", {}) is not None
    db.save_character(hero, 7, 900, 40, 2, {"level": 7})
    saved = db.character_by_name("DORAN")
    assert saved["level"] == 7 and saved["kills"] == 40 and '"level": 7' in saved["data"]
    assert [c["name"] for c in db.characters(owner)] == ["Doran"]
    assert db.delete_character(owner, 1) == hero and db.characters(owner) == []
    assert db.delete_character(owner, 1) is None


def test_leaderboard_and_guilds(db):
    owner = db.create_account("owner", "aa", "bb")
    ids = [db.create_character(owner, slot, f"Hero{slot}", "warrior", {}) for slot in (1, 2, 3)]
    for char_id, level, kills in zip(ids, (3, 9, 5), (50, 10, 99), strict=True):
        db.save_character(char_id, level, level * 100, kills, 0, {})
    assert [r["name"] for r in db.top("level")] == ["Hero2", "Hero3", "Hero1"]
    assert db.top("kills", 1)[0]["name"] == "Hero3"
    guild = db.create_guild("Moon Wolves", ids[0])
    assert guild is not None and db.create_guild("moon wolves", ids[1]) is None
    db.set_guild(ids[0], guild)
    db.set_guild(ids[1], guild)
    assert [m["name"] for m in db.guild_members(guild)] == ["Hero2", "Hero1"]
    db.delete_guild(guild)
    assert db.guild(guild) is None and db.character(ids[0])["guild_id"] is None


def test_name_rules():
    assert accounts.username_problem("ab") and not accounts.username_problem("abc_12")
    assert accounts.password_problem("12345") and not accounts.password_problem("123456")
    assert not accounts.hero_name_problem("גיבור") and accounts.hero_name_problem("two words")
    assert accounts.hero_name_problem("12345")
    assert not accounts.guild_name_problem("Moon Wolves") and accounts.guild_name_problem("x")
