#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# #############################################################################
# MLflow Server Setup Script for EC2 (SQLite Backend + S3 Artifacts)
#
# This script is intended to be run on an EC2 instance.
# It sets up an MLflow tracking server using:
#   - SQLite for the metadata backend (local file `mlflow.db`).
#   - S3 for the artifact store.
#
# PREREQUISITES (Manual AWS Setup Required before running script via GitHub Actions or manually):
# 1. EC2 Instance launched (Amazon Linux 2 or Ubuntu recommended).
# 2. IAM Role with S3 read/write permissions (for the specified MLFLOW_S3_BUCKET_NAME) attached to EC2.
# 3. S3 Bucket created for MLflow artifacts.
# 4. EC2 Security Group configured to allow inbound traffic on MLFLOW_SERVER_PORT (default 5000)
#    and SSH (port 22).
# #############################################################################

# --- Configuration ---
# S3 Bucket Name: This is expected to be set by the `MLFLOW_S3_BUCKET_NAME_ENV` environment variable.
# If the environment variable is not set, the script will use the placeholder and likely fail validation.
MLFLOW_S3_BUCKET_NAME="${MLFLOW_S3_BUCKET_NAME_ENV:-your-s3-bucket-name-placeholder}"

# Optional: You can change these if needed, but ensure consistency with any calling scripts/workflows.
MLFLOW_SERVER_PORT="${MLFLOW_SERVER_PORT_ENV:-5000}" # Allow overriding port via env var
MLFLOW_HOST="0.0.0.0" # Listen on all interfaces for external access
MLFLOW_DATA_DIR="$HOME/mlflow_server_data" # Directory to store mlflow.db and logs
MLFLOW_USER=$(whoami)
MLFLOW_LOG_FILE="$MLFLOW_DATA_DIR/mlflow_server.log"
MLFLOW_DB_FILE="mlflow.db" # Will be created in $MLFLOW_DATA_DIR

# --- Script Start ---
echo "=================================================="
echo "Starting MLflow Server Setup..."
echo "=================================================="
echo ""

# --- Configuration Validation ---
echo "Validating Configuration..."
if [ "$MLFLOW_S3_BUCKET_NAME" == "your-s3-bucket-name-placeholder" ] || [ -z "$MLFLOW_S3_BUCKET_NAME" ]; then
    echo "ERROR: MLFLOW_S3_BUCKET_NAME is not set correctly."
    echo "       It should be passed as an environment variable (MLFLOW_S3_BUCKET_NAME_ENV)."
    echo "       Current value: '$MLFLOW_S3_BUCKET_NAME'"
    exit 1
fi

