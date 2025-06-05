import React, { useEffect, useState } from 'react';
import ReactDOM from 'react-dom/client';

function App() {
  const [habits, setHabits] = useState([]);
  const [form, setForm] = useState({
    name: '',
    description: '',
    color: '#000000',
    icon: '',
  });
  const [editId, setEditId] = useState(null);
  const [editForm, setEditForm] = useState({
    name: '',
    description: '',
    color: '#000000',
    icon: '',
  });

  useEffect(() => {
    fetch('/habits')
      .then((r) => r.json())
      .then(setHabits)
      .catch(() => setHabits([]));
  }, []);

  function createHabit(e) {
    e.preventDefault();
    fetch('/habits', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    })
      .then((r) => r.json())
      .then((habit) => {
        setHabits([...habits, habit]);
        setForm({ name: '', description: '', color: '#000000', icon: '' });
      });
  }

  function startEdit(habit) {
    setEditId(habit.id);
    setEditForm({
      name: habit.name,
      description: habit.description || '',
      color: habit.color || '#000000',
      icon: habit.icon || '',
    });
  }

  function updateHabit(e) {
    e.preventDefault();
    fetch(`/habits/${editId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(editForm),
    })
      .then((r) => r.json())
      .then((updated) => {
        setHabits(habits.map((h) => (h.id === updated.id ? updated : h)));
        setEditId(null);
      });
  }

  function deleteHabit(id) {
    fetch(`/habits/${id}`, { method: 'DELETE' }).then(() => {
      setHabits(habits.filter((h) => h.id !== id));
    });
  }

  function logEvent(habitId, success) {
    const send = (lat, lon) => {
      fetch('/events', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          habit_id: habitId,
          success,
          latitude: lat,
          longitude: lon,
        }),
      });
    };

    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (pos) => send(pos.coords.latitude, pos.coords.longitude),
        () => send(null, null)
      );
    } else {
      send(null, null);
    }
  }

  return (
    <div>
      <h1>Resistor</h1>
      <form onSubmit={createHabit} style={{ marginBottom: '1em' }}>
        <input
          placeholder="Name"
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          required
        />{' '}
        <input
          placeholder="Description"
          value={form.description}
          onChange={(e) => setForm({ ...form, description: e.target.value })}
        />{' '}
        <input
          type="color"
          value={form.color}
          onChange={(e) => setForm({ ...form, color: e.target.value })}
        />{' '}
        <input
          placeholder="Icon"
          value={form.icon}
          onChange={(e) => setForm({ ...form, icon: e.target.value })}
        />{' '}
        <button type="submit">Add Habit</button>
      </form>

      {editId && (
        <form onSubmit={updateHabit} style={{ marginBottom: '1em' }}>
          <input
            placeholder="Name"
            value={editForm.name}
            onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
            required
          />{' '}
          <input
            placeholder="Description"
            value={editForm.description}
            onChange={(e) =>
              setEditForm({ ...editForm, description: e.target.value })
            }
          />{' '}
          <input
            type="color"
            value={editForm.color}
            onChange={(e) => setEditForm({ ...editForm, color: e.target.value })}
          />{' '}
          <input
            placeholder="Icon"
            value={editForm.icon}
            onChange={(e) => setEditForm({ ...editForm, icon: e.target.value })}
          />{' '}
          <button type="submit">Save</button>{' '}
          <button type="button" onClick={() => setEditId(null)}>
            Cancel
          </button>
        </form>
      )}
      <ul>
        {habits.map((habit) => (
          <li key={habit.id}>
            {habit.icon && <span>{habit.icon} </span>}
            <span style={{ color: habit.color || 'inherit' }}>{habit.name}</span>
            {habit.description ? ` - ${habit.description}` : ''}{' '}
            <button onClick={() => logEvent(habit.id, true)}>Success</button>{' '}
            <button onClick={() => logEvent(habit.id, false)}>Slip</button>{' '}
            <button onClick={() => startEdit(habit)}>Edit</button>{' '}
            <button onClick={() => deleteHabit(habit.id)}>Delete</button>
          </li>
        ))}
      </ul>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
