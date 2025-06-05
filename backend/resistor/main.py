from fastapi import FastAPI, Depends, HTTPException
from sqlmodel import select

from .database import init_db, get_session
from .models import Habit, Event
from .schemas import (
    HabitCreate,
    HabitRead,
    HabitUpdate,
    EventCreate,
    EventRead,
    ExportBundle,
)

app = FastAPI(title="Resistor API")


@app.get("/healthz")
def healthz():
    """Simple health check endpoint."""
    return {"status": "ok"}


@app.on_event("startup")
def on_startup():
    init_db()


@app.post("/habits", response_model=HabitRead)
def create_habit(habit: HabitCreate, session=Depends(get_session)):
    db_habit = Habit.model_validate(habit, from_attributes=True)
    session.add(db_habit)
    session.commit()
    session.refresh(db_habit)
    return db_habit


@app.get("/habits", response_model=list[HabitRead])
def list_habits(session=Depends(get_session)):
    habits = session.exec(select(Habit)).all()
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
    db_event = Event.model_validate(event, from_attributes=True)
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
def export_data(session=Depends(get_session)):
    """Export all habits and events as JSON."""
    habits = session.exec(select(Habit)).all()
    events = session.exec(select(Event)).all()
    return {
        "habits": [HabitRead.model_validate(h, from_attributes=True) for h in habits],
        "events": [EventRead.model_validate(e, from_attributes=True) for e in events],
    }


@app.post("/import")
def import_data(payload: ExportBundle, session=Depends(get_session)):
    """Import habits and events from an export payload."""
    # Validate and load habits
    habits = [Habit.model_validate(h, from_attributes=True) for h in payload.habits]
    events = [Event.model_validate(e, from_attributes=True) for e in payload.events]

    for habit in habits:
        session.merge(habit)
    for event in events:
        # Ensure referenced habit exists in the current session
        if not session.get(Habit, event.habit_id):
            raise HTTPException(status_code=400, detail="Habit not found for event")
        session.merge(event)

    session.commit()
    return {"status": "imported"}
