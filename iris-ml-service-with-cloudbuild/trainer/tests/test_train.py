"""Trainer tests: train on the sample CSV files and check the model is sensible."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
SAMPLES = Path(__file__).resolve().parents[2] / "sample-data"

from main import FEATURES, train_model  # noqa: E402


def test_small_csv_gives_accurate_model():
    model, accuracy = train_model((SAMPLES / "iris-small.csv").read_bytes())
    assert accuracy > 0.9


def test_full_csv_knows_three_species():
    model, accuracy = train_model((SAMPLES / "iris-full.csv").read_bytes())
    assert accuracy > 0.9
    assert len(model.classes_) == 3


def test_features_are_the_documented_columns():
    assert FEATURES == ["SepalLengthCm", "SepalWidthCm", "PetalLengthCm", "PetalWidthCm"]
