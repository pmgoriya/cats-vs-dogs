#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

cd "$SCRIPT_DIR/worker"

export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD RABBITMQ_HOST

echo "Starting Worker..."
go run worker.go
