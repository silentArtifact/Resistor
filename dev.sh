#!/bin/sh
# Simple development server launcher for Resistor

( cd backend && uvicorn resistor.main:app --reload --port 8080 ) &
BACK_PID=$!
( cd frontend && npm run dev ) &
FRONT_PID=$!

trap 'kill $BACK_PID $FRONT_PID' INT
wait $BACK_PID $FRONT_PID
