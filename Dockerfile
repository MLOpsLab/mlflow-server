FROM python:3.10-slim

# Minimize layers and use slim image
RUN pip install --no-cache-dir \
    mlflow==2.3.1 \
    boto3 \
    # Remove unnecessary dependencies
    && rm -rf /var/lib/apt/lists/* \
    && find /usr/local \
        $$ -type d -a -name test -o -name tests $$ \
        -o $$ -type f -a -name '*.pyc' -o -name '*.pyo' $$ \
        -exec rm -rf '{}' +

# Expose MLflow server port
EXPOSE 5000

# Lightweight entrypoint
ENTRYPOINT ["sh", "-c", \
    "mlflow server \
    --backend-store-uri sqlite:////app/mlflow.db \
    --default-artifact-root s3://${MLFLOW_ARTIFACTS_BUCKET}/mlruns \
    --host 0.0.0.0 \
    --port 5000"]