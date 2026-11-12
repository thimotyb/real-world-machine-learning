FROM python:3.12-slim
WORKDIR /app

# uv reads the dependencies straight from pyproject.toml
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
COPY pyproject.toml .
RUN uv pip install --system -r pyproject.toml

COPY main.py .
COPY app_logging.py .

# Cloud Run sets PORT; 8080 is the fallback
ENV PORT=8080
CMD ["sh", "-c", "fastapi run --host 0.0.0.0 --port ${PORT}"]
