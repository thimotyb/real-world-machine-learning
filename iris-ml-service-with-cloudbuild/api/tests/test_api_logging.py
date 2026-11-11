"""The log entries must be JSON with "severity" and "message": that is what Cloud Logging understands."""
import json
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app_logging import CloudLoggingFormatter  # noqa: E402

from test_api import make_client  # noqa: E402


def json_lines(text):
    return [json.loads(line) for line in text.splitlines() if line.startswith("{")]


def test_formatter_gives_severity_message_and_fields():
    record = logging.LogRecord("iris-api", logging.WARNING, __file__, 1, "Something %s", ("happened",), None)
    record.fields = {"model_uri": "gs://b/m.pkl", "severity": "IGNORED"}
    entry = json.loads(CloudLoggingFormatter().format(record))
    assert entry["severity"] == "WARNING"
    assert entry["message"] == "Something happened"
    assert entry["model_uri"] == "gs://b/m.pkl"  # searchable in Logs Explorer: jsonPayload.model_uri


def test_exception_stack_trace_is_in_the_message():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys as _sys
        record = logging.LogRecord("iris-api", logging.ERROR, __file__, 1, "Failed", (), _sys.exc_info())
    entry = json.loads(CloudLoggingFormatter().format(record))
    assert entry["severity"] == "ERROR"
    assert "ValueError: boom" in entry["message"]


def test_api_writes_json_logs_on_cloud_run(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("K_SERVICE", "iris-api")  # this is how the API knows it runs on Cloud Run
    client = make_client(monkeypatch, tmp_path, with_model=True)
    client.post("/predict", json=dict(sepal_length=5, sepal_width=5, petal_length=5, petal_width=5))
    entries = json_lines(capsys.readouterr().out)
    assert {"Model loaded", "Prediction"} <= {e["message"] for e in entries}
    prediction = next(e for e in entries if e["message"] == "Prediction")
    assert prediction["severity"] == "INFO" and prediction["species"] == "big"
