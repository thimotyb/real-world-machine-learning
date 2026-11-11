"""API tests: no Cloud Storage needed, the model is a tiny one trained here."""
import pickle
import sys
from pathlib import Path

from fastapi.testclient import TestClient
from sklearn import svm

API_DIR = str(Path(__file__).resolve().parents[1])


def make_client(monkeypatch, tmp_path, with_model):
    uri = None
    if with_model:
        model = svm.SVC(kernel="linear").fit(
            [[1, 1, 1, 1], [1.1, 1, 1, 1], [5, 5, 5, 5], [5.1, 5, 5, 5]],
            ["small", "small", "big", "big"],
        )
        path = tmp_path / "model.pkl"
        path.write_bytes(pickle.dumps(model))
        uri = str(path)
        monkeypatch.setenv("MODEL_URI", uri)
    else:
        monkeypatch.delenv("MODEL_URI", raising=False)
    sys.path.insert(0, API_DIR)  # "main" must be the API one, not the trainer one
    sys.modules.pop("main", None)
    import main

    return TestClient(main.app)


def test_health_without_model(monkeypatch, tmp_path):
    r = make_client(monkeypatch, tmp_path, with_model=False).get("/")
    assert r.status_code == 200
    assert r.json()["model_uri"] is None


def test_predict_without_model_is_503(monkeypatch, tmp_path):
    body = dict(sepal_length=1, sepal_width=1, petal_length=1, petal_width=1)
    assert make_client(monkeypatch, tmp_path, with_model=False).post("/predict", json=body).status_code == 503


def test_predict_with_model(monkeypatch, tmp_path):
    body = dict(sepal_length=5, sepal_width=5, petal_length=5, petal_width=5)
    r = make_client(monkeypatch, tmp_path, with_model=True).post("/predict", json=body)
    assert r.status_code == 200
    assert r.json()["species"] == "big"
