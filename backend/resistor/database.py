from pathlib import Path
from sqlmodel import create_engine, SQLModel, Session

DATA_PATH = Path("data")
DATA_PATH.mkdir(exist_ok=True)
engine = create_engine(f"sqlite:///{DATA_PATH / 'resistor.db'}", echo=True)


def init_db():
    """Recreate database tables to ensure schema matches models."""
    SQLModel.metadata.drop_all(engine)
    SQLModel.metadata.create_all(engine)


def get_session():
    return Session(engine)
