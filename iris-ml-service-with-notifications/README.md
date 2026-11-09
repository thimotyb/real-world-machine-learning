# Iris ML Service con notifiche – nuovo CSV nel bucket → training → redeploy

Evoluzione di `iris-ml-service`: il modello non è più dentro l'immagine ma vive in un
bucket. Quando qualcuno carica un nuovo CSV, Google Cloud avvisa un servizio di training
che addestra un nuovo modello e fa ripartire l'API con il modello nuovo.

```
 CSV ──► bucket  ──notifica (Eventarc)──► iris-trainer (Cloud Run)
          data/                              │ 1. scarica il CSV e addestra
          models/  ◄─────────────────────────┤ 2. salva models/model-<data>.pkl
                                             │ 3. aggiorna MODEL_URI dell'API
                                             ▼
                                     iris-api (Cloud Run)  → nuova revisione col nuovo modello
```

```
iris-ml-service-with-notifications/
├── api/          API FastAPI: carica il modello dal bucket (MODEL_URI)
├── trainer/      servizio di training, chiamato dalla notifica
├── sample-data/  iris-small.csv (solo 2 specie) e iris-full.csv (tutte e 3)
├── terraform/    bucket, repository, service account e permessi
├── scripts/      deploy.sh: immagini, servizi Cloud Run, trigger Eventarc
└── postman/      richieste di prova
```

