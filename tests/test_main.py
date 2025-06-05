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
