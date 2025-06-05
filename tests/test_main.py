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
    payload = {
        "name": "Test",
        "description": "Example desc",
        "color": "#ff0000",
        "icon": "🔥",
    }
    response = client.post("/habits", json=payload)
    assert response.status_code == 200
    data = response.json()
    habit_id = data["id"]
    assert data["description"] == payload["description"]
    assert data["color"] == payload["color"]
    assert data["icon"] == payload["icon"]

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
            "note": "Feeling great",
        },
    )
    assert event_response.status_code == 200
    event_id = event_response.json()["id"]

    response = client.get("/events")
    assert response.status_code == 200
    event = next(e for e in response.json() if e["id"] == event_id)
    assert event["latitude"] == 1.0
    assert event["longitude"] == 2.0
    assert event["note"] == "Feeling great"


def test_create_event_invalid_habit():
    init_db()
    response = client.post(
        "/events", json={"habit_id": 999999, "success": True}
    )
    assert response.status_code == 404


def test_update_habit():
    init_db()
    habit = client.post("/habits", json={"name": "Old"}).json()

    resp = client.patch(
        f"/habits/{habit['id']}",
        json={"name": "New", "description": "Updated"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["name"] == "New"
    assert data["description"] == "Updated"

    listed = client.get("/habits").json()
    assert any(h["id"] == habit["id"] and h["name"] == "New" for h in listed)


def test_reorder_habits():
    init_db()
    h1 = client.post("/habits", json={"name": "One"}).json()
    h2 = client.post("/habits", json={"name": "Two"}).json()

    resp = client.patch(f"/habits/{h2['id']}", json={"position": 0})
    assert resp.status_code == 200

    habits = client.get("/habits").json()
    ids = [h["id"] for h in habits]
    assert ids[0] == h2["id"] and ids[1] == h1["id"]


def test_archive_habit():
    init_db()
    habit = client.post("/habits", json={"name": "Archivable"}).json()

    resp = client.patch(f"/habits/{habit['id']}", json={"archived": True})
    assert resp.status_code == 200
    assert resp.json()["archived"] is True

    default_list = client.get("/habits").json()
    assert all(h["id"] != habit["id"] for h in default_list)

    archived_list = client.get("/habits", params={"include_archived": "true"}).json()
    assert any(h["id"] == habit["id"] for h in archived_list)


def test_delete_habit():
    init_db()
    habit = client.post("/habits", json={"name": "To Remove"}).json()
    client.post("/events", json={"habit_id": habit["id"], "success": True})

    del_resp = client.delete(f"/habits/{habit['id']}")
    assert del_resp.status_code == 200

    habits_after = client.get("/habits").json()
    assert all(h["id"] != habit["id"] for h in habits_after)
    events_after = client.get("/events").json()
    assert all(e["habit_id"] != habit["id"] for e in events_after)


def test_export_data():
    init_db()
    habit_resp = client.post("/habits", json={"name": "Export Habit"})
    habit_id = habit_resp.json()["id"]
    event_resp = client.post(
        "/events",
        json={"habit_id": habit_id, "success": False, "note": "x"},
    )
    event_id = event_resp.json()["id"]

    response = client.get("/export")
    assert response.status_code == 200
    data = response.json()
    assert any(h["id"] == habit_id for h in data["habits"])
    assert any(e["id"] == event_id and e["note"] == "x" for e in data["events"])


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
        json={"habit_id": habit["id"], "success": True, "note": "note"},
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
    assert any(e["id"] == event["id"] and e["note"] == "note" for e in events_after)
