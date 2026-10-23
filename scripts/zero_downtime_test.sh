#!/usr/bin/env bash
# ==============================================================================
# Script: zero_downtime_test.sh
# Purpose: Validates that Kubernetes RollingUpdate with maxUnavailable: 0
#          and readiness probes achieves true ZERO DOWNTIME during rollouts.
#
# Methodology:
# 1. Opens a background port-forward to the app-service.
# 2. Triggers a live rolling update on the deployment.
# 3. Bombards the service with continuous HTTP requests (~10 requests/sec).
# 4. Logs any failed HTTP requests (status != 200).
# 5. Awaits rollout completion and computes the success percentage.
# Expected Result: 0 failed requests (100% availability).
# ==============================================================================

set -euo pipefail

# Command Autodetection
if command -v kubectl.exe >/dev/null 2>&1; then
    KUBECTL="kubectl.exe"
else
    KUBECTL="kubectl"
fi

if command -v curl.exe >/dev/null 2>&1; then
    CURL="curl.exe"
    DEV_NULL="nul"
else
    CURL="curl"
    DEV_NULL="/dev/null"
fi

TEST_PORT=8085
TARGET_URL="http://127.0.0.1:${TEST_PORT}/"

get_http_code() {
    "$CURL" -s -o "$DEV_NULL" -w "%{http_code}" --max-time 2 "$TARGET_URL" 2>/dev/null | tr -d '\r\n' || echo "000"
}

echo "=================================================================="
echo "    ZERO-DOWNTIME ROLLING UPDATE TEST"
echo "=================================================================="

# Step 1: Forward port in background
echo "[1/4] Establishing port-forward to app-service on port ${TEST_PORT}..."
"$KUBECTL" port-forward svc/app-service "${TEST_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!

cleanup() {
    echo "Cleaning up port-forward process (PID ${PF_PID})..."
    kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Allow port-forward 3 seconds to establish connection
sleep 3

# Verify initial connectivity
echo "[2/4] Verifying initial service connectivity..."
INITIAL_STATUS=$(get_http_code)
if [ "$INITIAL_STATUS" != "200" ]; then
    echo "ERROR: Unable to connect to service at ${TARGET_URL}. Received HTTP ${INITIAL_STATUS}."
    exit 1
fi
echo "Service is healthy and responding with HTTP 200."

# Step 2: Trigger a live rolling update by updating the APP_VERSION environment variable
NEW_VERSION="v-rolling-$(date +%s)"
echo "[3/4] Triggering rolling update to version: ${NEW_VERSION}..."
"$KUBECTL" set env deployment/app-deployment APP_VERSION="$NEW_VERSION"

# Step 3: Send continuous requests while rollout is progressing
echo "[4/4] Sending continuous HTTP requests (~10 req/sec) during update..."
TOTAL_REQUESTS=0
SUCCESS_COUNT=0
FAILURE_COUNT=0

# Loop for ~15 seconds while Kubernetes performs the rolling update
END_TIME=$((SECONDS + 15))
while [ $SECONDS -lt $END_TIME ]; do
    HTTP_CODE=$(get_http_code)
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))

    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "  [DROP DETECTED] Request #$TOTAL_REQUESTS received HTTP status: $HTTP_CODE"
    fi

    # Small pause ~0.1s to achieve approximately 10 requests per second
    sleep 0.1
done

# Wait for Kubernetes to finalize rollout
echo "Waiting for Kubernetes to finish rollout..."
"$KUBECTL" rollout status deployment/app-deployment --timeout=60s

echo "=================================================================="
echo " ZERO-DOWNTIME TEST RESULTS"
echo "=================================================================="
echo " Total Requests Sent   : $TOTAL_REQUESTS"
echo " Successful (HTTP 200) : $SUCCESS_COUNT"
echo " Failed (Downtime)     : $FAILURE_COUNT"

if [ "$FAILURE_COUNT" -eq 0 ]; then
    echo " STATUS: PASSED! Zero dropped requests (100% availability during rollout)."
else
    echo " STATUS: FAILED! $FAILURE_COUNT requests were dropped during rollout."
fi
echo "=================================================================="
