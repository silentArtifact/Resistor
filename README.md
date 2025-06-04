This project is a small habit tracking prototype. It exposes a minimal API built with FastAPI and ships with a placeholder React frontend.

# Overview

The backend uses SQLite through SQLModel and the frontend is bootstrapped with Vite. Both are intended to run inside Docker but can also be launched directly for development.

# API Endpoints

* `POST /habits` – create a habit with a name and optional colour.
* `GET /habits` – list all habits.
* `POST /events` – log a success or slip against a habit.
* `GET /events` – list all logged events.

# Frontend

The React app currently renders only a heading that says "Resistor". It is included so the backend can serve a basic SPA bundle.

# Quick Start (Development)

```sh
./dev.sh
```

This script starts both the FastAPI server on port 8080 and the Vite dev server for the React app.

## Docker

To build and run the production container:

```sh
docker build -t resistor .
docker run -p 8080:8080 resistor
```

The image installs the Python requirements, installs the Node packages to build
the frontend and finally launches the API with `uvicorn`.

# Roadmap

The following planned features are not yet implemented:

* Mobile UI with Resist/Slip buttons and GPS capture.
* Analytics dashboard with charts and maps.
* Data deletion and import/export helpers.
* Cloud synchronization options.
* Health-check endpoint and Docker automation.

# License

Resistor is released under the MIT License. See `LICENSE` for full text.
