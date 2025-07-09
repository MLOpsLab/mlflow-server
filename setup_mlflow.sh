#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -x # DEBUG: Print every command executed

# ... (Keep the initial comments and configuration from the previous version) ...

# --- Configuration ---
MLFLOW_S3_BUCKET_NAME="${MLFLOW_S3_BUCKET_NAME_ENV:-your-s3-bucket-name-placeholder}"
MLFLOW_SERVER_PORT="${MLFLOW_SERVER_PORT_ENV:-5000}"
MLFLOW_HOST="0.0.0.0"
MLFLOW_DATA_DIR="$HOME/mlflow_server_data"
MLFLOW_USER=$(whoami)
MLFLOW_DB_FILENAME="mlflow.db"
MLFLOW_DB_ABSOLUTE_PATH="$MLFLOW_DATA_DIR/$MLFLOW_DB_FILENAME"
MLFLOW_LOG_FILE="$MLFLOW_DATA_DIR/mlflow_server.log"

echo "DEBUG: Script execution started. User: $(whoami), Home: $HOME"

# --- Script Start ---
echo "=================================================="
echo "Starting MLflow Server Setup..."
echo "=================================================="
echo ""

# --- Configuration Validation ---
echo "DEBUG: Entering Configuration Validation..."
echo "Validating Configuration..."
if [ "$MLFLOW_S3_BUCKET_NAME" == "your-s3-bucket-name-placeholder" ] || [ -z "$MLFLOW_S3_BUCKET_NAME" ]; then
    echo "ERROR: MLFLOW_S3_BUCKET_NAME is not set correctly."
    echo "       It should be passed as an environment variable (MLFLOW_S3_BUCKET_NAME_ENV)."
    echo "       Current value: '$MLFLOW_S3_BUCKET_NAME'"
    exit 1
fi

