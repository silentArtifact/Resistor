from fastapi import FastAPI, Depends, HTTPException, Body
from fastapi.encoders import jsonable_encoder
from sqlmodel import select
from datetime import datetime, timedelta

from .database import init_db, get_session
from .models import Habit, Event, Settings
from .schemas import (
    HabitCreate,
    HabitRead,
    HabitUpdate,
    EventCreate,
    EventRead,
    ExportBundle,
    SettingsSchema,
)
from .crypto import encrypt_json, decrypt_json

app = FastAPI(title="Resistor API")


@app.get("/healthz")
def healthz():
    """Simple health check endpoint."""
    return {"status": "ok"}


@app.on_event("startup")
def on_startup():
    init_db()


@app.get("/settings", response_model=SettingsSchema)
def get_settings(session=Depends(get_session)):
    """Return current configuration."""
    return session.get(Settings, 1)


@app.patch("/settings", response_model=SettingsSchema)
def update_settings(payload: SettingsSchema, session=Depends(get_session)):
    settings = session.get(Settings, 1)
    settings.capture_location = payload.capture_location
    session.add(settings)
    session.commit()
    session.refresh(settings)
    return settings


@app.post("/habits", response_model=HabitRead)
def create_habit(habit: HabitCreate, session=Depends(get_session)):
    data = habit.model_dump(exclude_unset=True)
    if data.get("position") is None:
        max_pos = session.exec(select(Habit.position).order_by(Habit.position.desc())).first()
        data["position"] = (max_pos or 0) + 1
    db_habit = Habit(**data)
    session.add(db_habit)
    session.commit()
    session.refresh(db_habit)
    return db_habit


@app.get("/habits", response_model=list[HabitRead])
def list_habits(include_archived: bool = False, session=Depends(get_session)):
    query = select(Habit)
    if not include_archived:
        query = query.where(Habit.archived == False)  # noqa: E712
    habits = session.exec(query.order_by(Habit.position)).all()
    return habits


@app.patch("/habits/{habit_id}", response_model=HabitRead)
def update_habit(habit_id: int, updates: HabitUpdate, session=Depends(get_session)):
    """Modify an existing habit."""
    habit = session.get(Habit, habit_id)
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found")
    for field, value in updates.model_dump(exclude_unset=True).items():
        setattr(habit, field, value)
    session.add(habit)
    session.commit()
    session.refresh(habit)
    return habit


@app.delete("/habits/{habit_id}")
def delete_habit(habit_id: int, session=Depends(get_session)):
    """Delete a habit and all its events."""
    habit = session.get(Habit, habit_id)
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found")
    events = session.exec(select(Event).where(Event.habit_id == habit_id)).all()
    for event in events:
        session.delete(event)
    session.delete(habit)
    session.commit()
    return {"status": "deleted"}


@app.post("/events", response_model=EventRead)
def create_event(event: EventCreate, session=Depends(get_session)):
    habit = session.get(Habit, event.habit_id)
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found")
    data = event.model_dump(exclude_unset=True)
    settings = session.get(Settings, 1)
    if settings and not settings.capture_location:
        data["latitude"] = None
        data["longitude"] = None
    db_event = Event(**data)
    session.add(db_event)
    session.commit()
    session.refresh(db_event)
    return db_event


@app.get("/events", response_model=list[EventRead])
def list_events(session=Depends(get_session)):
    events = session.exec(select(Event)).all()
    return events


@app.delete("/events/{event_id}")
def delete_event(event_id: int, session=Depends(get_session)):
    """Delete a single event by id."""
    event = session.get(Event, event_id)
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    session.delete(event)
    session.commit()
    return {"status": "deleted"}


@app.get("/export")
def export_data(passphrase: str | None = None, session=Depends(get_session)):
    """Export all habits and events as JSON."""
    habits = session.exec(select(Habit)).all()
    events = session.exec(select(Event)).all()
    payload = {
        "habits": [HabitRead.model_validate(h, from_attributes=True) for h in habits],
        "events": [EventRead.model_validate(e, from_attributes=True) for e in events],
    }
    if passphrase:
        return {"encrypted": encrypt_json(jsonable_encoder(payload), passphrase)}
    return payload


@app.post("/import")
def import_data(
    payload: dict = Body(...),
    passphrase: str | None = None,
    session=Depends(get_session),
):
    """Import habits and events from an export payload."""
    if "encrypted" in payload:
        if not passphrase:
            raise HTTPException(status_code=400, detail="Passphrase required")
        try:
            payload = decrypt_json(payload["encrypted"], passphrase)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid passphrase")

    bundle = ExportBundle.model_validate(payload)

    # Validate and load habits
    habits = [Habit.model_validate(h, from_attributes=True) for h in bundle.habits]
    events = [Event.model_validate(e, from_attributes=True) for e in bundle.events]

    for habit in habits:
        session.merge(habit)
    for event in events:
        # Ensure referenced habit exists in the current session
        if not session.get(Habit, event.habit_id):
            raise HTTPException(status_code=400, detail="Habit not found for event")
        session.merge(event)

    session.commit()
    return {"status": "imported"}


@app.get("/analytics")
def analytics(session=Depends(get_session)):
    """Return daily and weekly counts of events per habit."""
    now = datetime.utcnow()
    start_day = now - timedelta(days=1)
    start_week = now - timedelta(days=7)

    habits = session.exec(select(Habit)).all()
    results = []

    for habit in habits:
        day_events = session.exec(
            select(Event).where(Event.habit_id == habit.id, Event.timestamp >= start_day)
        ).all()
        week_events = session.exec(
            select(Event).where(Event.habit_id == habit.id, Event.timestamp >= start_week)
        ).all()

        daily_resist = sum(1 for e in day_events if e.success)
        daily_slip = sum(1 for e in day_events if not e.success)
        weekly_resist = sum(1 for e in week_events if e.success)
        weekly_slip = sum(1 for e in week_events if not e.success)

        results.append(
            {
                "habit_id": habit.id,
                "habit_name": habit.name,
                "daily_resist": daily_resist,
                "daily_slip": daily_slip,
                "weekly_resist": weekly_resist,
                "weekly_slip": weekly_slip,
            }
        )

    return results
