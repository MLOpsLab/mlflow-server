#!/bin/bash

# Set S3 tracking URI directly in the startup script
# Use environment variable for flexibility
MLFLOW_TRACKING_URI="s3://${MLFLOW_ARTIFACTS_BUCKET}/mlruns"

# MLflow Server Startup
mlflow server \
    --backend-store-uri sqlite:////app/mlflow.db \
    --default-artifact-root "${MLFLOW_TRACKING_URI}" \
    --host 0.0.0.0 \
    --port 5000