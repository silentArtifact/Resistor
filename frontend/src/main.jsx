import React, { useEffect, useState } from 'react';
import ReactDOM from 'react-dom/client';

function App() {
  const [habits, setHabits] = useState([]);

  useEffect(() => {
    fetch('/habits')
      .then((r) => r.json())
      .then(setHabits)
      .catch(() => setHabits([]));
  }, []);

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
      <ul>
        {habits.map((habit) => (
          <li key={habit.id}>
            {habit.name}{' '}
            <button onClick={() => logEvent(habit.id, true)}>Success</button>{' '}
            <button onClick={() => logEvent(habit.id, false)}>Slip</button>
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