# Ensure S3 bucket name has s3:// prefix for MLflow command
if [[ ! "$MLFLOW_S3_BUCKET_NAME" == s3://* ]]; then
    MLFLOW_S3_ARTIFACT_ROOT="s3://${MLFLOW_S3_BUCKET_NAME}"
else
    MLFLOW_S3_ARTIFACT_ROOT="${MLFLOW_S3_BUCKET_NAME}"
fi
echo "  User: $MLFLOW_USER"
echo "  MLflow Data Directory: $MLFLOW_DATA_DIR"
echo "  MLflow SQLite DB: $MLFLOW_DATA_DIR/$MLFLOW_DB_FILE"
echo "  MLflow S3 Artifact Root: $MLFLOW_S3_ARTIFACT_ROOT"
echo "  MLflow Server Port: $MLFLOW_SERVER_PORT"
echo "  MLFLOW_HOST: $MLFLOW_HOST"
echo "  MLflow Log File: $MLFLOW_LOG_FILE"
echo "--------------------------------------------------"

# --- 1. OS Detection and Package Installation ---
echo "STEP 1: Detecting OS and installing prerequisites..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
else
    echo "ERROR: Cannot determine OS type."
    exit 1
fi

if [[ "$OS_NAME" == "Amazon Linux" ]]; then
    echo "Detected Amazon Linux."
    sudo yum update -y
    sudo yum install python3 python3-pip git -y
elif [[ "$OS_NAME" == "Ubuntu" ]]; then
    echo "Detected Ubuntu."
    sudo apt-get update # Use apt-get for wider compatibility in scripts
    sudo apt-get install -y python3 python3-pip git
else
    echo "ERROR: Unsupported OS: $OS_NAME. This script supports Amazon Linux and Ubuntu."
    exit 1
fi
echo "Prerequisites installed successfully."
echo "--------------------------------------------------"

# --- 2. Install MLflow and Boto3 ---
echo "STEP 2: Installing MLflow and Boto3 using pip3..."
# Use --user to install in user's home directory, avoiding sudo pip
# Use --no-cache-dir to ensure fresh install, good for CI
pip3 install --no-cache-dir --user mlflow boto3

# Add ~/.local/bin to PATH if not already present for the current session and .bashrc/.bash_profile
LOCAL_BIN_PATH="$HOME/.local/bin"
if [[ ":$PATH:" != *":$LOCAL_BIN_PATH:"* ]]; then
    echo "Adding $LOCAL_BIN_PATH to PATH for current session..."
    export PATH="$LOCAL_BIN_PATH:$PATH"

    # Persist for future sessions by adding to shell profile
    PROFILE_FILE=""
    if [ -f "$HOME/.bashrc" ]; then
        PROFILE_FILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        PROFILE_FILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.profile" ]; then
        PROFILE_FILE="$HOME/.profile"
    fi

    if [ -n "$PROFILE_FILE" ]; then
        if ! grep -q "export PATH=\"$LOCAL_BIN_PATH:\$PATH\"" "$PROFILE_FILE"; then
            echo "Adding $LOCAL_BIN_PATH to PATH in $PROFILE_FILE..."
            echo '' >> "$PROFILE_FILE" # Add a newline for separation
            echo '# Add local bin to PATH for user-installed packages' >> "$PROFILE_FILE"
            echo "export PATH=\"$LOCAL_BIN_PATH:\$PATH\"" >> "$PROFILE_FILE"
        fi
    else
        echo "WARNING: Could not find .bashrc, .bash_profile, or .profile to persist PATH update."
    fi
fi
echo "MLflow and Boto3 installed."

# Verify mlflow command is available
if ! command -v mlflow &> /dev/null; then
    echo "ERROR: mlflow command not found after installation. PATH might not be updated correctly."
    echo "       Current PATH: $PATH"
    echo "       Expected mlflow in: $LOCAL_BIN_PATH"
    echo "       Try sourcing your profile (e.g., 'source ~/.bashrc') and re-running, or debug PATH."
    exit 1
fi
MLFLOW_EXECUTABLE_PATH=$(command -v mlflow)
echo "MLflow executable found at: $MLFLOW_EXECUTABLE_PATH"
echo "--------------------------------------------------"

# --- 3. Create MLflow Data Directory ---
echo "STEP 3: Creating MLflow data directory: $MLFLOW_DATA_DIR"
mkdir -p "$MLFLOW_DATA_DIR"
# cd "$MLFLOW_DATA_DIR" # We will run mlflow command with absolute paths or from home
echo "MLflow data directory ensured at: $MLFLOW_DATA_DIR"
echo "--------------------------------------------------"

# --- 4. Stop any existing MLflow Server & Start New One ---
echo "STEP 4: Stopping any existing MLflow server and starting a new one..."

# Attempt to find and kill any existing MLflow server process to avoid port conflicts.
# This is useful if the script is re-run.
# We target the specific command to be safer.
MLFLOW_SERVER_COMMAND_PATTERN="mlflow server --backend-store-uri sqlite:///$MLFLOW_DB_FILE --default-artifact-root $MLFLOW_S3_ARTIFACT_ROOT"

# Find PIDs associated with the MLflow server command, being careful with grep patterns
EXISTING_PIDS=$(pgrep -f "mlflow server .*--backend-store-uri sqlite:///.*$MLFLOW_DB_FILE.*--default-artifact-root $MLFLOW_S3_ARTIFACT_ROOT")

if [ -n "$EXISTING_PIDS" ]; then
    echo "Found existing MLflow server process(es) with PID(s): $EXISTING_PIDS. Attempting to kill..."
    sudo kill $EXISTING_PIDS || echo "Failed to kill process(es) $EXISTING_PIDS (they might have already terminated)."
    sleep 3 # Give processes time to terminate
else
    echo "No existing MLflow server process found matching the specific command."
fi

echo "Starting MLflow server in the background using nohup..."
echo "  SQLite DB file: $MLFLOW_DATA_DIR/$MLFLOW_DB_FILE"
echo "  Log file: $MLFLOW_LOG_FILE"

# Run MLflow server from the MLFLOW_DATA_DIR so sqlite:///mlflow.db creates the db there.
# Using nohup to run in the background and redirect stdout/stderr to a log file.
nohup "$MLFLOW_EXECUTABLE_PATH" server \
    --backend-store-uri "sqlite:///$MLFLOW_DB_FILE" \
    --default-artifact-root "$MLFLOW_S3_ARTIFACT_ROOT" \
    --host "$MLFLOW_HOST" \
    --port "$MLFLOW_SERVER_PORT" \
    --workers 1 \
    > "$MLFLOW_LOG_FILE" 2>&1 &

# Give it a few seconds to start up
echo "Waiting for MLflow server to start (approx 5-10 seconds)..."
sleep 10 # Increased sleep for potentially slower free-tier instances

# Check if the process is running
# Re-check PIDs using the specific command pattern
MLFLOW_PID=$(pgrep -f "mlflow server .*--backend-store-uri sqlite:///.*$MLFLOW_DB_FILE.*--default-artifact-root $MLFLOW_S3_ARTIFACT_ROOT" | awk '{print $1; exit}')

if [ -n "$MLFLOW_PID" ]; then
    echo "MLflow server started successfully (PID: $MLFLOW_PID)."
else
    echo "ERROR: MLflow server may not have started correctly."
    echo "Please check the logs for errors: $MLFLOW_LOG_FILE"
    echo "Last few lines of the log:"
    tail -n 20 "$MLFLOW_LOG_FILE"
    exit 1
fi
echo "--------------------------------------------------"

# --- 5. Output Final Information ---
echo "STEP 5: Setup Complete!"
PUBLIC_IP_CMD="curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo \"YOUR_EC2_PUBLIC_IP (Could not fetch automatically)\""
PUBLIC_IP=$(eval "$PUBLIC_IP_CMD")

echo ""
echo "====================================================================="
echo "MLflow Server is now running!"
echo ""
echo "Access the MLflow UI at: http://${PUBLIC_IP}:${MLFLOW_SERVER_PORT}"
echo ""
echo "Key Information:"
echo "  - Server Process ID (PID): $MLFLOW_PID (managed by nohup)"
echo "  - Logs: $MLFLOW_LOG_FILE"
echo "  - SQLite Database: $MLFLOW_DATA_DIR/$MLFLOW_DB_FILE"
echo "  - Artifacts S3 Bucket: $MLFLOW_S3_ARTIFACT_ROOT"
echo ""
echo "REMINDERS:"
echo "  - Ensure your EC2 instance's IAM Role has permissions for S3 bucket '$MLFLOW_S3_BUCKET_NAME'."
echo "  - Ensure your EC2 Security Group allows inbound traffic on port $MLFLOW_SERVER_PORT from your IP."
echo ""
echo "To stop the server:"
echo "  sudo kill $MLFLOW_PID"
echo "  (Or: ps aux | grep 'mlflow server' -> find PID -> kill <PID>)"
echo ""
echo "For a more robust setup (recommended for anything beyond basic testing), consider using systemd."
echo "You can create a service file like '/etc/systemd/system/mlflow-tracking.service' with content such as:"
echo "---------------------------------------------------------------------"
cat << EOF
[Unit]
Description=MLflow Tracking Server (SQLite + S3)
After=network.target

[Service]
User=${MLFLOW_USER}
# Group=${MLFLOW_USER} # Or the primary group of $MLFLOW_USER
WorkingDirectory=${MLFLOW_DATA_DIR} # Ensures mlflow.db is created here
ExecStart=${MLFLOW_EXECUTABLE_PATH} server \\
    --backend-store-uri "sqlite:///${MLFLOW_DB_FILE}" \\
    --default-artifact-root "${MLFLOW_S3_ARTIFACT_ROOT}" \\
    --host "${MLFLOW_HOST}" \\
    --port "${MLFLOW_SERVER_PORT}" \\
    --workers 1
Restart=always
RestartSec=10
# If not using IAM roles for S3 (IAM roles are strongly preferred for EC2):
# Environment="AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID"
# Environment="AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY"
# Environment="AWS_DEFAULT_REGION=your-aws-region"

[Install]
WantedBy=multi-user.target
EOF
echo "---------------------------------------------------------------------"
echo "Then, after stopping the nohup process (sudo kill $MLFLOW_PID), run:"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable mlflow-tracking"
echo "  sudo systemctl start mlflow-tracking"
echo "  sudo systemctl status mlflow-tracking"
echo "====================================================================="

exit 0