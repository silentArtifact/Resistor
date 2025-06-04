from datetime import datetime
from pydantic import BaseModel


class HabitCreate(BaseModel):
    name: str
    color: str | None = None


class HabitRead(HabitCreate):
    id: int


class EventCreate(BaseModel):
    habit_id: int
    success: bool
    latitude: float | None = None
    longitude: float | None = None


class EventRead(EventCreate):
    id: int
    timestamp: datetime
