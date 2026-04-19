#!/bin/bash
# =============================================================
# @File: auto_reparar.sh
# @Ubicación: Se ejecuta en el SERVIDOR Docker (10.0.10.10)
# @Description: Script de resiliencia que repara la conectividad
#   del servidor cada vez que arranca o se pierde la conexión.
#
# @Problema que resuelve:
#   En VMware, el servidor Docker (10.0.10.10) a veces arranca ANTES
#   que el router virtual (10.0.10.1). Sin el router, el servidor
#   no puede enviar tráfico hacia la red de Oficina (10.0.20.0/24)
#   ni recibe las peticiones DNAT correctamente.
#
# @Qué hace este script (en orden):
#   1. Espera activamente a que el router esté online (ping)
#   2. Desactiva rp_filter (filtro de ruta inversa del kernel)
#   3. Añade la ruta estática hacia la red de oficina
#   4. Configura reglas DNAT de bypass para redirigir tráfico
#      directamente a los contenedores Docker por su IP interna
#
# @Cuándo ejecutarlo: Manualmente tras un reinicio, o configurar
#   como servicio systemd para que se ejecute al arrancar.
# =============================================================

echo "--- Iniciando Auto-Reparación del Servidor ---"

# ----- PASO 1: ESPERA ACTIVA AL ROUTER -----
# @Para qué sirve: No tiene sentido configurar rutas si el router
#   no está encendido. Este bucle intenta hacer ping cada 2 segundos
#   hasta que el router (10.0.10.1) responda. Así evitamos errores
#   de configuración por arrancar demasiado pronto.
echo "Esperando a que el Router (10.0.10.1) esté online..."
while ! ping -c 1 -W 1 10.0.10.1 > /dev/null; do
    echo "Router no detectado. Reintentando en 2 segundos..."
    sleep 2
done
echo "¡Router detectado! Continuando..."

# ----- PASO 2: DESACTIVAR RP_FILTER (Reverse Path Filtering) -----
# @Para qué sirve: El kernel Linux tiene un filtro de seguridad que
#   descarta paquetes si la dirección de origen no coincide con la
#   ruta de retorno esperada. En nuestra infraestructura con múltiples
#   IPs virtuales (10.0.10.10 y 10.0.10.20 en la misma interfaz),
#   esto causa problemas. Al ponerlo a 0, permitimos que el tráfico
#   fluya correctamente entre todas las IPs.
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
sudo sysctl -w net.ipv4.conf.ens33.rp_filter=0

# ----- PASO 3: RUTA ESTÁTICA HACIA LA RED DE OFICINA -----
# @Para qué sirve: El servidor solo conoce su propia red (10.0.10.0/24).
#   Para que los PCs de la oficina (10.0.20.0/24) puedan acceder a
#   los servicios, el servidor necesita saber que esa red está detrás
#   del router (10.0.10.1). Sin esta ruta, las respuestas se perderían.
sudo ip route del 10.0.20.0/24 2>/dev/null          # Borra la ruta anterior (si existe)
sudo ip route add 10.0.20.0/24 via 10.0.10.1 dev ens33  # Añade la ruta correcta

# ----- PASO 4: BYPASS DNAT DE DOCKER -----
# @Para qué sirve: Docker tiene su propio sistema de NAT interno.
#   A veces interfiere con nuestras IPs virtuales (10.0.10.10 y 10.0.10.20).
#   Estas reglas "cortocircuitan" el NAT de Docker redirigiendo el tráfico
#   directamente a la IP interna del contenedor Nginx correspondiente.
#
# @Nota: Las IPs 172.18.0.X son las IPs internas de Docker.
#   Pueden cambiar si se recrean los contenedores. Verificar con:
#   docker inspect nginx_publico | grep IPAddress
#   docker inspect nginx_empresa | grep IPAddress
sudo iptables -t nat -F PREROUTING   # Limpia reglas DNAT anteriores

# Tráfico web público (10.0.10.10) → Nginx público (172.18.0.6)
sudo iptables -t nat -A PREROUTING -d 10.0.10.10 -p tcp --dport 80 -j DNAT --to-destination 172.18.0.6:80
sudo iptables -t nat -A PREROUTING -d 10.0.10.10 -p tcp --dport 443 -j DNAT --to-destination 172.18.0.6:443

# Tráfico de gestión (10.0.10.20) → Nginx empresa (172.18.0.10)
sudo iptables -t nat -A PREROUTING -d 10.0.10.20 -p tcp --dport 80 -j DNAT --to-destination 172.18.0.10:80
sudo iptables -t nat -A PREROUTING -d 10.0.10.20 -p tcp --dport 443 -j DNAT --to-destination 172.18.0.10:443
sudo iptables -t nat -A PREROUTING -d 10.0.10.20 -p tcp --dport 8443 -j DNAT --to-destination 172.18.0.10:8443
sudo iptables -t nat -A PREROUTING -d 10.0.10.20 -p tcp --dport 9443 -j DNAT --to-destination 172.18.0.10:9443

echo "--- ¡Servidor Reparado y Sincronizado con el Router! ---"
