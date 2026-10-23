#!/usr/bin/env bash
# ==============================================================================
# Script: rollback_timing.sh
# Purpose: Measures the exact time taken to execute an automated rollback
#          using 'kubectl rollout undo'.
#
# Target: Under 30 seconds.
#
# Why Rollback Speed Matters:
# When an incident or bad configuration occurs in production, automated or
# immediate rollback allows returning to the known-good state in seconds,
# minimizing Mean Time To Recovery (MTTR).
# ==============================================================================

set -euo pipefail

# Command Autodetection
if command -v kubectl.exe >/dev/null 2>&1; then
    KUBECTL="kubectl.exe"
else
    KUBECTL="kubectl"
fi

echo "=================================================================="
echo "    BENCHMARK: AUTOMATED ROLLBACK TIMING"
echo "=================================================================="

# Ensure there is a preceding revision to undo to
echo "[1/3] Preparing deployment revision for rollback measurement..."
"$KUBECTL" set env deployment/app-deployment ROLLBACK_TEST_TAG="$(date +%s)"
"$KUBECTL" rollout status deployment/app-deployment --timeout=60s >/dev/null

echo "[2/3] Initiating rollback via 'kubectl rollout undo'..."
START_TIME=$(date +%s)

# Execute the rollback
"$KUBECTL" rollout undo deployment/app-deployment

# Await completion of rollback
echo "Waiting for rollback status..."
"$KUBECTL" rollout status deployment/app-deployment --timeout=60s

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "=================================================================="
echo " ROLLBACK TIMING RESULTS"
echo "=================================================================="
echo " Rollback Duration : ${ELAPSED} seconds"
echo " Target Threshold  : Under 30 seconds"

if [ "$ELAPSED" -le 30 ]; then
    echo " STATUS: PASSED! Rollback completed in ${ELAPSED}s (well within the 30s target)."
else
    echo " STATUS: WARNING: Rollback took ${ELAPSED}s (>30s)."
fi
echo "=================================================================="