## Cosa mostrare
- **Notifica di bucket:** il trigger Eventarc `google.cloud.storage.object.v1.finalized`
  avvisa il trainer a ogni file nuovo. Il trainer ignora tutto ciò che non è un CSV in `data/`
  (altrimenti salvare un modello farebbe ripartire il training all'infinito).
- **Redeploy:** il trainer cambia la variabile `MODEL_URI` del servizio API: Cloud Run crea
  una nuova revisione. Rollback = tornare alla revisione precedente (vedi Cloud Run → Revisioni).
- **Modelli versionati** nel bucket (`models/model-<generation>.pkl`).
- **Permessi minimi:** l'API può solo leggere dal bucket; il trainer scrive e aggiorna l'API;
  il trainer è privato, lo chiama solo Eventarc.

## Esecuzione

Nei lab Google Skills il progetto e la regione cambiano a ogni avvio: prima di tutto

```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  eventarc.googleapis.com pubsub.googleapis.com storage.googleapis.com
gcloud config set compute/region us-east1      # la regione indicata dal lab
```

**1. Infrastruttura** (bucket, repository, service account):

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply \
  -var "project_id=$(gcloud config get-value project)" \
  -var "region=$(gcloud config get-value compute/region)" \
  -var "enable_apis=false"       # nei lab le API sono già abilitate dal comando sopra
cd ..
```

**2. Immagini, servizi e trigger:**

```bash
./scripts/deploy.sh
```

Alla fine stampa l'URL dell'API. Il trigger può impiegare alcuni minuti prima di essere
attivo e i permessi impiegano un po' a propagarsi: se la prima prova non parte, riprova dopo 2-3 minuti.

**3. Prova**

```bash
BUCKET=$(gcloud config get-value project)-iris-data
API=<URL stampato dallo script>

curl $API/                       # model_uri è null: ancora nessun modello
gcloud storage cp sample-data/iris-small.csv gs://$BUCKET/data/
# attendi ~1 minuto, poi:
curl $API/                       # model_uri punta al primo modello
curl -X POST $API/predict -H "Content-Type: application/json" \
  -d '{"sepal_length":6.7,"sepal_width":3.0,"petal_length":5.2,"petal_width":2.3}'
# risponde Iris-versicolor: il CSV piccolo non contiene la specie virginica

gcloud storage cp sample-data/iris-full.csv gs://$BUCKET/data/
# attendi ~1 minuto: nuova revisione, nuovo modello
# la stessa richiesta ora risponde Iris-virginica
```

Per seguire cosa succede: `gcloud run services logs read iris-trainer --region <regione>`
e, nella console, Cloud Run → `iris-api` → Revisioni.

Con Postman: importa `postman/iris-ml-service-with-notifications.postman_collection.json`
e imposta `base_url` all'URL dell'API (la richiesta "Predict - virginica" fallisce finché
non è stato caricato `iris-full.csv`, ed è voluto).

## Permessi GCP necessari

### 1. Chi lancia Terraform e `scripts/deploy.sh`
Ruoli sul progetto:

| Ruolo | A cosa serve |
|---|---|
| `roles/artifactregistry.admin` | creare il repository e fare il push delle due immagini |
| `roles/run.admin` | distribuire i due servizi Cloud Run e dare `run.invoker` al trainer |
| `roles/iam.serviceAccountAdmin` | creare i service account `iris-api` e `iris-trainer` |
| `roles/iam.serviceAccountUser` | usare i due service account nei servizi Cloud Run |
| `roles/resourcemanager.projectIamAdmin` | assegnare i ruoli di progetto al trainer e all'agente di Cloud Storage |
| `roles/storage.admin` | creare il bucket e i suoi permessi |
| `roles/eventarc.admin` | creare il trigger Eventarc |
| `roles/serviceusage.serviceUsageAdmin` | solo se Terraform abilita le API (`enable_apis = true`) |

API da abilitare: `artifactregistry`, `run`, `eventarc`, `pubsub`, `storage` (`.googleapis.com`).
Per leggere i log dei servizi serve inoltre `roles/logging.viewer`.

### 2. Permessi che Terraform assegna alle identità del progetto

| Identità | Ruolo | Dove | Perché |
|---|---|---|---|
| `iris-api` (esegue l'API) | `roles/storage.objectViewer` | bucket | leggere il modello |
| `iris-trainer` (esegue il training) | `roles/storage.objectAdmin` | bucket | leggere i CSV e scrivere i modelli |
| `iris-trainer` | `roles/run.developer` | progetto | aggiornare il servizio API (nuova revisione) |
| `iris-trainer` | `roles/iam.serviceAccountUser` | sul service account `iris-api` | Cloud Run richiede il permesso "act as" sull'identità dell'API |
| `iris-trainer` | `roles/artifactregistry.reader` | repository | l'aggiornamento di Cloud Run verifica che chi aggiorna possa leggere l'immagine |
| `iris-trainer` | `roles/eventarc.eventReceiver` | progetto | ricevere gli eventi di Eventarc |
| `iris-trainer` | `roles/run.invoker` | servizio `iris-trainer` | Eventarc chiama il trainer con questa identità (lo imposta `deploy.sh`) |
| agente di servizio di Cloud Storage | `roles/pubsub.publisher` | progetto | Cloud Storage pubblica le notifiche tramite Pub/Sub |
| agente di servizio di Eventarc | `roles/eventarc.serviceAgent` | progetto | assegnato da Google quando si abilita l'API |

Se manca `artifactregistry.reader` il trainer addestra e salva il modello ma l'aggiornamento
dell'API fallisce con `artifactregistry.repositories.downloadArtifacts denied`.
Dopo aver abilitato l'API Eventarc, i permessi dell'agente di servizio possono impiegare qualche minuto.

## Formato del CSV
Stesse colonne di `Iris.csv`: `SepalLengthCm, SepalWidthCm, PetalLengthCm, PetalWidthCm, Species`
(la colonna `Id` è ignorata). Il file va caricato nella cartella `data/` del bucket.

## Pulizia
```bash
gcloud eventarc triggers delete iris-new-file --location <regione>
gcloud run services delete iris-api iris-trainer --region <regione>
cd terraform && terraform destroy -var "project_id=$(gcloud config get-value project)" \
  -var "region=<regione>" -var "enable_apis=false"
```

## Lab Google Skills collegati (per approfondire)
Il lab [Hello Cloud Run](https://www.skills.google/focuses/30842?parent=catalog) fornisce
l'ambiente (progetto temporaneo, Cloud Shell). Per la parte di notifiche dal bucket:
- [Cloud Run Functions: Qwik Start](https://www.skills.google/focuses/49757?parent=catalog) (GSP1089)
- [Develop and Deploy Cloud Run Functions](https://www.skills.google/focuses/57552?parent=catalog)
- [Eventarc for Cloud Run](https://www.skills.google/focuses/15657?parent=catalog) (GSP773)
