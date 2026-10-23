# ==============================================================================
# Dockerfile: Automated Image Build & Deployment Pipeline
# ==============================================================================
# Best Practices Implemented:
# 1. Base Image: python:3.12-slim (minimal attack surface, small image size ~150MB)
# 2. Layer Caching: requirements.txt is copied and installed BEFORE app code so
#    Docker reuses the cached dependency layer if only code changes.
# 3. Security: Creates and switches to a non-root user ('appuser') with least privilege.
# 4. Production Server: Uses Gunicorn WSGI server instead of Flask's built-in dev server.
# ==============================================================================

# Step 1: Use an official lightweight Python runtime
FROM python:3.12-slim

# Step 2: Set environment variables
# - PYTHONDONTWRITEBYTECODE: Prevents Python from writing .pyc files to disk
# - PYTHONUNBUFFERED: Ensures standard output/error logs are flushed immediately to stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=v1

# Step 3: Set working directory inside the container
WORKDIR /app

# Step 4: Create a dedicated non-root user and group for security
# Running containers as root is a major security risk; this ensures least privilege.
RUN groupadd -r appgroup && useradd -r -g appgroup -u 1000 appuser

# Step 5: Copy and install Python dependencies FIRST (Docker layer caching optimization)
# Because dependencies change infrequently, Docker will cache this layer.
# Code edits will NOT trigger a slow reinstall of packages!
COPY app/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Step 6: Copy the application source code into the container
COPY app/ /app/

# Step 7: Change ownership of the app directory to our non-root user
RUN chown -R appuser:appgroup /app

# Step 8: Switch to the non-root user
USER appuser

# Step 9: Document the port the container listens on
EXPOSE 8080

# Step 10: Run the application with Gunicorn
# - --bind 0.0.0.0:8080: Listens on all interfaces on port 8080
# - --workers 2: Number of worker processes to handle concurrent requests
# - app:app: Tells Gunicorn to look in app.py for the 'app' Flask instance
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
