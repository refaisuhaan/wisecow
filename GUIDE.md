# AccuKnox DevOps Trainee Assessment — Step-by-Step Guide

This guide walks through all three problem statements end to end, using the
files in this project. Do the steps **in order** — later steps assume
earlier ones are done.

Tools you'll need installed locally: `git`, `docker`, `kubectl`, `kind` (or
`minikube`), `helm`.

---

## PS1 — Containerize & Deploy Wisecow

### Step 1: Fork and clone the real wisecow repo

1. Go to https://github.com/nyrahul/wisecow and click **Fork**.
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/wisecow.git
   cd wisecow
   ```
3. Copy every file from this project (`Dockerfile`, `k8s/`,
   `.github/workflows/ci-cd.yaml`, `scripts/`, `kubearmor/`, this
   `GUIDE.md`) into that cloned folder, sitting alongside the existing
   `wisecow.sh`, `README.md`, `LICENSE`.
4. Delete `wisecow.sh.README.txt` — you already have the real `wisecow.sh`
   from the fork.
5. Commit and push:
   ```bash
   git add .
   git commit -m "Add Dockerfile, k8s manifests, CI/CD, TLS, scripts, KubeArmor policy"
   git push origin main
   ```
6. Make sure the repo visibility matches what your assessment sheet
   actually asks for (the version of this instructions you were given says
   **public**; the original repo's own README says private with access for
   `nyrahul` — when in doubt, do both: keep it public AND add `nyrahul` as
   a collaborator, so you satisfy either reading).

### Step 2: Build the Docker image locally and test it

```bash
docker build -t wisecow:local .
docker run -d -p 4499:4499 --name wisecow-test wisecow:local
# In another terminal:
curl http://localhost:4499
# You should see cowsay ASCII art with a fortune quote in the response body.
docker rm -f wisecow-test
```

### Step 3: Push the image to a registry manually (first time)

Create a free Docker Hub account if you don't have one, then:

```bash
docker login
docker tag wisecow:local <dockerhub-username>/wisecow:latest
docker push <dockerhub-username>/wisecow:latest
```

Edit `k8s/01-deployment.yaml` and replace
`<DOCKERHUB_USERNAME>/wisecow:latest` with your actual image.

### Step 4: Create a local Kubernetes cluster

```bash
kind create cluster --name wisecow-cluster
# or: minikube start
kubectl cluster-info
```

### Step 5: Install an Ingress controller (needed for TLS routing)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```
(If using Minikube instead of Kind: `minikube addons enable ingress`.)

### Step 6: Install cert-manager (needed for TLS certificates)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s
```

### Step 7: Deploy Wisecow

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-deployment.yaml
kubectl apply -f k8s/02-service.yaml
kubectl apply -f k8s/03-certificate.yaml
kubectl apply -f k8s/04-ingress.yaml

kubectl get pods -n wisecow
kubectl get certificate -n wisecow      # should show READY=True after ~1 min
kubectl get ingress -n wisecow
```

### Step 8: Test TLS access

