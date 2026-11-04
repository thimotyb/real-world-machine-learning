# Iris ML Service – dal notebook alla produzione

Esempio didattico: un modello scikit-learn addestrato in un notebook diventa
un'API FastAPI, poi un container pronto per Artifact Registry e Cloud Run.

```
iris-ml-service/
├── notebook/   notebook originale (addestramento + Flask)
├── train.py    addestra il modello e crea model.pkl   (celle 1-13 del notebook)
├── main.py     API FastAPI                             (celle Flask del notebook)
├── pyproject.toml   dipendenze + entrypoint FastAPI
├── Dockerfile
└── postman/    collection per le chiamate di prova
```

## 1. Il notebook
Apri `notebook/Using_Pickle_and_Flask_for_ML_models.ipynb` in VS Code
(estensioni *Python* e *Jupyter*). Punti da far notare:
- addestramento e API sono mescolati nello stesso file;
- il modello viene ricaricato a ogni richiesta;
- Flask gira nel notebook e serve ngrok per raggiungerlo.

## 2. Esecuzione locale

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install uv
uv pip install -r pyproject.toml   # legge le dipendenze da pyproject.toml

python train.py                # crea model.pkl
fastapi dev                    # avvia l'API su http://localhost:8000 (porta 8000, reload automatico)
```

Documentazione interattiva generata da FastAPI: <http://localhost:8000/docs>

## 3. Container

```bash
docker build -t iris-ml-service .
docker run --rm -p 8000:8080 iris-ml-service
```

Il modello viene addestrato durante la build, così il pickle è sempre
compatibile con la versione di scikit-learn dell'immagine.
Cloud Run imposta da solo la variabile `PORT`.

## 4. Prove con Postman
Importa `postman/iris-ml-service.postman_collection.json`.
La variabile `base_url` vale `http://localhost:8000`: per provare il servizio
su Cloud Run sostituiscila con l'URL del servizio.

Oppure da terminale:

```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"sepal_length":5.1,"sepal_width":3.4,"petal_length":1.3,"petal_width":0.2}'
```

## 5. Passi successivi (corso)
Artifact Registry (push dell'immagine) → Cloud Run (deploy) → Cloud Build (automazione).
