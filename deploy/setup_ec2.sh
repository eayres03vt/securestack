#!/bin/bash
# Run this ONCE on the EC2 instance (via an SSM Session Manager shell)
# to install and start the app. Usage:
#   ./setup_ec2.sh <rds-endpoint-including-port>
# The RDS endpoint comes from `terraform output db_endpoint`.
set -e

DB_HOST="$1"
if [ -z "$DB_HOST" ]; then
  echo "Usage: ./setup_ec2.sh <rds-endpoint-including-port>"
  exit 1
fi

echo "Installing system packages..."
sudo dnf install -y git python3-pip python3-devel gcc

echo "Cloning repository..."
sudo mkdir -p /opt/securestack
sudo chown ec2-user:ec2-user /opt/securestack
cd /opt/securestack
git clone https://github.com/eayres03vt/securestack.git .

echo "Setting up Python virtual environment..."
cd app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

echo "Writing non-secret runtime config..."
cat > .env.production <<EOF
DB_HOST=$DB_HOST
DB_NAME=securestack
DB_USER=dbadmin
PROJECT_NAME=securestack
EOF

echo "Installing systemd service..."
sudo cp /opt/securestack/deploy/securestack.service /etc/systemd/system/securestack.service
sudo systemctl daemon-reload
sudo systemctl enable securestack
sudo systemctl restart securestack

echo "Done. Checking status:"
sudo systemctl status securestack --no-pager
