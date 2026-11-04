"""Train the Iris classifier and save it to disk.

This is the "notebook cells 1-13" turned into a plain script:
load data -> split -> train -> score -> pickle the model.

Run it with:  python train.py
"""
import pickle

from sklearn import datasets, svm
from sklearn.model_selection import train_test_split

MODEL_FILE = "model.pkl"


def main():
    # Load the Iris dataset (150 flowers, 4 measurements each)
    X, y = datasets.load_iris(return_X_y=True)

    # Keep 60% for training and 40% for testing (same split as the notebook)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.4, random_state=0
    )

    # Train a Support Vector Machine with a linear kernel
    model = svm.SVC(kernel="linear", C=1).fit(X_train, y_train)
    print(f"Accuracy on test set: {model.score(X_test, y_test):.3f}")

    # Serialize (pickle) the trained model so the API can load it later
    with open(MODEL_FILE, "wb") as f:
        pickle.dump(model, f)
    print(f"Model saved to {MODEL_FILE}")


if __name__ == "__main__":
    main()
