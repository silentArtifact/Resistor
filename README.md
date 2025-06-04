This self‑hosted web application helps individuals reinforce good habits by logging each moment they *resist* or *slip* into temptation. It offers instant positive feedback while collecting data for long‑term insight.

# Overview

Resistor is a single‑user Docker container (arm/v7, arm64, amd64) that runs a Python + FastAPI backend with a React (Vite) frontend and an embedded SQLite database. All data lives locally by default; optional end‑to‑end‑encrypted cloud sync keeps multiple devices in step.

# Features

* Define unlimited habits/temptations with custom names and colours.
* One‑tap **Resist** and **Slip** buttons on a mobile‑friendly home screen.
* Automatic timestamp and exact GPS capture (with user consent).
* Analytics dashboard:

  * Daily and weekly success counts, longest streak, overall success rate.
  * Hour‑of‑day and day‑of‑week heat maps.
  * Location clusters on an OpenStreetMap tile overlay.
* Soft‑wipe *Delete My Data* option: clears rows but retains schema and settings.
* Embedded SQLite storage; optional AES‑encrypted export/import (JSON).
* Cloud sync integrations (device‑code flow or WebDAV as noted below).
* Health‑check endpoint and semantic Docker tags compatible with Watchtower.
* MIT‑licensed open source.

# Architecture

* FastAPI serves a REST/JSON API and the React SPA.
* SQLModel ORM on top of SQLite.
* Background scheduler (APScheduler) handles sync and housekeeping.
* Frontend uses React Query for network state and Recharts for graphs.

# Quick Start (Docker)

```sh
docker run -d \
  --name resistor \
  -p 8080:8080 \
  -e TZ=America/Chicago \
  -e RESISTOR_DATA=/data \
  -v /path/on/host:/data \
ghcr.io/yourname/resistor:latest
```

## Building the container

To build the image yourself, run from the repository root:

```sh
docker build -t resistor .
```

Then start the container:

```sh
docker run -d \
  --name resistor \
  -p 8080:8080 \
  resistor
```

The container detects architecture and selects the correct image variant.

# Configuration

Set environment variables (or a `.env` file):

* `TZ` – IANA timezone string.
* `RESISTOR_DATA` – path to mounted writable folder.
* `RESISTOR_EXPORT_PASSPHRASE` – optional default passphrase for exports.
* `ONEDRIVE_CLIENT_ID` / `ICLOUD_APP_PASSWORD` / `DROPBOX_TOKEN` / `GDRIVE_CLIENT_ID` – provide any of these to enable cloud sync.

# Usage

## Adding a habit

Navigate to Settings → Habits → Add Habit. Give it a name and choose a colour.

## Logging events

From the home screen, tap the habit and press Resist or Slip. If the browser grants location permission, GPS coordinates are stored.

## Viewing analytics

Open the Analytics tab to see charts and maps. Hover/tap data points for details.

# Data Privacy and Deletion

Select Settings → Delete My Data. Confirming this action wipes all event rows and location data while keeping your habit list and sync credentials. The UI reloads to an empty state.

# Backup and Cloud Sync

Resistor can push and pull an encrypted zip of the database:

* OneDrive (Microsoft Graph device‑code OAuth)
* iCloud Drive (WebDAV with app‑specific password)
* Dropbox
* Google Drive
  Sync runs every hour; you can also trigger a manual sync.

# Export and Import

Go to Settings → Export to download an encrypted or plain JSON archive. Use Import to restore or merge data.

# Development

```sh
git clone https://github.com/yourname/resistor
cd resistor
./dev.sh  # starts backend and frontend hot‑reload servers
```

See `CONTRIBUTING.md` for coding standards and branch workflow.

# Roadmap

* Multi‑user mode with OAuth sign‑in.
* Push notification reminders.
* CSV export option.
* Plugin hook system.

# License

Resistor is released under the MIT License. See `LICENSE` for full text.
