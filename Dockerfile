FROM python:3.10-slim

# Minimize layer size and dependencies
RUN pip install --no-cache-dir \
    mlflow==2.3.1 \
    boto3 \
    && rm -rf /var/lib/apt/lists/* \
    && find /usr/local \
        $$ -type d -a -name test -o -name tests $$ \
        -o $$ -type f -a -name '*.pyc' -o -name '*.pyo' $$ \
        -exec rm -rf '{}' +

# Set conservative resource settings
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