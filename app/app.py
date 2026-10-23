"""
==============================================================================
Application Name: Automated Image Build & Deployment Pipeline Demo App
Description: A simple, production-grade Flask web application designed for
             demonstrating zero-downtime rolling updates in Kubernetes.
Endpoints:
  - "/"       : Returns a greeting message along with the current APP_VERSION.
  - "/health" : Returns HTTP 200 OK for Kubernetes readiness and liveness probes.
==============================================================================
"""

import os
from flask import Flask, jsonify

# Initialize the Flask web application instance
app = Flask(__name__)

# Read the application version from the environment variable 'APP_VERSION'.
# If 'APP_VERSION' is not set in the environment, default to 'v1'.
# When deploying new versions, Kubernetes will pass APP_VERSION="v2", "v3", etc.
APP_VERSION = os.getenv("APP_VERSION", "v1")


@app.route("/", methods=["GET"])
def index():
    """
    Root endpoint:
    Returns a welcoming message and the active application version.
    This allows us to visually verify which version of the container is handling requests.
    """
    return jsonify({
        "status": "success",
        "message": "Automated Image Build and Deployment Pipeline is operational!",
        "version": APP_VERSION
    }), 200


@app.route("/health", methods=["GET"])
def health():
    """
    Health check endpoint:
    Kubernetes uses this endpoint for its 'readinessProbe' and 'livenessProbe'.
    - If this returns HTTP 200: Kubernetes knows the pod is ready to accept traffic.
    - If this returns an error (e.g., 500) or fails to respond: Kubernetes will NOT
      route traffic to this pod, preventing broken rollouts.
    - If the FAIL_HEALTH environment variable is set to 'true', it simulates a broken
      version to demonstrate how Kubernetes prevents bad deployments.
    """
    if os.getenv("FAIL_HEALTH", "false").lower() == "true":
        return jsonify({
            "status": "unhealthy",
            "error": "Simulated failure: Health check failed!",
            "version": APP_VERSION
        }), 500

    return jsonify({
        "status": "healthy",
        "version": APP_VERSION
    }), 200


if __name__ == "__main__":
    # When running directly for local development (not via Gunicorn)
    # Listens on all network interfaces (0.0.0.0) at port 8080.
    app.run(host="0.0.0.0", port=8080)
