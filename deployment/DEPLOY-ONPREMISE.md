# SQL Monitor - On-Premise Deployment Guide

Complete step-by-step guide for deploying SQL Monitor on-premise using Docker Compose or Kubernetes.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture Options](#architecture-options)
- [Docker Compose Deployment](#docker-compose-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Bare Metal Deployment](#bare-metal-deployment)
- [Configuration](#configuration)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## Overview

This guide covers three on-premise deployment options:

1. **Docker Compose**: Simplest, single-server deployment
2. **Kubernetes**: Scalable, production-ready with HA
3. **Bare Metal**: Direct installation without containers

**Deployment Time**: 15-30 minutes (Docker Compose) or 45-90 minutes (Kubernetes)
**Hardware Requirements**: 
- Minimum: 2 vCPU, 4 GB RAM
- Recommended: 4 vCPU, 8 GB RAM (for 50+ servers)

## Prerequisites

### Docker Compose Requirements

```bash
# Install Docker Engine (Linux)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify
docker --version
docker-compose --version

# Allow non-root user (optional)
sudo usermod -aG docker $USER
newgrp docker
```

### Kubernetes Requirements

```bash
# Option 1: Minikube (single-node, dev/test)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube start --cpus=4 --memory=8192

# Option 2: K3s (lightweight, production-ready)
curl -sfL https://get.k3s.io | sh -
sudo kubectl get nodes

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
kubectl get nodes
```

### SQL Server Access

Your on-premise SQL Server must:
- Allow TCP/IP connections
- Have SQL Server Browser service running (for named instances)
- Allow connections from monitoring server IP
- Have MonitoringDB database created

## Architecture Options

### Option 1: Docker Compose (Simple)

```
┌─────────────────────────────────────────────────────────┐
│                  On-Premise Server                      │
│              (Docker Host)                              │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │          Docker Compose Stack                     │  │
│  │                                                   │  │
│  │  ┌────────────────────────────────────────────┐  │  │
│  │  │  Grafana Container                         │  │  │
│  │  │  Port 3000 → Host Port 9001                │  │  │
│  │  │  Env: MONITORINGDB_*                       │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  │                                                   │  │
│  │  ┌────────────────────────────────────────────┐  │  │
│  │  │  Docker Volume: grafana-data               │  │  │
│  │  │  Persistent dashboards/plugins             │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                        │
                        │ SQL connection (port 1433)
                        ▼
            ┌────────────────────────┐
            │   SQL Server           │
            │   MonitoringDB         │
            └────────────────────────┘
```

### Option 2: Kubernetes (HA)

```
┌──────────────────────────────────────────────────────────┐
│              Kubernetes Cluster                          │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Namespace: sql-monitor                            │ │
│  │                                                    │ │
│  │  ┌──────────────────┐       ┌──────────────────┐ │ │
│  │  │ Pod 1: Grafana   │       │ Pod 2: Grafana   │ │ │
│  │  │ 2 vCPU, 4 GB RAM │       │ 2 vCPU, 4 GB RAM │ │ │
│  │  └────────┬─────────┘       └────────┬─────────┘ │ │
│  │           │                           │           │ │
│  │           └───────────┬───────────────┘           │ │
│  │                       │                           │ │
│  │              ┌────────▼─────────┐                 │ │
│  │              │   LoadBalancer   │                 │ │
│  │              │   Service        │                 │ │
│  │              │   Port 3000      │                 │ │
│  │              └──────────────────┘                 │ │
│  │                                                    │ │
│  │  ┌──────────────────┐  ┌──────────────────────┐  │ │
│  │  │ ConfigMap        │  │ Secret               │  │ │
│  │  │ (DB config)      │  │ (Passwords)          │  │ │
│  │  └──────────────────┘  └──────────────────────┘  │ │
│  │                                                    │ │
│  │  ┌──────────────────┐                             │ │
│  │  │ PersistentVolume │                             │ │
│  │  │ (Dashboards)     │                             │ │
│  │  └──────────────────┘                             │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                        │
                        │ SQL connection
                        ▼
            ┌────────────────────────┐
            │   SQL Server           │
            │   MonitoringDB         │
            └────────────────────────┘
```

## Docker Compose Deployment

### Step 1: Clone Repository

```bash
git clone https://github.com/dbbuilder/sql-monitor.git
cd sql-monitor
```

### Step 2: Create Environment File

```bash
# Create .env file
cat > .env <<EOF
# MonitoringDB Connection
MONITORINGDB_SERVER=sql-server.example.com
MONITORINGDB_PORT=1433
MONITORINGDB_DATABASE=MonitoringDB
MONITORINGDB_USER=monitor_api
MONITORINGDB_PASSWORD=SecurePassword123!

# Grafana Configuration
GF_SECURITY_ADMIN_PASSWORD=Admin123!Secure
GF_SERVER_HTTP_PORT=3000
GF_SERVER_ROOT_URL=http://your-server:9001

# Dashboard Download
DASHBOARD_DOWNLOAD=true
GITHUB_REPO=https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards
EOF

# Secure the file
chmod 600 .env
```

### Step 3: Deploy with Docker Compose

```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f grafana

# Check status
docker-compose ps

# Access Grafana
# Open browser: http://your-server:9001
# Username: admin
# Password: (from .env file)
```

### Step 4: Verify Deployment

```bash
# Check container health
docker-compose ps
docker inspect sql-monitor-grafana-1 | grep -A 5 Health

# Test database connection
docker-compose exec grafana sh -c '
apk add --no-cache freetds
cat > /tmp/test.sql <<SQL
SELECT @@VERSION;
SQL
tsql -S $MONITORINGDB_SERVER -p $MONITORINGDB_PORT -U $MONITORINGDB_USER -P $MONITORINGDB_PASSWORD < /tmp/test.sql
'

# Check Grafana health
curl http://localhost:9001/api/health
```

## Kubernetes Deployment

### Step 1: Create Namespace

```bash
# Create namespace
kubectl create namespace sql-monitor

# Set as default
kubectl config set-context --current --namespace=sql-monitor
```

### Step 2: Create Secrets

```bash
# Create secret for database password
kubectl create secret generic monitoringdb-secret \
    --from-literal=password='SecurePassword123!' \
    --namespace=sql-monitor

# Create secret for Grafana admin password
kubectl create secret generic grafana-secret \
    --from-literal=admin-password='Admin123!Secure' \
    --namespace=sql-monitor

# Verify
kubectl get secrets
```

### Step 3: Create ConfigMap

```bash
# Create ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: sql-monitor-config
  namespace: sql-monitor
data:
  MONITORINGDB_SERVER: "sql-server.example.com"
  MONITORINGDB_PORT: "1433"
  MONITORINGDB_DATABASE: "MonitoringDB"
  MONITORINGDB_USER: "monitor_api"
  DASHBOARD_DOWNLOAD: "true"
  GITHUB_REPO: "https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards"
EOF

# Verify
kubectl get configmaps
kubectl describe configmap sql-monitor-config
```

### Step 4: Create Persistent Volume Claim

```bash
# Create PVC for Grafana data
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
  namespace: sql-monitor
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard  # Change to your storage class
EOF

# Verify
kubectl get pvc
```

### Step 5: Create Deployment

```bash
# Create Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sql-monitor-grafana
  namespace: sql-monitor
  labels:
    app: grafana
spec:
  replicas: 2
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: your-registry/sql-monitor-grafana:latest
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: MONITORINGDB_SERVER
          valueFrom:
            configMapKeyRef:
              name: sql-monitor-config
              key: MONITORINGDB_SERVER
        - name: MONITORINGDB_PORT
          valueFrom:
            configMapKeyRef:
              name: sql-monitor-config
              key: MONITORINGDB_PORT
        - name: MONITORINGDB_DATABASE
          valueFrom:
            configMapKeyRef:
              name: sql-monitor-config
              key: MONITORINGDB_DATABASE
        - name: MONITORINGDB_USER
          valueFrom:
            configMapKeyRef:
              name: sql-monitor-config
              key: MONITORINGDB_USER
        - name: MONITORINGDB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: monitoringdb-secret
              key: password
        - name: GF_SECURITY_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: grafana-secret
              key: admin-password
        - name: DASHBOARD_DOWNLOAD
          valueFrom:
            configMapKeyRef:
              name: sql-monitor-config
              key: DASHBOARD_DOWNLOAD
        - name: GITHUB_REPO
          valueFrom:
            configMapKeyRef:
              name: sql-monitor-config
              key: GITHUB_REPO
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
      volumes:
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: grafana-pvc
EOF

# Verify
kubectl get deployments
kubectl get pods
kubectl logs -f deployment/sql-monitor-grafana
```

### Step 6: Create Service

```bash
# Create LoadBalancer Service (or NodePort)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: sql-monitor-grafana
  namespace: sql-monitor
spec:
  type: LoadBalancer  # Change to NodePort if no LoadBalancer available
  selector:
    app: grafana
  ports:
  - name: http
    port: 3000
    targetPort: 3000
    # nodePort: 30300  # Uncomment for NodePort
EOF

# Get service details
kubectl get services
kubectl describe service sql-monitor-grafana

# Get external IP (if LoadBalancer)
kubectl get service sql-monitor-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Or get NodePort (if NodePort)
kubectl get service sql-monitor-grafana -o jsonpath='{.spec.ports[0].nodePort}'
```

### Step 7: Create Ingress (Optional, for HTTPS)

```bash
# Install NGINX Ingress Controller (if not installed)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# Create Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sql-monitor-ingress
  namespace: sql-monitor
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod  # If using cert-manager
spec:
  tls:
  - hosts:
    - grafana.example.com
    secretName: grafana-tls
  rules:
  - host: grafana.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sql-monitor-grafana
            port:
              number: 3000
EOF

# Verify
kubectl get ingress
kubectl describe ingress sql-monitor-ingress
```

## Bare Metal Deployment

### Step 1: Install Grafana

```bash
# Ubuntu/Debian
sudo apt-get install -y software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y grafana

# RHEL/CentOS
sudo yum install -y https://dl.grafana.com/oss/release/grafana-10.2.0-1.x86_64.rpm

# Start Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
sudo systemctl status grafana-server
```

### Step 2: Configure Grafana

```bash
# Edit configuration
sudo nano /etc/grafana/grafana.ini

# Key settings:
[server]
http_port = 3000
domain = grafana.example.com
root_url = http://grafana.example.com

[security]
admin_user = admin
admin_password = Admin123!Secure

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

# Restart Grafana
sudo systemctl restart grafana-server
```

### Step 3: Configure Datasource

```bash
# Create datasource configuration
sudo cat > /etc/grafana/provisioning/datasources/monitoringdb.yaml <<EOF
apiVersion: 1
datasources:
  - name: MonitoringDB
    type: mssql
    uid: PACBEEDECF159CDCA
    access: proxy
    url: sql-server.example.com:1433
    database: MonitoringDB
    user: monitor_api
    secureJsonData:
      password: SecurePassword123!
    jsonData:
      maxOpenConns: 10
      maxIdleConns: 2
      connMaxLifetime: 14400
      encrypt: 'true'
      tlsSkipVerify: true
    editable: false
    isDefault: true
EOF

# Restart Grafana
sudo systemctl restart grafana-server
```

### Step 4: Install Dashboards

```bash
# Download dashboards
sudo mkdir -p /var/lib/grafana/dashboards
cd /var/lib/grafana/dashboards

GITHUB_REPO="https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards"
for dashboard in $(curl -s https://api.github.com/repos/dbbuilder/sql-monitor/contents/public/dashboards | jq -r '.[].name'); do
    sudo curl -O "${GITHUB_REPO}/${dashboard}"
done

# Set ownership
sudo chown -R grafana:grafana /var/lib/grafana/dashboards

# Create dashboard provisioning config
sudo cat > /etc/grafana/provisioning/dashboards/sql-monitor.yaml <<EOF
apiVersion: 1
providers:
  - name: 'SQL Monitor'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

# Restart Grafana
sudo systemctl restart grafana-server
```

## Configuration

### Reverse Proxy with NGINX

```bash
# Install NGINX
sudo apt-get install -y nginx

# Create configuration
sudo cat > /etc/nginx/sites-available/grafana <<EOF
server {
    listen 80;
    server_name grafana.example.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable site
sudo ln -s /etc/nginx/sites-available/grafana /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### SSL with Let's Encrypt

```bash
# Install Certbot
sudo apt-get install -y certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d grafana.example.com

# Auto-renewal (already configured by certbot)
sudo systemctl status certbot.timer
```

## Maintenance

### Docker Compose Updates

```bash
# Pull latest image
docker-compose pull

# Restart services
docker-compose down
docker-compose up -d

# View logs
docker-compose logs -f
```

### Kubernetes Updates

```bash
# Update image
kubectl set image deployment/sql-monitor-grafana \
    grafana=your-registry/sql-monitor-grafana:v2.0 \
    --namespace=sql-monitor

# Rollback if needed
kubectl rollout undo deployment/sql-monitor-grafana --namespace=sql-monitor

# Check rollout status
kubectl rollout status deployment/sql-monitor-grafana --namespace=sql-monitor
```

### Backup and Restore

**Docker Compose:**
```bash
# Backup Grafana data
docker run --rm \
    --volumes-from sql-monitor-grafana-1 \
    -v $(pwd):/backup \
    ubuntu tar czf /backup/grafana-backup-$(date +%Y%m%d).tar.gz /var/lib/grafana

# Restore
docker run --rm \
    --volumes-from sql-monitor-grafana-1 \
    -v $(pwd):/backup \
    ubuntu bash -c "cd / && tar xzf /backup/grafana-backup-20251030.tar.gz"
```

**Kubernetes:**
```bash
# Backup PVC
kubectl exec -it <POD_NAME> -- tar czf /tmp/backup.tar.gz /var/lib/grafana
kubectl cp <POD_NAME>:/tmp/backup.tar.gz ./grafana-backup-$(date +%Y%m%d).tar.gz

# Restore
kubectl cp ./grafana-backup-20251030.tar.gz <POD_NAME>:/tmp/backup.tar.gz
kubectl exec -it <POD_NAME> -- tar xzf /tmp/backup.tar.gz -C /
```

## Troubleshooting

### Docker Compose Issues

```bash
# Container won't start
docker-compose logs grafana
docker inspect sql-monitor-grafana-1

# Database connection failed
docker-compose exec grafana ping sql-server.example.com
docker-compose exec grafana nc -zv sql-server.example.com 1433

# Permission issues
docker-compose exec grafana ls -la /var/lib/grafana
docker-compose exec grafana chown -R grafana:grafana /var/lib/grafana
```

### Kubernetes Issues

```bash
# Pod not running
kubectl get pods
kubectl describe pod <POD_NAME>
kubectl logs <POD_NAME>

# Service not accessible
kubectl get services
kubectl describe service sql-monitor-grafana
kubectl get endpoints sql-monitor-grafana

# PVC issues
kubectl get pvc
kubectl describe pvc grafana-pvc
```

### Performance Tuning

**Docker Compose:**
```yaml
# docker-compose.yml
services:
  grafana:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
```

**Kubernetes:**
```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## Next Steps

1. **Configure Monitoring**: Set up alerts for container health
2. **Implement Backup Strategy**: Schedule regular backups
3. **Security Hardening**: Configure firewall, SSL, authentication
4. **Load Testing**: Verify performance under load
5. **Documentation**: Document your specific configuration

## Support

- **Docker Documentation**: https://docs.docker.com
- **Kubernetes Documentation**: https://kubernetes.io/docs
- **GitHub Issues**: https://github.com/dbbuilder/sql-monitor/issues
- **Discussions**: https://github.com/dbbuilder/sql-monitor/discussions
