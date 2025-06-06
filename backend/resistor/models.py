from datetime import datetime
from sqlmodel import SQLModel, Field


class Habit(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str
    description: str | None = None
    color: str | None = None
    icon: str | None = None
    position: int = Field(default=0, index=True)
    archived: bool = Field(default=False)


class Event(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    habit_id: int = Field(foreign_key="habit.id")
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    success: bool
    latitude: float | None = None
    longitude: float | None = None
    note: str | None = None


class Settings(SQLModel, table=True):
    """Application-wide configuration."""
    id: int | None = Field(default=1, primary_key=True)
    capture_location: bool = Field(default=True)
