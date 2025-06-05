FROM node:20 AS frontend-build
WORKDIR /app/frontend
COPY frontend/package.json .
COPY frontend/package-lock.json* ./
RUN npm install
COPY frontend .
RUN npm run build

FROM python:3.11-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend ./
COPY --from=frontend-build /app/frontend/dist ./frontend/dist
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD curl -f http://localhost:8080/healthz || exit 1
CMD ["uvicorn", "resistor.main:app", "--host", "0.0.0.0", "--port", "8080"]
