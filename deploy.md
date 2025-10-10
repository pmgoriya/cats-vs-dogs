## Phase 1: User Data Script (EC2 Provisioning)

```bash
#!/bin/bash
apt update
apt install -y python3 python3-pip python3-venv postgresql postgresql-contrib rabbitmq-server golang-go nodejs npm nginx certbot python3-certbot-nginx

# Start and enable services
systemctl start postgresql
systemctl enable postgresql
systemctl start rabbitmq-server
systemctl enable rabbitmq-server
systemctl start nginx
systemctl enable nginx
```

---

## Phase 2: Database Setup (After SSH)

```bash
# Switch to postgres user and create database
sudo -u postgres psql

# In psql prompt:
CREATE DATABASE voting;
CREATE USER your_db_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE voting TO your_db_user;
\q

# Load schema
sudo -u postgres psql -d voting -f /path/to/schema.sql

# Or if you want your user to load it:
PGPASSWORD=your_password psql -h localhost -U your_db_user -d voting -f /path/to/schema.sql

# Verify
PGPASSWORD=your_password psql -h localhost -U your_db_user -d voting -c "SELECT * FROM votes;"
```

---

## Phase 3: Application as systemd Services

### Backend (FastAPI)

```bash
# Setup Python environment
cd /path/to/api
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

# Create systemd service
sudo nano /etc/systemd/system/voting-api.service
```

**voting-api.service:**
```ini
[Unit]
Description=Voting API
After=network.target postgresql.service rabbitmq-server.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/cats-vs-dogs-voting/api
EnvironmentFile=/home/ubuntu/cats-vs-dogs-voting/.env
ExecStart=/home/ubuntu/cats-vs-dogs-voting/api/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable voting-api
sudo systemctl start voting-api
sudo systemctl status voting-api
```

### Worker (Go)

```bash
# Setup Go worker
cd /path/to/worker
go mod tidy
go mod download

# Optional: Build binary for faster startup
go build -o voting-worker worker.go

# Create systemd service
sudo nano /etc/systemd/system/voting-worker.service
```

**voting-worker.service:**
```ini
[Unit]
Description=Voting Worker
After=network.target postgresql.service rabbitmq-server.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/cats-vs-dogs-voting/worker
EnvironmentFile=/home/ubuntu/cats-vs-dogs-voting/.env
ExecStart=/usr/bin/go run worker.go
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

**OR if you built binary:**
```ini
ExecStart=/home/ubuntu/cats-vs-dogs-voting/worker/voting-worker
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable voting-worker
sudo systemctl start voting-worker
sudo systemctl status voting-worker
```

---

## Phase 4: Frontend with nginx + SSL

### Build Frontend

```bash
cd /path/to/frontend
npm install
npm run build
```

### Copy to nginx

```bash
sudo cp -r dist/* /var/www/html/
```

### Configure nginx

```bash
sudo nano /etc/nginx/sites-available/default
```

**nginx config:**
```nginx
server {
    listen 80;
    server_name your-domain.com;  # or EC2 public IP

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
# Test nginx config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### Setup SSL with Certbot

```bash
# Make sure your domain points to EC2 public IP first

sudo certbot --nginx -d your-domain.com

# Follow prompts, certbot will auto-configure nginx for HTTPS

# Auto-renewal is set up automatically, test it:
sudo certbot renew --dry-run
```

---

## Verify Everything

```bash
# Check all services
sudo systemctl status voting-api
sudo systemctl status voting-worker
sudo systemctl status rabbitmq-server
sudo systemctl status postgresql
sudo systemctl status nginx

# View logs
sudo journalctl -u voting-api -f
sudo journalctl -u voting-worker -f

# Test API
curl http://localhost:8000/results

# Test from outside
curl https://your-domain.com/api/results
```

---

## Useful Commands

```bash
# Restart services
sudo systemctl restart voting-api
sudo systemctl restart voting-worker

# Stop services
sudo systemctl stop voting-api
sudo systemctl stop voting-worker

# View logs (last 100 lines)
sudo journalctl -u voting-api -n 100

# Follow logs in real-time
sudo journalctl -u voting-api -f

# Check RabbitMQ queue
sudo rabbitmqctl list_queues

# Check database
PGPASSWORD=your_password psql -h localhost -U your_db_user -d voting -c "SELECT COUNT(*) FROM jobs;"
```

That's it! Everything runs as systemd services and survives reboots.