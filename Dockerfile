FROM python:3.10-slim

# Use a specific, lightweight Python version
# Minimal dependencies
RUN pip install --no-cache-dir \
    mlflow==2.3.1 \  # Specify exact version
    boto3

# Reduce MLflow workers and set conservative settings
ENV GUNICORN_WORKERS=2
ENV GUNICORN_THREADS=1

# Expose MLflow server port
EXPOSE 5000

# Lightweight entrypoint
ENTRYPOINT ["sh", "-c", \
    "mlflow server \
    --backend-store-uri sqlite:////app/mlflow.db \
    --default-artifact-root s3://${MLFLOW_ARTIFACTS_BUCKET}/mlruns \
    --host 0.0.0.0 \
    --port 5000 \
    --workers ${GUNICORN_WORKERS} \
    --worker-threads ${GUNICORN_THREADS}"]