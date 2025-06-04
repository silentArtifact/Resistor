from fastapi import FastAPI, Depends, HTTPException
from sqlmodel import select

from .database import init_db, get_session
from .models import Habit, Event
from .schemas import HabitCreate, HabitRead, EventCreate, EventRead

app = FastAPI(title="Resistor API")


@app.on_event("startup")
def on_startup():
    init_db()


@app.post("/habits", response_model=HabitRead)
def create_habit(habit: HabitCreate, session=Depends(get_session)):
    db_habit = Habit.from_orm(habit)
    session.add(db_habit)
    session.commit()
    session.refresh(db_habit)
    return db_habit


@app.get("/habits", response_model=list[HabitRead])
def list_habits(session=Depends(get_session)):
    habits = session.exec(select(Habit)).all()
    return habits


@app.post("/events", response_model=EventRead)
def create_event(event: EventCreate, session=Depends(get_session)):
    habit = session.get(Habit, event.habit_id)
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found")
    db_event = Event.from_orm(event)
    session.add(db_event)
    session.commit()
    session.refresh(db_event)
    return db_event


@app.get("/events", response_model=list[EventRead])
def list_events(session=Depends(get_session)):
    events = session.exec(select(Event)).all()
    return events
