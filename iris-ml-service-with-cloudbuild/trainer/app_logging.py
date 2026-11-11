"""Logging setup shared by the api and trainer services (same file in both folders).

On Cloud Run every line written to stdout is collected by Cloud Logging. If the line is a JSON
object with a "severity" and a "message" field, Cloud Logging stores it as a structured entry:
the severity shows up as an icon/colour in the Logs Explorer, and every other field becomes
searchable (for example  jsonPayload.model_uri="gs://..."). No extra library or IAM role needed.

Locally (no K_SERVICE variable) the same entries are printed as readable text.

Usage:
    from app_logging import setup_logging
    logger = setup_logging("iris-api")
    logger.info("Model loaded", extra={"fields": {"model_uri": uri, "seconds": 1.2}})
"""
import json
import logging
import os
import sys

# Python level names are also valid Cloud Logging severities
RESERVED = {"severity", "message", "time"}


class CloudLoggingFormatter(logging.Formatter):
    """One JSON object per line: severity, message, logger name, plus the "fields" given in extra."""

    def format(self, record):
        message = record.getMessage()
        if record.exc_info:
            # The stack trace goes inside "message": Cloud Logging / Error Reporting recognise it there
            message += "\n" + self.formatException(record.exc_info)
        entry = {"severity": record.levelname, "message": message, "logger": record.name}
        for key, value in getattr(record, "fields", {}).items():
            if key not in RESERVED:
                entry[key] = value
        return json.dumps(entry, default=str)


class ReadableFormatter(logging.Formatter):
    """Local runs: "INFO iris-api: Model loaded  {'model_uri': ...}"."""

    def format(self, record):
        text = f"{record.levelname:<7} {record.name}: {record.getMessage()}"
        fields = getattr(record, "fields", None)
        if fields:
            text += f"  {fields}"
        if record.exc_info:
            text += "\n" + self.formatException(record.exc_info)
        return text


def setup_logging(name):
    """Configure the root logger once and return the logger of this service."""
    handler = logging.StreamHandler(sys.stdout)
    on_cloud_run = bool(os.environ.get("K_SERVICE"))
    handler.setFormatter(CloudLoggingFormatter() if on_cloud_run else ReadableFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
    return logging.getLogger(name)
