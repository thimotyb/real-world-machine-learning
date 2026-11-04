"""FastAPI service that serves the trained Iris model.

Replaces the Flask cells of the notebook. Run it with:
    fastapi dev
Then open http://localhost:8000/docs for the interactive documentation.
"""
import pickle

from fastapi import FastAPI
from pydantic import BaseModel

# Class ids returned by the model -> human readable names
SPECIES = {0: "setosa", 1: "versicolor", 2: "virginica"}

app = FastAPI(title="Iris classifier")

# Load the model ONCE at startup (the notebook reloaded it on every request)
with open("model.pkl", "rb") as f:
    model = pickle.load(f)


class IrisFeatures(BaseModel):
    """Request body. FastAPI validates it automatically (wrong type -> HTTP 422)."""

    sepal_length: float
    sepal_width: float
    petal_length: float
    petal_width: float


def predict(sepal_length, sepal_width, petal_length, petal_width):
    """Run the model and build the response."""
    class_id = int(model.predict([[sepal_length, sepal_width, petal_length, petal_width]])[0])
    return {"prediction": class_id, "species": SPECIES[class_id]}


@app.get("/")
def health():
    """Simple health check: handy to test that the container is up."""
    return {"status": "ok"}


@app.post("/predict")
def predict_post(features: IrisFeatures):
    """Prediction with a JSON body."""
    return predict(
        features.sepal_length,
        features.sepal_width,
        features.petal_length,
        features.petal_width,
    )


@app.get("/api/predict/{sepal_length}/{sepal_width}/{petal_length}/{petal_width}")
def predict_get(sepal_length: float, sepal_width: float, petal_length: float, petal_width: float):
    """Same route as the Flask notebook: values are passed in the URL."""
    return predict(sepal_length, sepal_width, petal_length, petal_width)