if [[ ! "$MLFLOW_S3_BUCKET_NAME" == s3://* ]]; then
    MLFLOW_S3_ARTIFACT_ROOT="s3://${MLFLOW_S3_BUCKET_NAME}"
else
    MLFLOW_S3_ARTIFACT_ROOT="${MLFLOW_S3_BUCKET_NAME}"
fi
echo "  User: $MLFLOW_USER"
echo "  MLflow Data Directory: $MLFLOW_DATA_DIR"
echo "  MLflow SQLite DB Absolute Path: $MLFLOW_DB_ABSOLUTE_PATH"
echo "  MLflow S3 Artifact Root: $MLFLOW_S3_ARTIFACT_ROOT"
echo "  MLflow Server Port: $MLFLOW_SERVER_PORT"
echo "  MLFLOW_HOST: $MLFLOW_HOST"
echo "  MLflow Log File: $MLFLOW_LOG_FILE"
echo "--------------------------------------------------"
echo "DEBUG: Configuration Validation Complete."

# --- 1. OS Detection and Package Installation ---
echo "DEBUG: Entering STEP 1: OS Detection and Package Installation..."
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
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip git
else
    echo "ERROR: Unsupported OS: $OS_NAME. This script supports Amazon Linux and Ubuntu."
    exit 1
fi
echo "Prerequisites installed successfully."
echo "--------------------------------------------------"
echo "DEBUG: STEP 1 Complete."


# --- 2. Install MLflow and Boto3 ---
echo "DEBUG: Entering STEP 2: Install MLflow and Boto3..."
echo "STEP 2: Installing MLflow and Boto3 using pip3..."
pip3 install --no-cache-dir --user mlflow boto3

LOCAL_BIN_PATH="$HOME/.local/bin"
if [[ ":$PATH:" != *":$LOCAL_BIN_PATH:"* ]]; then
    echo "Adding $LOCAL_BIN_PATH to PATH for current session..."
    export PATH="$LOCAL_BIN_PATH:$PATH"
    PROFILE_FILE=""
    if [ -f "$HOME/.bashrc" ]; then PROFILE_FILE="$HOME/.bashrc";
    elif [ -f "$HOME/.bash_profile" ]; then PROFILE_FILE="$HOME/.bash_profile";
    elif [ -f "$HOME/.profile" ]; then PROFILE_FILE="$HOME/.profile"; fi
    if [ -n "$PROFILE_FILE" ]; then
        if ! grep -q "export PATH=\"$LOCAL_BIN_PATH:\$PATH\"" "$PROFILE_FILE"; then
            echo "Adding $LOCAL_BIN_PATH to PATH in $PROFILE_FILE..."
            echo '' >> "$PROFILE_FILE"; echo '# Add local bin to PATH' >> "$PROFILE_FILE";
            echo "export PATH=\"$LOCAL_BIN_PATH:\$PATH\"" >> "$PROFILE_FILE"; fi
    else echo "WARNING: Could not find profile file to persist PATH update."; fi
fi
echo "MLflow and Boto3 installed."
if ! command -v mlflow &> /dev/null; then
    echo "ERROR: mlflow command not found. PATH: $PATH. Expected in: $LOCAL_BIN_PATH"
    exit 1
fi
MLFLOW_EXECUTABLE_PATH=$(command -v mlflow)
echo "MLflow executable found at: $MLFLOW_EXECUTABLE_PATH"
echo "--------------------------------------------------"
echo "DEBUG: STEP 2 Complete."

# --- 3. Create MLflow Data Directory ---
echo "DEBUG: Entering STEP 3: Create MLflow Data Directory..."
echo "STEP 3: Creating MLflow data directory: $MLFLOW_DATA_DIR"
mkdir -p "$MLFLOW_DATA_DIR"
echo "MLflow data directory ensured at: $MLFLOW_DATA_DIR"
echo "Current directory: $(pwd)"
ls -ld "$MLFLOW_DATA_DIR" # Check permissions and existence
echo "--------------------------------------------------"
echo "DEBUG: STEP 3 Complete. About to enter STEP 4."

# --- 4. Stop any existing MLflow Server & Start New One ---
echo "DEBUG: **ENTERING STEP 4 NOW**"
echo "STEP 4: Stopping any existing MLflow server and starting a new one..."
echo "DEBUG: STEP 4 - Just after initial echo."

MLFLOW_SERVER_COMMAND_PATTERN_CORE="mlflow server --backend-store-uri sqlite:///$MLFLOW_DB_ABSOLUTE_PATH --default-artifact-root $MLFLOW_S3_ARTIFACT_ROOT --host $MLFLOW_HOST --port $MLFLOW_SERVER_PORT"
echo "DEBUG: STEP 4 - Defined MLFLOW_SERVER_COMMAND_PATTERN_CORE: $MLFLOW_SERVER_COMMAND_PATTERN_CORE"

EXISTING_PIDS=$(pgrep -f "$MLFLOW_SERVER_COMMAND_PATTERN_CORE" || true)
echo "DEBUG: STEP 4 - pgrep result for EXISTING_PIDS: '$EXISTING_PIDS'"


if [ -n "$EXISTING_PIDS" ]; then
    echo "DEBUG: STEP 4 - Found existing PIDs: $EXISTING_PIDS. Attempting to kill..."
    sudo kill $EXISTING_PIDS || echo "WARNING: Failed to kill process(es) $EXISTING_PIDS (they might have already terminated or permission issues)."
    sleep 3
else
    echo "DEBUG: STEP 4 - No existing MLflow server process found matching the specific command pattern."
fi
echo "DEBUG: STEP 4 - After attempting to kill old processes."

echo "Starting MLflow server in the background using nohup..."
echo "  SQLite DB will be at: $MLFLOW_DB_ABSOLUTE_PATH"
echo "  Log file will be at: $MLFLOW_LOG_FILE"
echo "DEBUG: STEP 4 - About to execute nohup mlflow server..."

nohup "$MLFLOW_EXECUTABLE_PATH" server \
    --backend-store-uri "sqlite:///$MLFLOW_DB_ABSOLUTE_PATH" \
    --default-artifact-root "$MLFLOW_S3_ARTIFACT_ROOT" \
    --host "$MLFLOW_HOST" \
    --port "$MLFLOW_SERVER_PORT" \
    --workers 1 \
    > "$MLFLOW_LOG_FILE" 2>&1 &

MLFLOW_NOHUP_PID=$!
echo "DEBUG: STEP 4 - Nohup command executed. Nohup PID: $MLFLOW_NOHUP_PID."
echo "Nohup process started with PID: $MLFLOW_NOHUP_PID. Waiting for MLflow server to initialize..."
sleep 15

echo "DEBUG: STEP 4 - Checking for actual server PID after sleep."
MLFLOW_ACTUAL_SERVER_PID=$(pgrep -f "$MLFLOW_SERVER_COMMAND_PATTERN_CORE" || true)
echo "DEBUG: STEP 4 - pgrep result for MLFLOW_ACTUAL_SERVER_PID: '$MLFLOW_ACTUAL_SERVER_PID'"

if [ -n "$MLFLOW_ACTUAL_SERVER_PID" ]; then
    echo "MLflow server appears to be running with PID(s): $MLFLOW_ACTUAL_SERVER_PID."
    MLFLOW_DISPLAY_PID=$(echo $MLFLOW_ACTUAL_SERVER_PID | awk '{print $1}')
else
    echo "ERROR: MLflow server may not have started correctly after $MLFLOW_NOHUP_PID launched."
    echo "Please check the logs for errors: $MLFLOW_LOG_FILE"
    echo "-------------------- LOGS START --------------------"
    tail -n 30 "$MLFLOW_LOG_FILE" || echo "Could not read log file $MLFLOW_LOG_FILE."
    echo "-------------------- LOGS END ----------------------"
    if ! ps -p $MLFLOW_NOHUP_PID > /dev/null; then
       echo "Nohup process $MLFLOW_NOHUP_PID is no longer running. It likely exited with an error."
    fi
    exit 1
fi
echo "--------------------------------------------------"
echo "DEBUG: STEP 4 Complete."

# --- 5. Output Final Information ---
# ... (Keep STEP 5 as is) ...
echo "DEBUG: Entering STEP 5: Output Final Information..."
echo "STEP 5: Setup Complete!"
PUBLIC_IP_CMD="curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo \"YOUR_EC2_PUBLIC_IP (Could not fetch automatically)\""
PUBLIC_IP=$(eval "$PUBLIC_IP_CMD")

# --- 6. Setup systemd Service for MLflow ---
echo "=================================================="
echo "STEP 6: Setting up systemd service for MLflow..."
echo "=================================================="

SYSTEMD_SERVICE_FILE="/etc/systemd/system/mlflow.service"

sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=MLflow Tracking Server
After=network.target

[Service]
User=$MLFLOW_USER
WorkingDirectory=$MLFLOW_DATA_DIR
ExecStart=$MLFLOW_EXECUTABLE_PATH server \
  --backend-store-uri sqlite:///$MLFLOW_DB_ABSOLUTE_PATH \
  --default-artifact-root $MLFLOW_S3_ARTIFACT_ROOT \
  --host $MLFLOW_HOST \
  --port $MLFLOW_SERVER_PORT
Environment="PATH=$HOME/.local/bin:/usr/bin:/bin"
Restart=always
StandardOutput=append:$MLFLOW_LOG_FILE
StandardError=append:$MLFLOW_LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and enabling mlflow.service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable mlflow.service
sudo systemctl restart mlflow.service

echo ""
echo "✅ MLflow service created and started via systemd!"
sudo systemctl status mlflow.service --no-pager || true


echo ""
echo "====================================================================="
echo "MLflow Server is now running!"
echo ""
echo "Access the MLflow UI at: http://${PUBLIC_IP}:${MLFLOW_SERVER_PORT}"
echo ""
echo "Key Information:"
echo "  - Server Process ID (PID): $MLFLOW_DISPLAY_PID (actual server process)"
echo "  - Logs: $MLFLOW_LOG_FILE"
echo "  - SQLite Database: $MLFLOW_DB_ABSOLUTE_PATH"
echo "  - Artifacts S3 Bucket: $MLFLOW_S3_ARTIFACT_ROOT"
echo ""
echo "REMINDERS:"
echo "  - Ensure your EC2 instance's IAM Role has permissions for S3 bucket '$MLFLOW_S3_BUCKET_NAME'."
echo "  - Ensure your EC2 Security Group allows inbound traffic on port $MLFLOW_SERVER_PORT from your IP."
echo ""
echo "To stop the server:"
echo "  sudo kill $MLFLOW_DISPLAY_PID"
echo ""
echo "For a more robust setup (recommended for anything beyond basic testing), consider using systemd."
# ... (systemd example) ...
echo "====================================================================="
echo "DEBUG: Script finished."
# Remove set -x if you want to turn off extreme debugging for the final output.
# set +x
exit 0