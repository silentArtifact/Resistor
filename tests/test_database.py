from sqlmodel import Session

from resistor.database import init_db_destructive, init_db_safe, engine
from resistor.models import Habit


def test_init_db_safe_preserves_data():
    init_db_destructive()

    with Session(engine) as session:
        habit = Habit(name="Persistent")
        session.add(habit)
        session.commit()
        habit_id = habit.id

    init_db_safe()
    with Session(engine) as session:
        assert session.get(Habit, habit_id) is not None

    init_db_safe()
    with Session(engine) as session:
        assert session.get(Habit, habit_id) is not None