```bash
# Map the hostname to your cluster (Kind on Docker Desktop = localhost)
echo "127.0.0.1 wisecow.local" | sudo tee -a /etc/hosts

curl -k https://wisecow.local
```
`-k` is needed because it's a self-signed cert for this local demo — that's
expected and fine for the assessment. (For a real domain + public cluster,
swap the `ClusterIssuer` in `k8s/03-certificate.yaml` for a Let's Encrypt
ACME issuer instead of `selfSigned`, and you won't need `-k`.)

### Step 9: Set up GitHub Actions CI/CD

1. In your GitHub repo, go to **Settings → Secrets and variables →
   Actions** and add:
   - `DOCKERHUB_USERNAME` — your Docker Hub username
   - `DOCKERHUB_TOKEN` — a Docker Hub access token (Docker Hub →
     Account Settings → Security → New Access Token)
   - `KUBE_CONFIG` — base64 of a kubeconfig that can reach your cluster:
     ```bash
     cat ~/.kube/config | base64 -w0
     ```
     Paste that whole string as the secret value.

2. **Important limitation:** GitHub-hosted runners run in GitHub's cloud
   and cannot reach a `kind`/`minikube` cluster on your laptop. For the
   Continuous Deployment step to actually work against a local cluster,
   register a **self-hosted runner** on the same machine as your cluster:
   - Repo → Settings → Actions → Runners → New self-hosted runner →
     follow the on-screen `./config.sh` / `./run.sh` instructions.
   - Then change `runs-on: ubuntu-latest` to `runs-on: self-hosted` in the
     `deploy` job of `.github/workflows/ci-cd.yaml`.
   - Alternative: point `KUBE_CONFIG` at a real cloud cluster (e.g. a free
     tier on a managed K8s service) so a normal GitHub-hosted runner can
     reach it over the internet — no self-hosted runner needed.

3. Commit any small change and push to `main` — watch the **Actions** tab.
   The `build-and-push` job should build and push a new image tag; the
   `deploy` job should run `kubectl set image` against your cluster.

---

## PS2 — Two Automation Scripts

You only need to pick **two**. This project includes:

### Option 1: System Health Monitoring (`scripts/health_monitor.sh`)

```bash
chmod +x scripts/health_monitor.sh
./scripts/health_monitor.sh              # one-off check, prints + logs
./scripts/health_monitor.sh --watch 60   # loop every 60s
```
Checks CPU / memory / disk / process-count against thresholds (env vars
`CPU_THRESHOLD`, `MEM_THRESHOLD`, `DISK_THRESHOLD`, `PROC_THRESHOLD`,
default 80% / 80% / 80% / 300 processes) and logs `[ALERT]` or `[OK]` lines
to console + `/var/log/health_monitor.log` (or `./health_monitor.log` if
that's not writable).

### Option 4: Application Health Checker (`scripts/app_health_checker.py`)

```bash
python3 scripts/app_health_checker.py --url https://wisecow.local --url https://google.com
python3 scripts/app_health_checker.py --url https://wisecow.local --watch 30 --log app_health.log
```
Classifies each URL as `UP` (HTTP 200-399) or `DOWN` (timeout, connection
error, or HTTP ≥ 400), logs the HTTP code and response latency, and exits
non-zero if anything is down — so you can wire it into cron or CI as a
smoke test.

---

## PS3 — KubeArmor Zero-Trust Policy (Optional / Bonus)

### Step 1: Install KubeArmor

```bash
curl -sfL https://raw.githubusercontent.com/kubearmor/KubeArmor/main/getting-started/deploy_kubearmor.sh | sh -s -- install
# or with the karmor CLI:
curl -sfL https://raw.githubusercontent.com/kubearmor/kubearmor-client/main/install.sh | sh -s -- -b /usr/local/bin
karmor install
```
Verify:
```bash
kubectl get pods -n kubearmor
```

### Step 2: Apply the zero-trust policy

```bash
kubectl apply -f kubearmor/wisecow-policy.yaml
kubectl get kubearmorpolicy -n wisecow
```

### Step 3: Trigger and capture a policy violation

```bash
POD=$(kubectl get pod -n wisecow -l app=wisecow -o jsonpath='{.items[0].metadata.name}')

# This should be BLOCKED by wisecow-block-highrisk-binaries:
kubectl exec -it -n wisecow "$POD" -- apt-get update
kubectl exec -it -n wisecow "$POD" -- /bin/sh -c "echo blocked-shell-test"
```
In another terminal, tail live violation logs:
```bash
karmor logs -n wisecow
# or:
kubectl logs -n kubearmor -l kubearmor-app=kubearmor-relay -f
```
Take a screenshot of the terminal showing the `Permission denied` /
blocked-exec result **and** the corresponding `Blocked` entry in the
KubeArmor log output. Save it as `kubearmor/violation-screenshot.png`.

### Step 4: Commit

```bash
git add kubearmor/wisecow-policy.yaml kubearmor/violation-screenshot.png
git commit -m "Add KubeArmor zero-trust policy and violation screenshot"
git push
```

---

## Final Checklist Before Submitting

- [ ] Repo contains: `wisecow.sh` (real one), `Dockerfile`, `k8s/*.yaml`,
      `.github/workflows/ci-cd.yaml`
- [ ] Docker image builds and runs locally, serves cowsay+fortune on 4499
- [ ] Deployment + Service applied and pods are `Running`
- [ ] Ingress + Certificate give TLS access (even if self-signed for a demo)
- [ ] GitHub Actions workflow runs on push: builds, pushes image, and
      (bonus) deploys
- [ ] Two PS2 scripts present and tested (`scripts/health_monitor.sh`,
      `scripts/app_health_checker.py`)
- [ ] (Bonus) `kubearmor/wisecow-policy.yaml` applied + violation
      screenshot committed
- [ ] Repo visibility set as instructed; fill out the Google Form with
      repo link, your details, etc.
