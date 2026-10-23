#!/usr/bin/env bash
# ==============================================================================
# Script: failure_demo.sh
# Purpose: Demonstrates how the Kubernetes readinessProbe acts as an automated
#          safety gate, preventing broken releases from impacting live users.
#
# Educational Scenario:
# 1. A developer commits code that breaks the '/health' endpoint (returns HTTP 500).
# 2. Kubernetes starts 1 new pod (due to maxSurge: 1).
# 3. The readiness probe fails against the new pod.
# 4. Because maxUnavailable: 0, Kubernetes REFUSES to terminate the old healthy pods.
# 5. 'kubectl rollout status' times out (simulating CI failure).
# 6. Live user requests continue to be served by the OLD pods without downtime!
# 7. We roll back to restore the clean state.
# ==============================================================================

set -euo pipefail

# Command Autodetection
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

if command -v curl.exe >/dev/null 2>&1; then
    CURL="curl.exe"
    DEV_NULL="nul"
else
    CURL="curl"
    DEV_NULL="/dev/null"
fi

DEMO_PORT=8086
TARGET_URL="http://127.0.0.1:${DEMO_PORT}/"

get_http_code() {
    "$CURL" -s -o "$DEV_NULL" -w "%{http_code}" --max-time 2 "$TARGET_URL" 2>/dev/null | tr -d '\r\n' || echo "000"
}

get_http_body() {
    "$CURL" -s --max-time 2 "$TARGET_URL" 2>/dev/null | tr -d '\r' || echo "Failed to reach endpoint"
}

echo "=================================================================="
echo "    FAILURE DEMO: BROKEN IMAGE ROLLOUT PREVENTION"
echo "=================================================================="

# Step 1: Establish port-forward to test traffic
echo "[1/6] Opening port-forward to app-service on port ${DEMO_PORT}..."
"$KUBECTL" port-forward svc/app-service "${DEMO_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!

cleanup() {
    echo "Cleaning up background port-forward (PID ${PF_PID})..."
    kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 3

# Verify initial baseline
BASELINE_STATUS=$(get_http_code)
echo "Initial Service Status: HTTP $BASELINE_STATUS (Old pods serving traffic)"

# Step 2: Build broken Docker image (FAIL_HEALTH=true causes /health to return 500)
echo "[2/6] Building deliberately broken image (test-app:broken)..."
cat << 'EOF' > Dockerfile.broken
FROM python:3.12-slim
WORKDIR /app
ENV FAIL_HEALTH=true APP_VERSION=broken-v-bad
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
EOF

"$DOCKER" build -t test-app:broken -f Dockerfile.broken . >/dev/null
rm -f Dockerfile.broken

echo "[3/6] Preloading broken image into Minikube..."
"$MINIKUBE" image load test-app:broken

# Step 3: Deploy the broken image
echo "[4/6] Updating deployment to use broken image 'test-app:broken'..."
"$KUBECTL" set image deployment/app-deployment app=test-app:broken

# Step 4: Monitor the rollout status with a short timeout
echo "[5/6] Watching rollout status (Expect timeout!)..."
set +e
"$KUBECTL" rollout status deployment/app-deployment --timeout=15s
ROLLOUT_EXIT_CODE=$?
set -e

if [ $ROLLOUT_EXIT_CODE -ne 0 ]; then
    echo ">>> CONFIRMED: Rollout timed out and stalled as expected!"
else
    echo ">>> UNEXPECTED: Rollout succeeded when it should have stalled."
fi

# Step 5: Check pod statuses and prove old pods are still serving
echo "------------------------------------------------------------------"
echo "Current Pod States in Cluster:"
"$KUBECTL" get pods -l app=demo-app
echo "------------------------------------------------------------------"
echo "Notice that the new broken pod is NOT Ready (0/1 READY)."
echo "Testing live user endpoint during the stalled rollout:"
LIVE_RESPONSE=$(get_http_body)
echo "Response received: $LIVE_RESPONSE"

LIVE_CODE=$(get_http_code)
if [ "$LIVE_CODE" = "200" ]; then
    echo "=================================================================="
    echo " SUCCESS: Traffic continues to be served 100% by the OLD pods!"
    echo " The broken deployment was completely blocked by Kubernetes."
    echo "=================================================================="
fi

# Step 6: Rollback deployment to healthy state
echo "[6/6] Rolling back deployment to recover healthy cluster state..."
"$KUBECTL" rollout undo deployment/app-deployment
"$KUBECTL" rollout status deployment/app-deployment --timeout=60s
echo "Cluster successfully recovered to healthy state."
echo "=================================================================="
