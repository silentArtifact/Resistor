import base64
import json
import os
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.fernet import Fernet

ITERATIONS = 390000
SALT_SIZE = 16


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=ITERATIONS,
    )
    return kdf.derive(passphrase.encode())


def encrypt_json(data: dict, passphrase: str) -> str:
    salt = os.urandom(SALT_SIZE)
    key = _derive_key(passphrase, salt)
    f = Fernet(base64.urlsafe_b64encode(key))
    token = f.encrypt(json.dumps(data).encode())
    return base64.b64encode(salt + token).decode()


def decrypt_json(token: str, passphrase: str) -> dict:
    raw = base64.b64decode(token)
    salt, encrypted = raw[:SALT_SIZE], raw[SALT_SIZE:]
    key = _derive_key(passphrase, salt)
    f = Fernet(base64.urlsafe_b64encode(key))
    data = f.decrypt(encrypted)
    return json.loads(data.decode())
