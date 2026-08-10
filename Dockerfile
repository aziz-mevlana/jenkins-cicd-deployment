# 1. AŞAMA: Frontend Build İşlemi
FROM node:20-alpine AS frontend-builder
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

# 2. AŞAMA: Backend Build İşlemi
FROM python:3.11-alpine AS backend-builder
RUN apk add --no-cache gcc musl-dev postgresql-dev libffi-dev
WORKDIR /usr/src/app
COPY requirements.txt ./
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /usr/src/app/wheels -r requirements.txt

# 3. AŞAMA: Çalışma Zamanı (Runtime)
FROM python:3.11-alpine AS runtime
RUN apk add --no-cache libpq libffi
RUN addgroup -S appuser && adduser -S appuser -G appuser
WORKDIR /app

# Backend bağımlılıklarını kur
COPY --from=backend-builder /usr/src/app/wheels /wheels
RUN pip install --no-cache /wheels/* && rm -rf /wheels

# Django kodlarını kopyala
COPY django_project/ /app/django_project/
COPY manage.py /app/

# Frontend'de oluşan statik dosyaları kopyala
COPY --from=frontend-builder /app/frontend/dist /app/static

# İzinleri ayarla ve güvenli kullanıcıya geç
RUN chown -R appuser:appuser /app
USER appuser

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "django_project.wsgi:application"]