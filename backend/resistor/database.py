from pathlib import Path
from sqlmodel import create_engine, SQLModel, Session

DATA_PATH = Path("data")
DATA_PATH.mkdir(exist_ok=True)
engine = create_engine(f"sqlite:///{DATA_PATH / 'resistor.db'}", echo=True)


def init_db():
    SQLModel.metadata.create_all(engine)


def get_session():
    """Yield a database session scoped to a context manager."""
    with Session(engine) as session:
        yield session
