#!/bin/bash

# Funções para mensagens coloridas
function info {
    echo -e "\e[32m[INFO] $1\e[0m"
}

function error {
    echo -e "\e[31m[ERROR] $1\e[0m"
}

function warning {
    echo -e "\e[33m[WARNING] $1\e[0m"
}

# Verificação de pré-requisitos
info "Verificando pré-requisitos..."
if ! [ -x "$(command -v docker)" ]; then
    error "Docker não está instalado. Por favor, instale o Docker e tente novamente."
    exit 1
fi

if ! [ -x "$(command -v docker-compose)" ]; then
    error "Docker Compose não está instalado. Por favor, instale o Docker Compose e tente novamente."
    exit 1
fi

# Criação de diretórios necessários
info "Criando diretórios necessários..."
mkdir -p mattermost/{data,logs,config,plugins,client-plugins}
mkdir -p nginx/{conf.d,ssl}

# Criação do arquivo .env
info "Criando arquivo .env..."
cat <<EOF > .env
DOMAIN=team.cnmfs.me
EMAIL=dev@cnmfs.me
MATTERMOST_DB_PASS=$(openssl rand -base64 32)
EOF

# Criação do arquivo docker-compose.yml
info "Criando arquivo docker-compose.yml..."
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  mattermost:
    image: mattermost/mattermost-team-edition:latest
    container_name: mattermost
    restart: unless-stopped
    volumes:
      - ./mattermost/data:/mattermost/data
      - ./mattermost/logs:/mattermost/logs
      - ./mattermost/config:/mattermost/config
      - ./mattermost/plugins:/mattermost/plugins
      - ./mattermost/client-plugins:/mattermost/client-plugins
    environment:
      - MM_USERNAME=admin
      - MM_PASSWORD=admin
      - MM_DBNAME=mattermost
      - MM_DBUSER=mmuser
      - MM_DBPASS=\${MATTERMOST_DB_PASS}
      - MM_DBHOST=db:5432
    depends_on:
      - db
      - elasticsearch

  db:
    image: postgres:13-alpine
    container_name: mattermost-db
    restart: unless-stopped
    volumes:
      - ./mattermost/db:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=mattermost
      - POSTGRES_USER=mmuser
      - POSTGRES_PASSWORD=\${MATTERMOST_DB_PASS}

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.10.1
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    volumes:
      - ./elasticsearch/data:/usr/share/elasticsearch/data

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/ssl:/etc/nginx/ssl
      - ./nginx/logs:/var/log/nginx
    depends_on:
      - mattermost

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    volumes:
      - ./prometheus:/etc/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana:/var/lib/grafana

  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - ./jenkins:/var/jenkins_home
    environment:
      - JENKINS_OPTS=--prefix=/jenkins
EOF

# Configuração do Nginx
info "Configurando Nginx..."
cat <<EOF > nginx/conf.d/mattermost.conf
server {
    listen 80;
    server_name \${DOMAIN};

    location / {
        proxy_pass http://mattermost:8065;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Inicialização dos contêineres
info "Inicializando contêineres..."
docker-compose up -d

# Verificação final dos contêineres
info "Verificando contêineres..."
if [ $(docker ps -q | wc -l) -eq 0 ]; then
    error "Nenhum contêiner está em execução. Verifique os logs para mais detalhes."
    exit 1
fi

info "Todos os contêineres foram iniciados com sucesso."

# Mensagem final ao usuário
info "Instalação concluída. Acesse o Mattermost em http://\${DOMAIN}"
