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
