"""Prediction API. It loads the model from a file in a Cloud Storage bucket.

The location of the model is given by the MODEL_URI environment variable, for example
    gs://my-bucket/models/model-20261109-101500.pkl
When a new model is trained, the trainer changes MODEL_URI: Cloud Run creates a new
revision and the new revision loads the new model at startup.

Run locally with:  MODEL_URI=./model.pkl fastapi dev
"""
import os
import pickle
import time

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from app_logging import setup_logging

logger = setup_logging("iris-api")

MODEL_URI = os.environ.get("MODEL_URI")
VERSION = "v1"  # demo: change it, run the pipeline, and watch the new revision go live

app = FastAPI(title="Iris classifier (model from bucket)")


def load_model(uri):
    """Read the pickled model from Cloud Storage (gs://...) or from a local file."""
    if uri.startswith("gs://"):
        from google.cloud import storage

        bucket_name, blob_name = uri[len("gs://"):].split("/", 1)
        data = storage.Client().bucket(bucket_name).blob(blob_name).download_as_bytes()
        return pickle.loads(data)
    with open(uri, "rb") as f:
        return pickle.load(f)


# Load once at startup. Before the first CSV is uploaded there is no model yet.
if MODEL_URI:
    started = time.perf_counter()
    model = load_model(MODEL_URI)
    logger.info("Model loaded", extra={"fields": {"model_uri": MODEL_URI, "seconds": round(time.perf_counter() - started, 2)}})
else:
    model = None
    logger.warning("No MODEL_URI: the API starts without a model, /predict answers 503")


class IrisFeatures(BaseModel):
    sepal_length: float
    sepal_width: float
    petal_length: float
    petal_width: float


@app.get("/")
def health():
    """Shows which model this revision is serving."""
    return {"status": "ok", "version": VERSION, "model_uri": MODEL_URI}


@app.post("/predict")
def predict(f: IrisFeatures):
    if model is None:
        logger.warning("Prediction refused: no model yet")
        raise HTTPException(status_code=503, detail="No model yet: upload a CSV to the bucket")
    species = model.predict([[f.sepal_length, f.sepal_width, f.petal_length, f.petal_width]])[0]
    logger.info("Prediction", extra={"fields": {"species": str(species), "model_uri": MODEL_URI, **f.model_dump()}})
    return {"species": str(species), "model_uri": MODEL_URI}
