This project is a small habit tracking prototype. It exposes a minimal API built with FastAPI and ships with a placeholder React frontend.

# Overview

The backend uses SQLite through SQLModel and the frontend is bootstrapped with Vite. Both are intended to run inside Docker but can also be launched directly for development.

# API Endpoints

* `POST /habits` – create a habit with a name, optional description, colour, icon and position.
* `GET /habits` – list all active habits. Pass `include_archived=true` to include archived ones.
* `PATCH /habits/{id}` – update a habit's details (name, colour, position, etc.) or archive it.
* `DELETE /habits/{id}` – remove a habit and its events.
* `POST /events` – log a success or slip against a habit.
* `GET /events` – list all logged events.

# Frontend

The React app lets you manage habits and quickly log events. A dropdown at the top acts as a quick switcher for the active habit, and Resist/Slip buttons record successes or failures. After logging you are prompted for an optional note and see a brief alert as feedback.

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

## Planned Use Cases
### Habit Definition & Configuration

* As a user, I can create a new habit with a name, description, and color/icon so I can quickly tell habits apart.
* As a user, I can edit or delete an existing habit when my goals change.
* As a user, I can archive a habit (retain historic data but hide it from the main UI).
* As a user, I can reorder habits to keep my most-used habits at the top of the quick switcher.
* As a user, I can set a personal goal (e.g., max 2 temptations per week) for each habit to gauge progress.

### Quick Interaction (In-the-Moment Logging)

* As a user, I can press a large Resist button to log that I successfully resisted a temptation.
* As a user, I can tap a Slip button to record a failure.
* As a user, I can switch habits in one gesture (swipe, dropdown, or keyboard cycle) to avoid friction.
* As a user, I get an immediate visual reward (animation, haptic, sound) after logging a resistance.
* As a user, I can add an optional note after Resist or Slip to capture context (e.g., mood, trigger).

### Context Capture

* As a user, the app automatically records timestamp and exact GPS location (when I grant permission) with each log entry.
* As a user, I can later view the raw location on a map or see it bucketed by city/region.
* As a user, I can disable GPS capture at any time; future entries won’t store location data.

### Analytics & Insights

* As a user, I can view daily, weekly, and monthly counts of Resist and Slip events per habit.
* As a user, I can see rolling streaks of consecutive days without a Slip.
* As a user, I can review success-rate percentages (Resist ÷ total events) for any date range.
* As a user, I can see heat-maps by hour-of-day and day-of-week to spot vulnerable times.
* As a user, I can see a map cluster view highlighting locations with frequent temptations.
* As a user, I can filter analytics by custom date range or by location tag.

### Data Export & Import

* As a user, I can export all data as JSON, optionally encrypted with a passphrase I choose.
* As a user, I can import a previously exported file to restore my data on a new install.
* As a user, I receive clear feedback if an import fails due to wrong passphrase or version mismatch.

### Cloud Sync & Backup

* As a user, I can link my account to OneDrive, iCloud Drive, Dropbox, or Google Drive via OAuth/device-code.
* As a user, the app uploads a compressed, encrypted snapshot after each new log or once per hour (whichever is first).
* As a user, I can trigger a manual sync and see last-sync status and any errors.
* As a user, I can disconnect a cloud provider and purge remote backups.

### Data Deletion & Privacy

* As a user, I can press Delete My Data to clear all log entries while preserving my habit definitions and settings (Option B soft wipe).
* As a user, I must confirm twice before deletion to prevent accidents.
* As a user, after deletion the dashboard reloads showing a fresh, empty state.
* As a user, I can request deletion of remote backups as part of the same flow.

### Deployment & Maintenance

* As an operator, I can pull the Docker image for my platform (amd64 or arm/v7) and run it with a single command.
* As an operator, I can bind-mount a host directory to persist the SQLite database.
* As an operator, I can update the container via Watchtower and retain my data.
* As an operator, I can check a /healthz endpoint for uptime monitoring.
* As an operator, I can set environment variables (e.g., TZ, BACKUP\_INTERVAL) to tweak behavior.

### Settings & Personalization

* As a user, I can switch between light and dark themes.
* As a user, I can choose metric or imperial distance units for location displays.
* As a user, I can change the default chart time frame (e.g., show week view first).
* As a user, I can choose whether the app plays sounds or animations after a log.

### Accessibility

* As a user, I can navigate all primary actions with keyboard only.
* As a user, I can use screen-reader-friendly controls and get descriptive labels for charts.
* As a user, I can enable a high-contrast mode for better visibility.

### Error Handling & Edge Cases

* As a user, if GPS permission is denied, the app gracefully logs entries without location and reminds me how to enable it.
* As a user, if the device is offline, logs queue locally and sync once connectivity returns.
* As a user, if the database becomes corrupted, the app offers a guided restore from the latest cloud backup.
* As an operator, I receive structured JSON logs for troubleshooting (e.g., sync failures).

These use cases should cover the functional surface area needed to validate and prioritize features while developing the application. Let me know if you notice gaps or want deeper detail on any scenario.

# License

Resistor is released under the MIT License. See `LICENSE` for full text.
