# Run MLflow server

rm -rf mlruns mlflow.db
mlflow server --backend-store-uri sqlite:///mlflow.db --default-artifact-root ./mlruns

# Build and Run docker image

docker build -t mlflow-server . && docker run --network mlflow-net -d --name mlflow-server -p 5000:5000 -v "D:/mlflow/mlruns:/mlflow/mlruns" mlflow-server
