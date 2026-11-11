# Iris ML Service con Cloud Build – una pipeline che prova, costruisce e distribuisce

Evoluzione di `iris-ml-service-with-notifications`: stesso servizio (API + trainer + notifica dal bucket),
ma gli aggiornamenti del codice non si fanno più con `docker build` e `gcloud run deploy` a mano.
Li fa una **pipeline Cloud Build** (`cloudbuild.yaml`) che prova il codice, costruisce le immagini,
le pubblica su Artifact Registry e distribuisce i due servizi Cloud Run.

```
 sorgente ──► Cloud Build (cloudbuild.yaml)
              │ 1. test API e trainer (pytest, in parallelo)
              │ 2. build delle due immagini (tag = identificativo della build/commit)
              │ 3. push su Artifact Registry
              ▼ 4. deploy iris-api e iris-trainer su Cloud Run  ──► nuova revisione
```

La pipeline si può lanciare in **due modi**:
- **a mano** con `gcloud builds submit` (percorso della lezione: non serve un repository git);
- **da git** con un trigger (push o pull request su GitHub): sezione opzionale in fondo.

```
iris-ml-service-with-cloudbuild/
├── cloudbuild.yaml        la pipeline
├── api/  trainer/         come nell'esempio con le notifiche, più la cartella tests/
├── terraform/             bucket, repository immagini, service account (anche quello della pipeline)
├── scripts/
│   ├── setup-events.sh    una tantum: trigger Eventarc "nuovo file nel bucket → trainer"
│   └── create-trigger.sh  opzionale: trigger GitHub con approvazione manuale
└── sample-data/  postman/
```

## Cosa mostrare
- **Una sola pipeline per tutto**: lo stesso file serve per il primo deploy e per ogni aggiornamento.
- **La pipeline ferma i deploy sbagliati**: se un test fallisce non viene costruita nessuna immagine
  e Cloud Run resta com'era.
- **Identità dedicata**: la pipeline gira come `iris-cloudbuild`, che può solo scrivere le immagini,
  distribuire i due servizi e usare i loro service account (non l'account predefinito di Cloud Build).
- **Codice e modello sono separati**: il deploy dell'API non imposta `MODEL_URI`, che resta quello
  scritto dal trainer. Si aggiorna il codice senza perdere il modello.
- **Ogni build lascia una revisione** di Cloud Run con l'immagine taggata: il rollback è un clic.

## Istruzioni per far girare l'esempio in Google Skills

**Lab di base:** [Hello Cloud Run](https://www.skills.google/focuses/30842?parent=catalog) (progetto temporaneo
`qwiklabs-gcp-...`, Cloud Shell, Docker e Terraform pronti). Progetto e regione cambiano a ogni avvio,
per questo i comandi li leggono da `gcloud`.

**1. Prendi il codice e imposta progetto e regione** (dal Cloud Shell)

```bash
git clone -b python3 https://github.com/thimotyb/real-world-machine-learning.git
# se l'hai già clonato:  cd real-world-machine-learning && git pull
cd real-world-machine-learning/iris-ml-service-with-cloudbuild

gcloud config get-value project                # deve essere il qwiklabs-gcp-... del lab
gcloud config set compute/region us-east1      # la regione indicata dal lab
PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud config get-value compute/region)
```

**2. Abilita le API** (nel lab Terraform non può farlo)

```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com eventarc.googleapis.com \
  pubsub.googleapis.com storage.googleapis.com cloudbuild.googleapis.com
```

Aspetta 2-3 minuti (come nell'esempio con le notifiche: l'agente di Eventarc ha bisogno di tempo).

**3. Terraform** (bucket, repository immagini, service account, permessi della pipeline)

```bash
cd terraform
terraform init
terraform apply -var "project_id=$PROJECT_ID" -var "region=$REGION" -var "enable_apis=false"
cd ..
```

Controlla il piano e rispondi `yes`. Crea anche `iris-cloudbuild`, l'identità della pipeline.

**4. Prima esecuzione della pipeline, a mano** (sostituisce `docker build` + `gcloud run deploy`)

```bash
gcloud builds submit . \
  --region "$REGION" \
  --config cloudbuild.yaml \
  --gcs-source-staging-dir "gs://${PROJECT_ID}-iris-data/source" \
  --service-account "projects/${PROJECT_ID}/serviceAccounts/iris-cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com" \
  --substitutions "_REGION=${REGION},SHORT_SHA=build1"
```

- `--gcs-source-staging-dir`: dove caricare il sorgente (il bucket creato da Terraform; `iris-cloudbuild` può leggerlo).
- `SHORT_SHA` è il tag delle immagini: con un trigger lo mette Cloud Build (primi caratteri del commit),
  lanciando a mano lo scegli tu. **Cambialo a ogni lancio** (`build2`, `build3`...).
- Dura circa 4-5 minuti: guarda i passi in Console → Cloud Build → Cronologia
  (`test-api` e `test-trainer` in parallelo, poi `build-*`, `push-*`, `deploy-*`).

Al termine ci sono due servizi Cloud Run, `iris-api` e `iris-trainer`.

**5. Collega il bucket al trainer** (una tantum)

```bash
./scripts/setup-events.sh        # alla fine stampa "API URL": copialo
```

Crea il trigger Eventarc come nell'esempio con le notifiche (se fallisce alla prima prova per i permessi
di Eventarc, riprova da solo per ~5 minuti).

