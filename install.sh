#!/bin/bash

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "========================================="
echo "  Cats vs Dogs Voting App - Setup"
echo "========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}➜ $1${NC}"
}

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/redhat-release ]; then
        DISTRO="redhat"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
fi

print_info "Detected OS: $OS"
echo ""

# Check if .env exists
if [ -f "$ENV_FILE" ]; then
    print_info "Found existing .env file. Using existing configuration."
    source "$ENV_FILE"
else
    print_info "Creating .env file with default values..."
    cat > "$ENV_FILE" << 'EOF'
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=voting
DB_USER=postgres
DB_PASSWORD=postgres

# RabbitMQ Configuration
RABBITMQ_HOST=localhost
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# API Configuration
API_HOST=0.0.0.0
API_PORT=8000
EOF
    
    print_success "Created .env file at: $ENV_FILE"
    echo ""
    print_info "IMPORTANT: Please edit .env file and set your desired passwords!"
    echo "Press ENTER to continue with default values, or Ctrl+C to exit and edit .env first..."
    read -r
    
    source "$ENV_FILE"
fi

echo ""
print_info "Using configuration:"
echo "  Database: $DB_NAME"
echo "  DB User: $DB_USER"
echo "  DB Host: $DB_HOST:$DB_PORT"
echo ""

# ==========================================
# 1. INSTALL POSTGRESQL
# ==========================================
print_info "Step 1: Installing PostgreSQL..."

if command -v psql &> /dev/null; then
    print_success "PostgreSQL already installed: $(psql --version)"
else
    if [ "$OS" == "linux" ] && [ "$DISTRO" == "debian" ]; then
        sudo apt update
        sudo apt install -y postgresql postgresql-contrib
        sudo systemctl start postgresql
        sudo systemctl enable postgresql
        print_success "PostgreSQL installed and started"
    elif [ "$OS" == "macos" ]; then
        brew install postgresql@15
        brew services start postgresql@15
        print_success "PostgreSQL installed and started"
    else
        print_error "Unsupported OS. Please install PostgreSQL manually."
        exit 1
    fi
fi

echo ""

# ==========================================
# 2. SETUP POSTGRESQL DATABASE
# ==========================================
print_info "Step 2: Setting up PostgreSQL database..."

# Set password for postgres user
print_info "Setting password for postgres user..."
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$DB_PASSWORD';" 2>/dev/null || {
    print_error "Failed to set postgres password. Trying alternative method..."
    echo "postgres:$DB_PASSWORD" | sudo chpasswd 2>/dev/null || true
}

# Configure PostgreSQL to accept password authentication
PG_VERSION=$(sudo -u postgres psql -t -c "SHOW server_version;" | cut -d'.' -f1 | xargs)
if [ "$OS" == "linux" ]; then
    PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
elif [ "$OS" == "macos" ]; then
    PG_HBA="/usr/local/var/postgres/pg_hba.conf"
fi

if [ -f "$PG_HBA" ]; then
    print_info "Configuring PostgreSQL authentication..."
    sudo cp "$PG_HBA" "$PG_HBA.backup"
    
    # Add or update local connection rules
    if grep -q "local.*all.*postgres.*trust" "$PG_HBA"; then
        print_info "Already configured for trust authentication"
    else
        sudo sed -i.bak 's/local.*all.*postgres.*peer/local   all             postgres                                trust/' "$PG_HBA" 2>/dev/null || \
        sudo sed -i '' 's/local.*all.*postgres.*peer/local   all             postgres                                trust/' "$PG_HBA" 2>/dev/null || true
        
        # Add host connection with md5
        echo "host    all             all             127.0.0.1/32            md5" | sudo tee -a "$PG_HBA" > /dev/null
    fi
    
    # Restart PostgreSQL
    if [ "$OS" == "linux" ]; then
        sudo systemctl restart postgresql
    elif [ "$OS" == "macos" ]; then
        brew services restart postgresql@15
    fi
    print_success "PostgreSQL authentication configured"
