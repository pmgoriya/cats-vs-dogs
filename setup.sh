#!/bin/bash

echo "=== Cats vs Dogs Voting App Setup ==="
echo ""

# Create directory structure
echo "Creating directory structure..."
# mkdir -p api worker frontend/src

# Check prerequisites
echo ""
echo "Checking prerequisites..."
command -v psql >/dev/null 2>&1 || { echo "PostgreSQL not found. Please install it."; exit 1; }
command -v rabbitmqctl >/dev/null 2>&1 || { echo "RabbitMQ not found. Please install it."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Python3 not found. Please install it."; exit 1; }
command -v go >/dev/null 2>&1 || { echo "Go not found. Please install it."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Node.js not found. Please install it."; exit 1; }

echo "All prerequisites found!"

# Setup database
echo ""
echo "Setting up database..."
sudo -u postgres psql -c "CREATE DATABASE voting;" 2>/dev/null || echo "Database already exists"
sudo -u postgres psql -d voting -f schema.sql

# Setup Python API
echo ""
echo "Setting up Python API..."
cd api
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate
cd ..

# Setup Go Worker
echo ""
echo "Setting up Go worker..."
cd worker
go mod download
cd ..

# Setup Frontend
echo ""
echo "Setting up frontend..."
cd frontend
npm install
cd ..

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "To run the application, open 3 terminals:"
echo ""
echo "Terminal 1 (API):"
echo "  cd api && source venv/bin/activate"
echo "  uvicorn main:app --host 0.0.0.0 --port 8000"
echo ""
echo "Terminal 2 (Worker):"
echo "  cd worker && go run worker.go"
echo ""
echo "Terminal 3 (Frontend):"
echo "  cd frontend && npm run dev"
echo ""
echo "Then open http://localhost:5173 in your browser"