**6. Demo: il modello**

```bash
BUCKET=${PROJECT_ID}-iris-data
API=<URL stampato dallo script>

curl $API/                       # "version": "v1", "model_uri": null: ancora nessun modello
gcloud storage cp sample-data/iris-small.csv gs://$BUCKET/data/
# attendi 30-60 secondi (la prima volta fino a 2 minuti: il trigger si attiva), poi:
curl $API/                       # model_uri punta al primo modello
curl -X POST $API/predict -H "Content-Type: application/json" \
  -d '{"sepal_length":6.7,"sepal_width":3.0,"petal_length":5.2,"petal_width":2.3}'
# risponde Iris-versicolor
```

**7. Demo: aggiorna il codice con la pipeline**

```bash
sed -i 's/VERSION = "v1"/VERSION = "v2"/' api/main.py

gcloud builds submit . --region "$REGION" --config cloudbuild.yaml \
  --gcs-source-staging-dir "gs://${PROJECT_ID}-iris-data/source" \
  --service-account "projects/${PROJECT_ID}/serviceAccounts/iris-cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com" \
  --substitutions "_REGION=${REGION},SHORT_SHA=build2"

curl $API/                       # "version": "v2" e model_uri INVARIATO
```

In Cloud Run → `iris-api` → Revisioni c'è una nuova revisione con l'immagine `iris-api:build2`.

**8. Demo: la pipeline blocca un errore**

```bash
sed -i 's/== "big"/== "huge"/' api/tests/test_api.py        # rompi un test

gcloud builds submit . --region "$REGION" --config cloudbuild.yaml \
  --gcs-source-staging-dir "gs://${PROJECT_ID}-iris-data/source" \
  --service-account "projects/${PROJECT_ID}/serviceAccounts/iris-cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com" \
  --substitutions "_REGION=${REGION},SHORT_SHA=build3"
# BUILD FAILURE al passo test-api: nessuna immagine nuova, nessuna nuova revisione

curl $API/                       # il servizio è ancora quello di prima
sed -i 's/== "huge"/== "big"/' api/tests/test_api.py        # ripristina
```

**9. Prova solo test e build, senza distribuire**

Aggiungi `_DEPLOY=false` alle sostituzioni (`--substitutions "_REGION=${REGION},SHORT_SHA=prova,_DEPLOY=false"`):
la pipeline fa test, build e push ma salta i due passi di deploy. È quello che fa il trigger delle pull request.

Postman: importa `postman/iris-ml-service-with-cloudbuild.postman_collection.json` e imposta `base_url`.

## Opzionale: lanciare la pipeline da git (push o pull request)

