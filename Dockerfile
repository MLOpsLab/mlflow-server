FROM python:3.10-slim

# Install minimal dependencies
RUN pip install --no-cache-dir \
    mlflow \
    boto3

# Set environment variables for Gunicorn
ENV GUNICORN_WORKERS=2
ENV GUNICORN_THREADS=1

# Expose MLflow server port
EXPOSE 5000

# Lightweight entrypoint with controlled workers
ENTRYPOINT ["sh", "-c", \
    "mlflow server \
    --backend-store-uri sqlite:////app/mlflow.db \
    --default-artifact-root s3://${MLFLOW_ARTIFACTS_BUCKET}/mlruns \
    --host 0.0.0.0 \
    --port 5000 \
    --workers 2 \
    --worker-threads 1"]