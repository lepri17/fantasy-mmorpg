"""Passwords, login tokens and the rules for account, hero and guild names."""

from __future__ import annotations

import hashlib
import hmac
import os
import re
import secrets

# scrypt cost; tests lower it with MMO_SCRYPT_N to run fast.
SCRYPT_N = int(os.environ.get("MMO_SCRYPT_N", 2**14))
USERNAME = re.compile(r"^[A-Za-z0-9_]{3,16}$")
# Hero and guild names: letters of any alphabet (Hebrew too), digits and _.
HERO_NAME = re.compile(r"^[^\W]{2,16}$", re.UNICODE)
GUILD_NAME = re.compile(r"^[^\W][\w ]{1,14}[^\W]$", re.UNICODE)
MIN_PASSWORD = 6
MAX_PASSWORD = 64


def hash_password(password: str, salt: bytes | None = None) -> tuple[str, str]:
    """(salt, hash) as hex, with scrypt."""
    salt = salt if salt is not None else os.urandom(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=SCRYPT_N, r=8, p=1, dklen=32)
    return salt.hex(), digest.hex()


def check_password(password: str, salt_hex: str, hash_hex: str) -> bool:
    _, digest = hash_password(password, bytes.fromhex(salt_hex))
    return hmac.compare_digest(digest, hash_hex)


def new_token() -> str:
    return secrets.token_urlsafe(32)


def token_hash(token: str) -> str:
    """Tokens are kept hashed, so a copy of the database cannot log anyone in."""
    return hashlib.sha256(token.encode()).hexdigest()


def username_problem(name) -> str:
    if not isinstance(name, str) or not USERNAME.match(name):
        return "Use 3-16 letters, digits or _ for the name."
    return ""


def password_problem(password) -> str:
    if not isinstance(password, str) or not MIN_PASSWORD <= len(password) <= MAX_PASSWORD:
        return f"The password needs {MIN_PASSWORD} to {MAX_PASSWORD} characters."
    return ""


def hero_name_problem(name) -> str:
    if not isinstance(name, str) or not HERO_NAME.match(name) or name.isdigit():
        return "A hero name needs 2-16 letters or digits, with no spaces."
    return ""


def guild_name_problem(name) -> str:
    if not isinstance(name, str) or not GUILD_NAME.match(name) or "  " in name:
        return "A guild name needs 3-16 letters, digits or spaces."
    return ""