Per chi ha un account GitHub (non serve nella lezione). Un trigger Cloud Build parte da un
repository, quindi **ci vuole un repo GitHub con il contenuto di questa cartella alla radice**
(i passi della pipeline usano `./api` e `./trainer`).

1. Crea un repository GitHub e carica la cartella `iris-ml-service-with-cloudbuild` come radice
   (`git init -b main`, `git add .`, `git commit`, `git push`).
2. **Passo manuale in console, una tantum:** Cloud Build → Repository (2ª generazione) →
   *Crea connessione host* → GitHub → autorizza l'app e *Collega repository*. Prendi nota del nome della
   connessione e del repository (non si può fare da script: richiede l'autorizzazione OAuth).
3. Crea i trigger:
   ```bash
   CONNECTION=<nome connessione> GITHUB_REPO=<nome repository> ./scripts/create-trigger.sh
   ```
   Crea `iris-deploy` (push su `main`, **con approvazione manuale**) e `iris-pull-request`
   (test e build senza deploy).
4. Demo: modifica `api/main.py`, `git push` su `main`. La build resta *In attesa di approvazione*
   in Cloud Build → Cronologia finché non la approvi (console, oppure `gcloud builds approve <ID> --region "$REGION"`);
   poi gira come nel passo 4. Una pull request verso `main` lancia `iris-pull-request`.

Questa parte **non è stata provata nel lab** (richiede la connessione GitHub): il percorso a mano
dei passi 1-9 è quello verificato.

## Se qualcosa non va

| Sintomo | Cosa controllare |
|---|---|
| `iris-cloudbuild ... does not have storage.objects.get` | manca l'accesso al sorgente: usa `--gcs-source-staging-dir` col bucket di Terraform |
| `BUILD FAILURE` al passo `test-*` | un test non passa: guarda il log del passo in Cronologia |
| Build fallita al deploy con `permission denied` | `iris-cloudbuild` deve avere `roles/run.admin` e `roles/iam.serviceAccountUser` su `iris-api` e `iris-trainer` (li crea Terraform) |
| Build fallita al push | `iris-cloudbuild` deve avere `roles/artifactregistry.writer` sul repository |
| `$SHORT_SHA` vuoto / tag uguale al lancio precedente | con il lancio a mano passalo tu in `--substitutions` e cambialo a ogni lancio |
| `403` o `Permission denied` su `gcloud builds submit` | l'utente deve poter usare `iris-cloudbuild` (`roles/iam.serviceAccountUser`) e avviare build (`roles/cloudbuild.builds.editor`) |
| Per Eventarc, trigger, modelli | vedi la tabella dell'esempio con le notifiche |

## Permessi GCP necessari

Chi lancia Terraform e `gcloud builds submit`: i ruoli dell'esempio con le notifiche, più
`roles/cloudbuild.builds.editor` (avviare le build). L'API `cloudbuild.googleapis.com` deve essere abilitata.

| Identità | Ruolo | Dove | Perché |
|---|---|---|---|
| `iris-cloudbuild` (esegue la pipeline) | `roles/artifactregistry.writer` | repository immagini | push delle immagini |
| `iris-cloudbuild` | `roles/run.admin` | progetto | distribuire i due servizi |
| `iris-cloudbuild` | `roles/iam.serviceAccountUser` | su `iris-api` e `iris-trainer` | Cloud Run richiede "act as" sull'identità dei servizi |
| `iris-cloudbuild` | `roles/logging.logWriter` | progetto | log della build in Cloud Logging |
| `iris-cloudbuild` | `roles/storage.objectViewer` | bucket | leggere il sorgente caricato con `gcloud builds submit` |

## Pulizia
```bash
gcloud eventarc triggers delete iris-new-file --location "$REGION"
gcloud run services delete iris-api iris-trainer --region "$REGION"
# se hai creato i trigger GitHub:  gcloud builds triggers delete iris-deploy iris-pull-request --region "$REGION"
cd terraform && terraform destroy -var "project_id=$PROJECT_ID" -var "region=$REGION" -var "enable_apis=false"
```
(le immagini in Artifact Registry e i file in `source/` del bucket vengono cancellati da `terraform destroy`).
