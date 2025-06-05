# Resistor Backend

This directory contains the FastAPI application. Install requirements and run the development server:

```sh
pip install -r requirements.txt
uvicorn resistor.main:app --reload --port 8080
```

The requirements file pins `httpx` below 0.27 to avoid compatibility issues.

## Endpoints

* `PATCH /habits/{id}` – update an existing habit.
* `DELETE /habits/{id}` – delete a habit and associated events.
* `GET /export` – return all habits and events in a single JSON payload.
* `POST /import` – restore habits and events from an exported JSON payload.

### Encryption Format

Both endpoints accept an optional `passphrase` query parameter. When provided to
`/export`, the JSON payload is encrypted and returned as `{ "encrypted":
"<base64>" }`. The value is a base64 string containing a 16 byte salt followed
by a Fernet token. The salt and passphrase are used with PBKDF2-HMAC-SHA256
(390k iterations) to derive a 32 byte key for symmetric encryption. To import an
encrypted export, POST the object back to `/import` with the same passphrase.
