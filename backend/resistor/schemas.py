from datetime import datetime
from pydantic import BaseModel


class HabitCreate(BaseModel):
    name: str
    description: str | None = None
    color: str | None = None
    icon: str | None = None


class HabitRead(HabitCreate):
    id: int


class HabitUpdate(BaseModel):
    """Fields that can be updated on a habit."""
    name: str | None = None
    description: str | None = None
    color: str | None = None
    icon: str | None = None


class EventCreate(BaseModel):
    habit_id: int
    success: bool
    latitude: float | None = None
    longitude: float | None = None


class EventRead(EventCreate):
    id: int
    timestamp: datetime


class ExportBundle(BaseModel):
    """Payload used for full data export/import."""
    habits: list[HabitRead]
    events: list[EventRead]
