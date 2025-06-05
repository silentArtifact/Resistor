from fastapi.testclient import TestClient
from resistor.main import app
from resistor.database import init_db

client = TestClient(app)


def test_healthz():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_and_list_habit():
    init_db()
    response = client.post("/habits", json={"name": "Test"})
    assert response.status_code == 200
    habit_id = response.json()["id"]

    response = client.get("/habits")
    assert response.status_code == 200
    assert any(h["id"] == habit_id for h in response.json())


def test_create_event_and_list_events():
    init_db()
    habit = client.post("/habits", json={"name": "Event Habit"}).json()
    event_response = client.post(
        "/events",
        json={
            "habit_id": habit["id"],
            "success": True,
            "latitude": 1.0,
            "longitude": 2.0,
        },
    )
    assert event_response.status_code == 200
    event_id = event_response.json()["id"]

    response = client.get("/events")
    assert response.status_code == 200
    event = next(e for e in response.json() if e["id"] == event_id)
    assert event["latitude"] == 1.0
    assert event["longitude"] == 2.0


def test_create_event_invalid_habit():
    init_db()
    response = client.post(
        "/events", json={"habit_id": 999999, "success": True}
    )
    assert response.status_code == 404


def test_export_data():
    init_db()
    habit_resp = client.post("/habits", json={"name": "Export Habit"})
    habit_id = habit_resp.json()["id"]
    event_resp = client.post(
        "/events",
        json={"habit_id": habit_id, "success": False},
    )
    event_id = event_resp.json()["id"]

    response = client.get("/export")
    assert response.status_code == 200
    data = response.json()
    assert any(h["id"] == habit_id for h in data["habits"])
    assert any(e["id"] == event_id for e in data["events"])


def test_delete_event():
    init_db()
    habit = client.post("/habits", json={"name": "Delete Habit"}).json()
    event = client.post(
        "/events",
        json={"habit_id": habit["id"], "success": True},
    ).json()

    del_resp = client.delete(f"/events/{event['id']}")
    assert del_resp.status_code == 200

    events = client.get("/events").json()
    assert all(e["id"] != event["id"] for e in events)


def test_delete_event_not_found():
    init_db()
    response = client.delete("/events/9999")
    assert response.status_code == 404


def test_export_delete_import_round_trip():
    init_db()

    # Create unique data to export
    habit = client.post("/habits", json={"name": "Import Habit"}).json()
    event = client.post(
        "/events",
        json={"habit_id": habit["id"], "success": True},
    ).json()

    export_resp = client.get("/export")
    assert export_resp.status_code == 200
    exported = export_resp.json()

    # Remove the database file to simulate a clean slate
    from pathlib import Path
    from resistor.database import engine

    engine.dispose()
    Path(engine.url.database).unlink()
    init_db()

    # Verify DB is empty
    assert client.get("/habits").json() == []
    assert client.get("/events").json() == []

    import_resp = client.post("/import", json=exported)
    assert import_resp.status_code == 200

    habits_after = client.get("/habits").json()
    events_after = client.get("/events").json()

    assert any(h["id"] == habit["id"] for h in habits_after)
    assert any(e["id"] == event["id"] for e in events_after)
