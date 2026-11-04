# Small official Python image
FROM python:3.12-slim

WORKDIR /app

# uv: a fast installer that can read dependencies straight from pyproject.toml
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install dependencies first: Docker caches this layer until pyproject.toml changes
COPY pyproject.toml .
RUN uv pip install --system -r pyproject.toml

# Copy the application code
COPY train.py main.py ./

# Train the model INSIDE the image, so the pickle always matches
# the scikit-learn version installed above
RUN python train.py

# Cloud Run tells the container which port to use through the PORT variable.
# Locally we fall back to 8080.
ENV PORT=8080
# `fastapi run` is the production command; the app location comes from [tool.fastapi] in pyproject.toml
CMD ["sh", "-c", "fastapi run --host 0.0.0.0 --port ${PORT}"]
