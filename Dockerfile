FROM python:3.9-slim

# Install MLflow and boto3 for S3
RUN pip install --no-cache-dir \
    mlflow \
    boto3

# Create the directory for SQLite database and set permissions
RUN mkdir -p /app/mlflow && \
    chmod -R 777 /app/mlflow

# Expose MLflow server port
EXPOSE 5000

# Entrypoint that uses environment variable for S3 bucket
ENTRYPOINT ["sh", "-c", \
    "mlflow server \
    --backend-store-uri sqlite:////app/mlflow/mlflow.db \
    --default-artifact-root s3://${MLFLOW_ARTIFACTS_BUCKET}/mlruns \
    --host 0.0.0.0 \
    --port 5000"]