fi

# Wait for PostgreSQL to be ready
sleep 2

# Create database
print_info "Creating database '$DB_NAME'..."
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" 2>/dev/null || {
    print_info "Database '$DB_NAME' already exists"
}

# Create schema
print_info "Creating database schema..."
sudo -u postgres psql -d "$DB_NAME" << 'EOSQL'
-- Votes table
CREATE TABLE IF NOT EXISTS votes (
    choice VARCHAR(10) PRIMARY KEY,
    count INTEGER NOT NULL DEFAULT 0
);

-- Jobs table
CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY,
    choice VARCHAR(10) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_jobs_created ON jobs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);

-- Seed data
INSERT INTO votes (choice, count) VALUES ('cats', 0), ('dogs', 0)
ON CONFLICT (choice) DO NOTHING;
EOSQL

print_success "Database schema created"

# Verify database setup
print_info "Verifying database setup..."
VOTE_COUNT=$(sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM votes;")
if [ "$VOTE_COUNT" -eq 2 ]; then
    print_success "Database verification passed"
    sudo -u postgres psql -d "$DB_NAME" -c "SELECT * FROM votes;"
else
    print_error "Database verification failed"
    exit 1
fi

echo ""

# ==========================================
# 3. INSTALL RABBITMQ
# ==========================================
print_info "Step 3: Installing RabbitMQ..."

if command -v rabbitmqctl &> /dev/null; then
    print_success "RabbitMQ already installed"
else
    if [ "$OS" == "linux" ] && [ "$DISTRO" == "debian" ]; then
        sudo apt install -y rabbitmq-server
        sudo systemctl start rabbitmq-server
        sudo systemctl enable rabbitmq-server
        print_success "RabbitMQ installed and started"
    elif [ "$OS" == "macos" ]; then
        brew install rabbitmq
        brew services start rabbitmq
        print_success "RabbitMQ installed and started"
    else
        print_error "Unsupported OS. Please install RabbitMQ manually."
        exit 1
    fi
fi

# Wait for RabbitMQ to be ready
sleep 3

# Verify RabbitMQ
if sudo rabbitmqctl status &> /dev/null; then
    print_success "RabbitMQ is running"
else
    print_error "RabbitMQ is not running properly"
fi

echo ""

# ==========================================
# 4. INSTALL PYTHON AND SETUP API
# ==========================================
print_info "Step 4: Setting up Python API..."

# Check Python
if ! command -v python3 &> /dev/null; then
    print_error "Python3 not found. Please install Python 3.8+ manually."
    exit 1
fi
print_success "Python found: $(python3 --version)"

# Setup API virtual environment
cd "$SCRIPT_DIR/api"
if [ -d "venv" ]; then
    print_info "Virtual environment already exists"
else
    print_info "Creating Python virtual environment..."
    python3 -m venv venv
    print_success "Virtual environment created"
fi

# Activate and install dependencies
print_info "Installing Python dependencies..."
source venv/bin/activate
pip install --upgrade pip > /dev/null
pip install -r requirements.txt > /dev/null
deactivate
print_success "Python dependencies installed"

cd "$SCRIPT_DIR"
echo ""

# ==========================================
# 5. INSTALL GO AND SETUP WORKER
# ==========================================
print_info "Step 5: Setting up Go Worker..."

# Check Go
if ! command -v go &> /dev/null; then
    print_error "Go not found. Please install Go 1.21+ manually."
    print_info "Download from: https://go.dev/dl/"
    exit 1
fi
print_success "Go found: $(go version)"

# Setup Go worker
cd "$SCRIPT_DIR/worker"
print_info "Downloading Go dependencies..."
go mod tidy
go mod download
print_success "Go dependencies installed"

cd "$SCRIPT_DIR"
echo ""

# ==========================================
# 6. INSTALL NODE AND SETUP FRONTEND
# ==========================================
print_info "Step 6: Setting up Frontend..."

# Check Node
if ! command -v node &> /dev/null; then
    print_error "Node.js not found. Please install Node.js 16+ manually."
    print_info "Download from: https://nodejs.org/"
    exit 1
fi
print_success "Node.js found: $(node --version)"

# Setup frontend
cd "$SCRIPT_DIR/frontend"
if [ -d "node_modules" ]; then
    print_info "Node modules already installed"
else
    print_info "Installing Node dependencies..."
    npm install > /dev/null 2>&1
    print_success "Node dependencies installed"
fi

cd "$SCRIPT_DIR"
echo ""

# ==========================================
# 7. CREATE STARTUP SCRIPTS
# ==========================================
print_info "Step 7: Creating startup scripts..."

# Create start-api.sh
cat > "$SCRIPT_DIR/start-api.sh" << 'EOF'
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
EOF

# Create start-worker.sh
cat > "$SCRIPT_DIR/start-worker.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

cd "$SCRIPT_DIR/worker"

export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD RABBITMQ_HOST

echo "Starting Worker..."
go run worker.go
EOF

# Create start-frontend.sh
cat > "$SCRIPT_DIR/start-frontend.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR/frontend"

echo "Starting Frontend on http://localhost:5173"
npm run dev
EOF

# Create start-all.sh
cat > "$SCRIPT_DIR/start-all.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting all services..."
echo ""
echo "Opening 3 terminals..."
echo ""

if command -v gnome-terminal &> /dev/null; then
    gnome-terminal --tab --title="API" -- bash -c "cd '$SCRIPT_DIR' && ./start-api.sh; exec bash"
    gnome-terminal --tab --title="Worker" -- bash -c "cd '$SCRIPT_DIR' && ./start-worker.sh; exec bash"
    gnome-terminal --tab --title="Frontend" -- bash -c "cd '$SCRIPT_DIR' && ./start-frontend.sh; exec bash"
elif command -v xterm &> /dev/null; then
    xterm -hold -e "cd '$SCRIPT_DIR' && ./start-api.sh" &
    xterm -hold -e "cd '$SCRIPT_DIR' && ./start-worker.sh" &
    xterm -hold -e "cd '$SCRIPT_DIR' && ./start-frontend.sh" &
else
    echo "Please open 3 terminals manually and run:"
    echo "  Terminal 1: ./start-api.sh"
    echo "  Terminal 2: ./start-worker.sh"
    echo "  Terminal 3: ./start-frontend.sh"
fi
EOF

chmod +x "$SCRIPT_DIR/start-api.sh"
chmod +x "$SCRIPT_DIR/start-worker.sh"
chmod +x "$SCRIPT_DIR/start-frontend.sh"
chmod +x "$SCRIPT_DIR/start-all.sh"

print_success "Startup scripts created"
echo ""

# ==========================================
# FINAL SUMMARY
# ==========================================
echo ""
echo "========================================="
echo "  ✓ Setup Complete!"
echo "========================================="
echo ""
print_success "All components installed and configured:"
echo "  ✓ PostgreSQL - Database ready with schema"
echo "  ✓ RabbitMQ - Message queue running"
echo "  ✓ Python API - Dependencies installed"
echo "  ✓ Go Worker - Dependencies installed"
echo "  ✓ React Frontend - Dependencies installed"
echo ""
print_info "Configuration stored in: $ENV_FILE"
echo ""
print_info "To start the application:"
echo ""
echo "  Option 1 - Start all services at once:"
echo "    ./start-all.sh"
echo ""
echo "  Option 2 - Start services in separate terminals:"
echo "    Terminal 1: ./start-api.sh"
echo "    Terminal 2: ./start-worker.sh"
echo "    Terminal 3: ./start-frontend.sh"
echo ""
print_info "Then open: http://localhost:5173"
echo ""
print_info "To verify setup:"
echo "  curl http://localhost:8000/results"
echo ""
print_success "Happy voting! 🐱 vs 🐶"
echo ""