#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "Error: .env file not found!"
    exit 1
fi

cd "$SCRIPT_DIR/api"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Error: Virtual environment not found. Run ./install.sh first"
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Export environment variables
export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD RABBITMQ_HOST

echo "Starting API on http://$API_HOST:$API_PORT"
echo "Virtual environment: $(which python)"
echo ""

uvicorn main:app --host "$API_HOST" --port "$API_PORT" --reload
