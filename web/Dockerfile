# ---- Velouré web container ----
# Start from a small official Python image
FROM python:3.12-slim

# All app files live in /app inside the container
WORKDIR /app

# Install the Python libraries first (Docker caches this step,
# so rebuilds are fast when only the code changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code, templates and static files
COPY . .

# The app listens on port 5000 inside the container
EXPOSE 5000

# Run Flask with Gunicorn, a production web server (2 worker processes)
CMD ["gunicorn", "--workers", "2", "--bind", "0.0.0.0:5000", "app:app"]
