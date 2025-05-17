FROM python:3.9-slim

# Install MLflow
RUN pip install --no-cache-dir mlflow gunicorn

# Create working directory
WORKDIR /mlflow

# Expose port
EXPOSE 5000

# CMD must be a proper JSON array, lowercase args!
CMD ["mlflow", "server", \
     "--backend-store-uri", "sqlite:///mlflow.db", \
     "--default-artifact-root", "/mlflow/mlruns", \
     "--host", "0.0.0.0", \
     "--port", "5000"]
