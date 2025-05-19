FROM python:3.10-slim

# Install dependencies
RUN pip install mlflow boto3

# Expose the port in the Docker image (not in the container command)
EXPOSE 5000

# Command to run the MLflow server
CMD ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000"]
