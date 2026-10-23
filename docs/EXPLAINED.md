# Core DevOps Concepts Explained

Welcome to the project conceptual guide! This document explains the core engineering decisions behind our pipeline in plain English.

---

## 1. Why Git Commit SHA Tags Instead of `latest`?

In Docker, the `:latest` tag is a mutable pointer. It simply points to the most recent image built on a machine. Using `:latest` in production environments is considered an anti-pattern for several crucial reasons:

### A. Traceability (The Main Reason)
- When a pod in production reports an error or crash, tagging with the **Git commit SHA** (e.g. `ghcr.io/user/repo:7c9e12a...`) tells engineers the exact commit that produced that container.
- You can run `git checkout 7c9e12a` and immediately see the exact lines of code, commit message, author, and pull request.
- With `:latest`, nobody knows which commit is actually running on the cluster.

### B. Traceability vs. Reproducibility
It is important to understand the technical difference between these two concepts:
- **Traceability:** Being able to look at any running artifact and trace it directly back to its source code and author. Commit SHA tagging provides 100% traceability.
- **Reproducibility:** Being able to rebuild an image years later and produce the exact same binary output bit-for-bit. To achieve true reproducibility, an organization must pin base image digests (e.g. `python@sha256:...`), pin dependency versions down to their hashes, and lock compiler versions. SHA tags give us *traceability*, not automatic bit-for-bit reproducibility.

### C. Kubernetes Caching Hazards with `:latest`
- If you push a new image with `:latest`, Kubernetes may see that it already has an image named `:latest` cached on the node and skip pulling the new image!
- With immutable commit SHAs, the tag changes on every commit, forcing Kubernetes to pull and run the new version without ambiguity.

---

## 2. Continuous Delivery vs. Continuous Deployment

Many people use the terms "CD" interchangeably, but there is a major architectural difference:

```
                  ┌──────────────────────┐
                  │ Continuous Delivery  │
                  └──────────┬───────────┘
                             │
     [Build] ──> [Test] ──> [Deploy to Staging] ──> [HUMAN APPROVAL GATE] ──> [Deploy to Prod]
                                                            │
                                                            ▼ (Manual Click)

                  ┌────────────────────────┐
                  │ Continuous Deployment  │
                  └──────────┬─────────────┘
                             │
     [Build] ──> [Test] ──> [Deploy to Prod] ──> [AUTOMATED QUALITY GATE]
                                                        │
                                                        ▼ (ReadinessProbe: /health)
```

| Concept | Human Approval Required? | How Code Reaches Production |
| :--- | :---: | :--- |
| **Continuous Delivery** | **Yes** | The pipeline automatically builds and tests code, but a human engineer must click "Approve" or trigger a release to deploy to production. |
| **Continuous Deployment** | **No** | **Every commit pushed to the main branch is deployed to production automatically.** The only safety gates are automated tests and Kubernetes readiness probes. |

### Our Pipeline Architecture: Continuous DEPLOYMENT
In this project, our pipeline implements **Continuous Deployment**:
1. A developer pushes to `main` (the **ONLY** manual step).
2. The pipeline automatically builds and publishes the image.
3. The pipeline deploys to the Kubernetes cluster.
4. **The automated gate:** Kubernetes executes `readinessProbe` on `/health` and monitors `kubectl rollout status --timeout=60s`.
   - If `/health` passes: traffic smoothly shifts to the new pods.
   - If `/health` fails: rollout stalls, the CI job fails, and old pods keep serving traffic without human intervention.

---

## 3. Handling Secrets & Credentials Securely

Security is paramount in CI/CD pipelines. A single leaked credential can compromise an entire cloud infrastructure.

### The Golden Rule: Never Hardcode Secrets
- **Never put passwords, tokens, API keys, or private keys into source code, Dockerfiles, or Kubernetes manifests.**
- If you put a secret into a `Dockerfile`, it gets baked into the image layers. Anyone who pulls the image or runs `docker history` can inspect and steal the secret!
- If you commit secrets to Git, they remain forever in the Git history even if you delete them in a later commit.

### How We Handle Secrets Securely in This Project
1. **GitHub Automatic `GITHUB_TOKEN`:**
   - Instead of creating a personal access token (PAT) with broad permissions, our pipeline uses GitHub's built-in `GITHUB_TOKEN`.
   - It is created dynamically when the workflow starts, expires immediately when the workflow finishes, and is scoped strictly to the current repository.
2. **Principle of Least Privilege:**
   - We explicitly declare permissions in the workflow:
     ```yaml
     permissions:
       contents: read
       packages: write
     ```
   - The token can only read code and write packages to GHCR; it cannot alter organization settings, delete repos, or access unrelated repositories.
3. **Secret Separation in Kubernetes:**
   - In production, sensitive variables (database passwords, API tokens) are injected at runtime via **Kubernetes Secrets** or external secret vaults (such as HashiCorp Vault, AWS Secrets Manager, or Azure Key Vault).
   - The application receives secrets through mounted volumes or environment variables, keeping container images completely generic and reusable across environments (Dev, Staging, Prod).
