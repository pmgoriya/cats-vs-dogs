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