#!/usr/bin/env bash
# ==============================================================================
# Script: measure_build.sh
# Purpose: Compares Docker build times between a Cold Build (no cache)
#          and a Warm Build (leveraging Docker layer caching).
#
# Educational Note:
# In our Dockerfile, we copy and install 'requirements.txt' BEFORE copying
# the rest of the application code. This ensures that when application code
# changes, Docker reuses the cached dependencies layer rather than
# downloading and installing them again from PyPI.
# ==============================================================================

set -euo pipefail

# Command Autodetection
if command -v docker.exe >/dev/null 2>&1; then
    DOCKER="docker.exe"
else
    DOCKER="docker"
fi

echo "=================================================================="
echo "    BENCHMARK: COLD BUILD VS. WARM-CACHE BUILD DURATION"
echo "=================================================================="

# ------------------------------------------------------------------------------
# Test 1: Cold Build (Docker cache is completely bypassed using --no-cache)
# ------------------------------------------------------------------------------
echo ">>> Running Cold Build (Bypassing cache with --no-cache)..."
COLD_START=$(date +%s)
"$DOCKER" build --no-cache -t benchmark-app:cold . > /dev/null
COLD_END=$(date +%s)
COLD_DURATION=$((COLD_END - COLD_START))
echo "Cold Build completed in: ${COLD_DURATION} seconds"

# ------------------------------------------------------------------------------
# Test 2: Warm Build (Docker reuses cached layers)
# ------------------------------------------------------------------------------
echo ">>> Running Warm-Cache Build (Reusing cached dependency layers)..."
WARM_START=$(date +%s)
"$DOCKER" build -t benchmark-app:warm . > /dev/null
WARM_END=$(date +%s)
WARM_DURATION=$((WARM_END - WARM_START))
echo "Warm Build completed in: ${WARM_DURATION} seconds"

# ------------------------------------------------------------------------------
# Results Summary
# ------------------------------------------------------------------------------
echo "=================================================================="
echo " BUILD MEASUREMENT RESULTS"
echo "=================================================================="
printf "%-25s | %-15s\n" "Build Strategy" "Time Taken (s)"
echo "--------------------------+----------------"
printf "%-25s | %-15s\n" "Cold Build (--no-cache)" "${COLD_DURATION}s"
printf "%-25s | %-15s\n" "Warm Build (Cached)" "${WARM_DURATION}s"
echo "=================================================================="
if [ "$WARM_DURATION" -gt 0 ]; then
    SPEEDUP=$((COLD_DURATION / (WARM_DURATION > 0 ? WARM_DURATION : 1)))
    echo "Layer caching provided an approximately ${SPEEDUP}x speedup!"
else
    echo "Warm build took under 1 second!"
fi
echo "=================================================================="
