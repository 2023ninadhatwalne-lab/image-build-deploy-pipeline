# Automated Image Build and Deployment Pipeline

A complete university group project demonstrating modern, zero-downtime **Continuous Deployment** using Docker, Kubernetes (Minikube / kind), and GitHub Actions.

---

## 1. Project Overview

In this pipeline, **a Git push to the `main` branch is the ONLY manual action.** 

Once code is pushed:
1. GitHub Actions automatically builds the Docker image.
2. The image is tagged with the exact **Git commit SHA** (never `"latest"`) for 100% traceability.
3. The image is published to GitHub Container Registry (`ghcr.io`).
4. An ephemeral Kubernetes cluster (`kind`) deploys the updated image using a zero-downtime `RollingUpdate` strategy.
5. The Kubernetes `readinessProbe` serves as the **only quality gate**:
   - If `/health` returns HTTP 200: Traffic shifts and the pipeline turns green.
   - If `/health` fails: The rollout stalls, `kubectl rollout status` times out, the CI job fails, and old pods continue serving live traffic uninterrupted.

---

## 2. Repository Structure

```
├── .github/
│   └── workflows/
│       └── pipeline.yml          # GitHub Actions CI/CD workflow (Build, Tag, GHCR, kind deploy, Smoke test)
├── app/
│   ├── app.py                    # Flask application with "/" and "/health" endpoints
│   └── requirements.txt          # Python dependencies (Flask, Gunicorn)
├── docs/
│   ├── EXPLAINED.md              # Beginner explanations: SHA tagging, CD concepts, secret safety
│   └── RESULTS.md                # Benchmarks and experimental results table
├── k8s/
│   ├── deployment.yaml           # 2 replicas, RollingUpdate (maxUnavailable: 0, maxSurge: 1), health probes
│   └── service.yaml              # NodePort/ClusterIP service exposing port 80 -> container port 8080
├── scripts/
│   ├── failure_demo.sh           # Demonstrates failed release isolation while old pods continue serving
│   ├── manual_deploy.sh          # Baseline: times manual build, tag, cluster load, and deployment
│   ├── measure_build.sh          # Benchmarks Cold Build (--no-cache) vs. Warm-Cache Build
│   ├── rollback_timing.sh        # Measures speed of automated rollback (kubectl rollout undo)
│   └── zero_downtime_test.sh     # Sends continuous traffic (10 req/s) during rollout; asserts 0 failures
├── .dockerignore                 # Excludes unnecessary files from container build context
├── Dockerfile                    # Multi-layer slim Python image, non-root user, Gunicorn server
└── README.md                     # Complete project documentation and execution guide
```

---

## 3. Running Locally on Minikube

You can run and test every phase of this pipeline right on your local machine using Minikube and Bash.

### Prerequisites
Make sure your tools are running:
```bash
docker --version
minikube status
kubectl cluster-info
```

### Step 1: Run the Automated Measurement Scripts

All scripts are located in `/scripts` and are fully automated:

#### 1. Measure Docker Layer Caching Speedup
Compares how long it takes to build from scratch versus reusing cached layers:
```bash
bash scripts/measure_build.sh
```

#### 2. Run the Baseline Manual Deployment
Times a complete manual build, image load into Minikube, and deployment:
```bash
bash scripts/manual_deploy.sh
```

#### 3. Test Zero-Downtime Rolling Updates
Sends continuous HTTP traffic (~10 requests/second) while triggering a rolling update, proving **0 dropped requests**:
```bash
bash scripts/zero_downtime_test.sh
```

#### 4. Demonstrate Failure Protection (Broken Release Simulation)
Deploys a deliberately broken container (where `/health` returns HTTP 500), showing that:
- The new pod fails the readiness probe.
- The rollout stalls and times out.
- Existing old pods continue serving 100% of user traffic without interruption.
- Automatically rolls back to restore healthy cluster state.
```bash
bash scripts/failure_demo.sh
```

#### 5. Measure Rollback Timing
Measures the duration of an automated rollback (`kubectl rollout undo`) to verify it takes under 30 seconds:
```bash
bash scripts/rollback_timing.sh
```

---

## 4. How to Connect to GitHub & Run the Pipeline

Follow these exact steps to push this project to your own GitHub account and let GitHub Actions run the pipeline:

### Step 1: Create a New GitHub Repository
1. Open [GitHub](https://github.com/new).
2. Name your repository (e.g., `image-build-deploy-pipeline`).
3. Choose **Public** (recommended so GHCR container packages are visible).
4. Do **not** initialize with a README, .gitignore, or license (we already have them).
5. Click **Create repository**.

### Step 2: Configure Package Permissions in GitHub Actions
To allow the pipeline to write images to GitHub Container Registry (GHCR):
1. In your GitHub repository, go to **Settings** > **Actions** > **General**.
2. Scroll down to **Workflow permissions**.
3. Select **Read and write permissions**.
4. Check the box **Allow GitHub Actions to create and approve pull requests**.
5. Click **Save**.

### Step 3: Commit and Push Your Code
Open your terminal in this directory and run:

```bash
# Add all files to git tracking
git add .

# Create the initial commit
git commit -m "feat: complete automated image build and deployment pipeline"

# Link your local repository to your GitHub repository
# Replace YOUR_USERNAME with your GitHub username:
git remote add origin https://github.com/YOUR_USERNAME/image-build-deploy-pipeline.git

# Push your code to the main branch
git push -u origin main
```

### Step 4: Watch the Pipeline Execute
1. Go to your GitHub repository and click the **Actions** tab.
2. You will see **Automated Build & Deploy Pipeline** running.
3. Click into the run to watch:
   - **Job 1 (`build-and-push`)**: Logs in to GHCR, builds with Docker Buildx, tags with your commit SHA, and pushes to `ghcr.io`.
   - **Job 2 (`deploy`)**: Creates a `kind` cluster inside the CI runner, pulls and preloads the SHA image, applies the manifests with `sed`, enforces `kubectl rollout status --timeout=60s`, and executes the live smoke test via `curl`.
