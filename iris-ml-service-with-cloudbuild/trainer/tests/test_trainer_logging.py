"""The trainer logs the training result as a searchable JSON entry (Cloud Logging)."""
import json
import sys
from pathlib import Path

TRAINER_DIR = str(Path(__file__).resolve().parents[1])
SAMPLES = Path(__file__).resolve().parents[2] / "sample-data"


def test_training_is_logged_with_accuracy(monkeypatch, capsys):
    monkeypatch.setenv("K_SERVICE", "iris-trainer")
    sys.path.insert(0, TRAINER_DIR)  # "main" must be the trainer one, not the API one
    sys.modules.pop("main", None)
    import main

    main.train_model((SAMPLES / "iris-small.csv").read_bytes())
    entries = [json.loads(l) for l in capsys.readouterr().out.splitlines() if l.startswith("{")]
    trained = next(e for e in entries if e["message"] == "Model trained")
    assert trained["severity"] == "INFO"
    assert trained["accuracy"] > 0.9 and trained["rows"] > 0
