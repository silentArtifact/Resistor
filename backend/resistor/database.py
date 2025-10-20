from pathlib import Path
from sqlmodel import create_engine, SQLModel, Session

from .models import Settings

DATA_PATH = Path("data")
DATA_PATH.mkdir(exist_ok=True)
engine = create_engine(f"sqlite:///{DATA_PATH / 'resistor.db'}", echo=True)


def init_db_safe() -> None:
    """Create database tables if they do not already exist."""
    SQLModel.metadata.create_all(engine)
    # ensure default settings row exists
    with Session(engine) as session:
        if session.get(Settings, 1) is None:
            session.add(Settings(id=1, capture_location=True))
            session.commit()


def init_db_destructive() -> None:
    """Drop and recreate all tables.

    Intended for use in tests and fixtures that require a clean database
    state. Production code should prefer :func:`init_db_safe`.
    """

    SQLModel.metadata.drop_all(engine)
    init_db_safe()


def get_session():
    return Session(engine)
