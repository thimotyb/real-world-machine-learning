"""Trainer service. It is called by Eventarc when a file appears in the bucket.

Flow:
  1. Eventarc sends an HTTP POST with the Cloud Storage event (bucket + file name)
  2. we download the CSV and train a model
  3. we save the model in the same bucket:  models/model-<generation>.pkl
  4. we "re-deploy" the API: we set MODEL_URI on the Cloud Run service,
     which creates a new revision that loads the new model
"""
import io
import os
import pickle

import pandas as pd
from fastapi import FastAPI, HTTPException, Request
from google.api_core.exceptions import PreconditionFailed
from google.cloud import run_v2, storage
from sklearn import svm
from sklearn.model_selection import train_test_split

# Settings given at deploy time
PROJECT_ID = os.environ.get("PROJECT_ID")
REGION = os.environ.get("REGION")
API_SERVICE = os.environ.get("API_SERVICE", "iris-api")

FEATURES = ["SepalLengthCm", "SepalWidthCm", "PetalLengthCm", "PetalWidthCm"]
LABEL = "Species"

app = FastAPI(title="Iris trainer")


def train_model(csv_bytes):
    """Train on the CSV content. Returns the model and its accuracy on a test split."""
    df = pd.read_csv(io.BytesIO(csv_bytes))
    X_train, X_test, y_train, y_test = train_test_split(
        df[FEATURES], df[LABEL], test_size=0.3, random_state=0
    )
    model = svm.SVC(kernel="linear", C=1).fit(X_train.values, y_train)
    return model, model.score(X_test.values, y_test)


def redeploy_api(model_uri):
    """Set MODEL_URI on the API service. Cloud Run creates a new revision.

    We do NOT wait for the rollout to finish: Eventarc re-sends an event if the
    answer is slow, and that would start the training again (and again).
    """
    client = run_v2.ServicesClient()
    name = f"projects/{PROJECT_ID}/locations/{REGION}/services/{API_SERVICE}"
    service = client.get_service(name=name)
    container = service.template.containers[0]
    # keep the other variables, replace MODEL_URI
    others = [e for e in container.env if e.name != "MODEL_URI"]
    container.env = others + [run_v2.EnvVar(name="MODEL_URI", value=model_uri)]
    client.update_service(service=service)  # returns immediately, the rollout continues in background


@app.post("/")
async def handle_event(request: Request):
    # The body of a Cloud Storage event contains the bucket and the file name
    event = await request.json()
    bucket_name, file_name = event["bucket"], event["name"]
    print(f"Event received: gs://{bucket_name}/{file_name}")

    # Only react to CSV files in data/. The models/ folder is ignored, so that
    # saving a model does not trigger a new training.
    if not (file_name.startswith("data/") and file_name.endswith(".csv")):
        print("Ignored: not a CSV in data/")
        return {"status": "ignored"}

    bucket = storage.Client().bucket(bucket_name)
    model, accuracy = train_model(bucket.blob(file_name).download_as_bytes())
    print(f"Trained on {file_name}, accuracy {accuracy:.3f}")

    # Every upload gets its own versioned model. The name comes from the "generation"
    # of the uploaded file, so the same event always gives the same model name.
    model_file = f"models/model-{event['generation']}.pkl"
    model_uri = f"gs://{bucket_name}/{model_file}"
    try:
        # if_generation_match=0 means "write only if the file does not exist yet".
        # Eventarc delivers events AT LEAST once: a duplicate event stops here.
        bucket.blob(model_file).upload_from_string(pickle.dumps(model), if_generation_match=0)
    except PreconditionFailed:
        print(f"Duplicate event, {model_file} already exists")
        return {"status": "duplicate"}

    try:
        redeploy_api(model_uri)
    except Exception as e:
        # Show the real reason in the logs and in the response (easier to debug permissions)
        print(f"Redeploy failed: {e!r}")
        raise HTTPException(status_code=500, detail=f"Redeploy failed: {e!r}")
    print(f"API redeployed with {model_uri}")
    return {"status": "trained", "accuracy": accuracy, "model_uri": model_uri}
