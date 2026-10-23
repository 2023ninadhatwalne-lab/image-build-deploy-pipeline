#!/usr/bin/env bash
# ==============================================================================
# Script: manual_deploy.sh
# Purpose: Baseline measurement of the traditional manual deployment process.
#
# What this script does:
# 1. Starts a timer.
# 2. Builds the Docker image locally.
# 3. Tags the image with a manual version.
# 4. Loads the image directly into Minikube.
# 5. Applies Kubernetes manifests with the updated image.
# 6. Waits for Kubernetes rollout status to complete.
# 7. Stops the timer and prints total elapsed seconds.
# ==============================================================================

set -euo pipefail

# --- Command Autodetection (Ensures script runs on Linux, macOS, WSL, & Windows) ---
if command -v kubectl.exe >/dev/null 2>&1; then
    KUBECTL="kubectl.exe"
else
    KUBECTL="kubectl"
fi

if command -v minikube.exe >/dev/null 2>&1; then
    MINIKUBE="minikube.exe"
elif [ -f "/mnt/c/Program Files/Kubernetes/Minikube/minikube.exe" ]; then
    MINIKUBE="/mnt/c/Program Files/Kubernetes/Minikube/minikube.exe"
elif [ -f "/c/Program Files/Kubernetes/Minikube/minikube.exe" ]; then
    MINIKUBE="/c/Program Files/Kubernetes/Minikube/minikube.exe"
else
    MINIKUBE="minikube"
fi

if command -v docker.exe >/dev/null 2>&1; then
    DOCKER="docker.exe"
else
    DOCKER="docker"
fi

echo "=================================================================="
echo "    BASELINE TEST: MANUAL BUILD, LOAD, AND DEPLOYMENT"
echo "=================================================================="
echo "Starting deployment timer..."
START_TIME=$(date +%s)

# Step 1: Manual Docker Build & Tag
echo "[1/4] Building Docker image locally..."
IMAGE_TAG="manual-app:$(date +%s)"
"$DOCKER" build -t "$IMAGE_TAG" .

# Step 2: Load Image into Minikube cluster
echo "[2/4] Loading image into Minikube..."
"$MINIKUBE" image load "$IMAGE_TAG"

# Step 3: Apply manifests with the new image tag
echo "[3/4] Updating Deployment with new image tag..."
"$KUBECTL" apply -f k8s/service.yaml
# Replace placeholder with our manual image tag and apply
sed "s|IMAGE_TAG_PLACEHOLDER|$IMAGE_TAG|g" k8s/deployment.yaml | "$KUBECTL" apply -f -

# Step 4: Wait for the rolling update to complete
echo "[4/4] Waiting for rollout to complete..."
"$KUBECTL" rollout status deployment/app-deployment --timeout=90s

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "=================================================================="
echo " RESULT: Manual deployment finished successfully!"
echo " Total Elapsed Time: ${ELAPSED} seconds"
echo "=================================================================="
