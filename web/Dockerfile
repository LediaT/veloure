# ---- Velouré web container ----
# Built from the project root (see docker-compose.yml / render.yaml)
FROM python:3.12-slim

WORKDIR /app

# Install the Python libraries first (cached between builds)
COPY web/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application code, templates, static files, and the menu (used to fill an empty hosted database)
COPY web/ .
COPY db/init.sql ./init.sql

EXPOSE 5000

# Gunicorn production server. Locally it uses port 5000; hosts like Render pass their own $PORT.
CMD ["sh", "-c", "gunicorn --workers 2 --bind 0.0.0.0:${PORT:-5000} app:app"]
