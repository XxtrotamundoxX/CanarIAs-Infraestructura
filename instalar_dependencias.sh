#!/bin/bash

# @File: instalar_dependencias.sh
# @Description: Preparación del entorno de servidor desde cero.
# @Logic: Instalación de Docker y configuración de la red puente.

echo "--- Instalando Dependencias del Sistema ---"

# 1. Actualizar repositorio e instalar Docker
sudo apt update && sudo apt install -y docker.io docker-compose

# 2. Habilitar servicio de Docker
sudo systemctl enable --now docker

# 3. Crear red común de infraestructura
# @Logic: Esta red permite que los contenedores de distintos archivos YAML se vean entre sí.
docker network create infraestructura_app_net || echo "La red ya existe."

# 4. Crear volumen externo para Portainer
docker volume create portainer_data_vol

echo "--- Entorno Preparado ---"
