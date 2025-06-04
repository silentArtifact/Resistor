from fastapi.testclient import TestClient
from resistor.main import app
from resistor.database import init_db

client = TestClient(app)


def test_create_and_list_habit():
    init_db()
    response = client.post("/habits", json={"name": "Test"})
    assert response.status_code == 200
    habit_id = response.json()["id"]

    response = client.get("/habits")
    assert response.status_code == 200
    assert any(h["id"] == habit_id for h in response.json())
