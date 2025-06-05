# Resistor Backend

This directory contains the FastAPI application. Install requirements and run the development server:

```sh
pip install -r requirements.txt
uvicorn resistor.main:app --reload --port 8080
```

The requirements file pins `httpx` below 0.27 to avoid compatibility issues.

## Endpoints

* `GET /export` – return all habits and events in a single JSON payload.
