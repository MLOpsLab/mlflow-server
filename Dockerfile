FROM python:3.10-slim

# Install dependencies
RUN pip install mlflow boto3 psycopg2-binary

WORKDIR /app

# Copy any startup scripts
COPY start-mlflow.sh /app/start-mlflow.sh
RUN chmod +x /app/start-mlflow.sh

EXPOSE 5000

# Use the startup script as entrypoint
ENTRYPOINT ["/app/start-mlflow.sh"]