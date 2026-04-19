# **INFORME DEL PROYECTO FINAL DE CICLO (ASIR)**

### **Diseño, Bastionado y Despliegue de Infraestructura Corporativa con Docker, Nginx, PKI y Enrutamiento Avanzado**

**Autor:** Jeremy  
**Ciclo:** Técnico Superior en Administración de Sistemas Informáticos en Red (ASIR)  
**Proyecto:** Infraestructura Tecnológica para "CanarIAs S.L.L."  
**Fecha:** Abril 2026  

---

## **1. INTRODUCCIÓN**

El presente proyecto consiste en el diseño, despliegue y securización completa de la infraestructura tecnológica de una empresa ficticia llamada "CanarIAs S.L.L.". La idea nace de la necesidad de crear un entorno profesional que simule lo que un técnico ASIR se encontraría en una empresa real: servidores web, correo electrónico corporativo, gestión de contraseñas, monitorización y, sobre todo, seguridad de red.

El reto principal del proyecto es hacer que convivan dos mundos opuestos en la misma infraestructura: por un lado, una **zona pública (DMZ)** accesible desde Internet con el sitio web WordPress de la empresa; y por otro, una **zona de gestión privada** con herramientas sensibles (contraseñas, correo, panel Docker) que solo deben ser accesibles por los administradores.

Para conseguir esto, he descartado las topologías de "red plana" (donde todo está en la misma red) y he implementado una arquitectura basada en el paradigma de **Defensa en Profundidad (Defense in Depth)**: un router Linux que segmenta la red en 3 subredes independientes, un firewall con reglas de bloqueo explícitas, proxies inversos Nginx que gestionan el acceso HTTPS, y una PKI propia que cifra todas las comunicaciones internas.

Todo el despliegue de servicios se realiza con **Docker y Docker Compose**, lo que permite levantar la infraestructura completa en minutos y garantizar la portabilidad del proyecto.

---

## **2. OBJETIVOS**

### Objetivos principales

1. **Segmentar la red corporativa** en 3 zonas aisladas (Servidores, Oficina, Invitados) con un Router Linux perimetral que controle el tráfico entre ellas.
2. **Desplegar servicios web en Alta Disponibilidad (HA)** con un clúster de 3 réplicas de WordPress balanceadas por Nginx.
3. **Implementar un firewall funcional (DMZ)** basado en iptables que bloquee el acceso de invitados y tráfico externo a los servicios de gestión, permitiendo solo el acceso a la web pública.
4. **Gestionar contraseñas de forma segura** con Vaultwarden (compatible con Bitwarden) y Docker Secrets para no exponer credenciales en los archivos de configuración.
5. **Desplegar un servidor de correo completo** con envío (SMTP), recepción (IMAP), antispam (SpamAssassin) y protección contra fuerza bruta (Fail2Ban).
6. **Crear una PKI propia** que permita cifrar todas las comunicaciones HTTPS internas con certificados válidos firmados por nuestra propia Autoridad Certificadora.
7. **Monitorizar el estado de todos los servicios** en tiempo real con Uptime Kuma para detectar caídas antes de que afecten a los usuarios.
8. **Garantizar la resiliencia** del sistema completo ante caídas eléctricas o reinicios no programados, con scripts de auto-reparación y políticas de reinicio automático.

### Objetivo secundario

9. **Acceso remoto seguro** mediante Tailscale (VPN mesh WireGuard) para permitir a los administradores gestionar la infraestructura desde casa sin abrir puertos en el router.

---

## **3. HERRAMIENTAS**

### Software y tecnologías utilizadas

| Herramienta | Versión/Tipo | Para qué se usa en el proyecto |
|:---|:---|:---|
| **VMware Workstation** | Virtualización | Simular las máquinas (router + servidor) en portátil |
| **Ubuntu Server 22.04** | Sistema operativo | Base para el Router y el Servidor Docker |
| **Docker + Docker Compose** | Contenedores | Desplegar todos los servicios como microservicios |
| **Nginx** | Proxy inverso | Balanceo de carga, HTTPS, Virtual Hosts |
| **WordPress (Bitnami)** | CMS | Web pública de la empresa |
| **MariaDB (Bitnami)** | Base de datos | Almacenar contenido de WordPress |
| **Vaultwarden** | Gestor de contraseñas | Almacenamiento cifrado de credenciales |
| **Portainer CE** | Orquestador Docker | Panel gráfico para gestionar contenedores |
| **Docker-Mailserver** | Servidor de correo | SMTP/IMAP con Postfix, Dovecot, SpamAssassin, Fail2Ban |
| **Rainloop** | Webmail | Cliente web de correo electrónico |
| **Uptime Kuma** | Monitorización | Dashboard de estado de servicios en tiempo real |
| **ISC DHCP Server** | Servidor DHCP | Asignación automática de IPs en las 3 subredes |
| **Dnsmasq** | Servidor DNS | Resolución de dominios `*.canarias.local` |
| **iptables** | Firewall | Control de tráfico entre redes (DMZ) |
| **Tailscale** | VPN mesh | Acceso remoto seguro desde casa (WireGuard) |
| **OpenSSL** | Criptografía | Generación de certificados SSL/TLS (PKI) |
| **Bash** | Scripting | Automatización de backups, reparaciones y despliegue |

---

## **4. DESARROLLO**

### **4.1. Topología de Red**

El primer paso fue diseñar la red. El objetivo era aislar el tráfico de los diferentes tipos de usuarios (empleados, invitados, público de Internet) para que un compromiso en una zona no afecte a las demás.

El router Linux dispone de 4 interfaces de red:

```text
                    [ INTERNET / WAN ]
                           |
                    (ens33) | IP dinámica (192.168.139.131)
                +---------------------+
                |  ROUTER / FIREWALL  |
                |     (canarias)      |
                +---------------------+
               /         |           \
     (ens37)  /    (ens38)|            \ (ens39)
             /            |             \
 [ RED SERVIDORES ]  [ RED OFICINA ]  [ RED INVITADOS ]
   10.0.10.0/24       10.0.20.0/24      10.0.30.0/24
                          
   10.0.10.10 → WordPress (público)      
   10.0.10.20 → Gestión (privado)        
```

**[📸 Haz una captura del diagrama de red en VMware mostrando las 3 redes virtuales (VMnet) conectadas al router y al servidor]**

---

### **4.2. Configuración del Router Perimetral**

#### 4.2.1. Habilitación del reenvío de paquetes

Para que la máquina Linux actúe como un router real, hay que activar el reenvío de paquetes IP en el kernel:

```bash
# Activar IP forwarding (permanente)
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**[📸 Lanza `sysctl net.ipv4.ip_forward` en el router y haz una captura mostrando que devuelve `= 1`]**

#### 4.2.2. Servidor DHCP (`isc-dhcp-server`)

Configuré el servidor DHCP para que los PCs de la oficina e invitados reciban sus IPs automáticamente al conectarse, sin necesidad de configurar nada a mano. Además, utilicé la **Opción 121 (RFC 3442)** para inyectar rutas estáticas directamente en los clientes.

**Archivo: `/etc/dhcp/dhcpd.conf`**

```conf
# Opciones personalizadas para inyectar rutas automáticamente
# La Opción 121 envía rutas estáticas al cliente en el momento de la concesión DHCP
option classless-static-routes code 121 = array of unsigned integer 8;
option ms-classless-static-routes code 249 = array of unsigned integer 8;

# --- RED SERVIDORES (ens37 - 10.0.10.0/24) ---
# Sin pool dinámica: solo el servidor Docker tiene IP aquí (reservada por MAC)
subnet 10.0.10.0 netmask 255.255.255.0 {
    option routers 10.0.10.1;
    option domain-name-servers 10.0.20.1;
    option domain-name "canarias.local";
}

# Reserva estática: el servidor SIEMPRE recibe 10.0.10.10
host servidor-canarias {
    hardware ethernet 00:0c:29:de:1b:a1;
    fixed-address 10.0.10.10;
}

# --- RED OFICINA (ens38 - 10.0.20.0/24) ---
# Los empleados reciben IPs entre .100 y .200
subnet 10.0.20.0 netmask 255.255.255.0 {
    option routers 10.0.20.1;
    option domain-name-servers 10.0.20.1;
    option domain-name "canarias.local";
    range 10.0.20.100 10.0.20.200;

    # Opción 121: "Para ir a 10.0.10.0/24, usa la puerta 10.0.20.1"
    option classless-static-routes 24, 10,0,10, 10,0,20,1, 0, 10,0,20,1;
    option ms-classless-static-routes 24, 10,0,10, 10,0,20,1, 0, 10,0,20,1;

    # Reservas por MAC para los administradores
    host pc-principal { hardware ethernet 00:0c:29:85:df:4f; fixed-address 10.0.20.20; }
    host pc-aitor     { hardware ethernet 00:0c:29:33:2d:db; fixed-address 10.0.20.25; }
    host pc-jeremy    { hardware ethernet 00:0c:29:16:6e:b2; fixed-address 10.0.20.30; }
    host pc-patricia  { hardware ethernet 00:0c:29:95:34:0d; fixed-address 10.0.20.40; }
    host pc-adonay    { hardware ethernet 00:0c:29:c8:d8:39; fixed-address 10.0.20.50; }
    host pc-ikram     { hardware ethernet 00:0c:29:4c:87:db; fixed-address 10.0.20.60; }
}

# --- RED INVITADOS (ens39 - 10.0.30.0/24) ---
# Tiempo de concesión corto (30 min) para liberar IPs rápido
subnet 10.0.30.0 netmask 255.255.255.0 {
    option routers 10.0.30.1;
    option domain-name-servers 10.0.30.1;
    option domain-name "canarias.local";
    option classless-static-routes 24, 10,0,10, 10,0,30,1, 0, 10,0,30,1;
    option ms-classless-static-routes 24, 10,0,10, 10,0,30,1, 0, 10,0,30,1;
    range 10.0.30.100 10.0.30.200;
    default-lease-time 1800;
}
```

**[📸 Lanza `cat /etc/dhcp/dhcpd.conf` en el router y haz una captura del archivo completo]**

**[📸 Lanza `systemctl status isc-dhcp-server` para demostrar que el servicio está activo]**

#### 4.2.3. Servidor DNS (`dnsmasq`)

Para que los empleados puedan acceder a los servicios escribiendo nombres como `vault.canarias.local` en lugar de IPs, configuré Dnsmasq como servidor DNS local. Se divide en 3 archivos dentro de `/etc/dnsmasq.d/`:

**Archivo 1: `/etc/dnsmasq.d/asir-config`** — Opciones globales:

```conf
# Escuchar en todas las interfaces (necesario para Tailscale)
interface=*
bind-interfaces
# No enviar consultas de dominios locales a Internet
domain-needed
bogus-priv
```

**Archivo 2: `/etc/dnsmasq.d/canarias.conf`** — Resolución forzada de dominios:

```conf
# --- ZONA PÚBLICA (DMZ) ---
# Todo el tráfico web público apunta a 10.0.10.10 (WordPress)
address=/canarias.local/10.0.10.10
address=/www.canarias.local/10.0.10.10
address=/wp.canarias.local/10.0.10.10

# --- ZONA PRIVADA (GESTIÓN) ---
# Los servicios internos apuntan a 10.0.10.20
address=/vault.canarias.local/10.0.10.20
address=/mail.canarias.local/10.0.10.20
address=/docker.canarias.local/10.0.10.20
address=/pki.canarias.local/10.0.10.20
address=/status.canarias.local/10.0.10.20
```

**Archivo 3: `/etc/dnsmasq.d/interfaces.conf`** — Interfaces de escucha:

```conf
interface=ens37       # Red Servidores
interface=ens38       # Red Oficina
interface=ens39       # Red Invitados
interface=tailscale0  # VPN Tailscale
interface=lo          # Loopback local
bind-interfaces
```

**[📸 Lanza `cat /etc/dnsmasq.d/canarias.conf` y haz una captura del contenido]**

**[📸 Desde un PC de oficina, lanza `nslookup vault.canarias.local` y haz una captura mostrando que resuelve a 10.0.10.20]**

---

### **4.3. Firewall con Iptables — Implementación de la DMZ**

Este es uno de los puntos más importantes del proyecto. El firewall define la seguridad real de la red: qué tráfico se permite y qué se bloquea.

La política general es `FORWARD ACCEPT` (permitir por defecto), pero se añaden reglas explícitas de `DROP` para bloquear el acceso a la zona de gestión desde los invitados y desde Internet. Esto se implementa mediante el script `auto_reparar_router.sh`:

```bash
#!/bin/bash
# auto_reparar_router.sh — Script de blindaje DMZ del router

# PASO 1: Limpiar todas las reglas anteriores
iptables -F
iptables -t nat -F
iptables -t mangle -F

# PASO 2: Política por defecto (ACCEPT)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# PASO 3: Optimización MSS para VPN/túneles
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# PASO 4: Reglas INPUT (protección del router)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT              # SSH siempre accesible
iptables -A INPUT -i lo -j ACCEPT                           # Loopback
iptables -A INPUT -i tailscale0 -j ACCEPT                   # VPN Tailscale
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# PASO 5: Reglas FORWARD (control de tráfico entre redes)

# 5.1. Tailscale → Todo = PERMITIDO (acceso VPN)
iptables -A FORWARD -i tailscale0 -j ACCEPT

# 5.2. Oficina (10.0.20.x) → Servidores = TODO PERMITIDO
iptables -A FORWARD -s 10.0.20.0/24 -d 10.0.10.0/24 -j ACCEPT

# 5.3. Conexiones ya establecidas pueden continuar
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# ===== REGLAS DMZ (Protección de la Gestión) =====

# 5.4. Invitados → WordPress = SOLO puertos 80 y 443
iptables -A FORWARD -s 10.0.30.0/24 -d 10.0.10.10 -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -s 10.0.30.0/24 -d 10.0.10.10 -p tcp --dport 443 -j ACCEPT

# 5.5. Invitados → Gestión = BLOQUEADO 🔒
iptables -A FORWARD -s 10.0.30.0/24 -d 10.0.10.20 -j DROP

# 5.6. Internet → Gestión = BLOQUEADO 🔒
iptables -A FORWARD -i ens33 -d 10.0.10.20 -j DROP

# 5.7. SSH entre redes = PERMITIDO (administración)
iptables -A FORWARD -p tcp --dport 22 -j ACCEPT

# 5.8. CANDADO FINAL: Todo lo demás hacia gestión = BLOQUEADO 🔒
iptables -A FORWARD -d 10.0.10.20 -j DROP

# PASO 6: DNAT (publicar WordPress al exterior)
iptables -t nat -A PREROUTING -i ens33 -p tcp --dport 80 -j DNAT --to 10.0.10.10:80
iptables -t nat -A PREROUTING -i ens33 -p tcp --dport 443 -j DNAT --to 10.0.10.10:443

# PASO 7: MASQUERADE (dar salida a Internet)
iptables -t nat -A POSTROUTING -o ens33 -j MASQUERADE
iptables -t nat -A POSTROUTING -o ens37 -j MASQUERADE

# PASO 8: Persistencia
systemctl restart dnsmasq isc-dhcp-server
iptables-save > /etc/iptables/rules.v4
```

**Orden de evaluación de las reglas (de arriba a abajo):**

```
┌───────────────────────────────────────────────────┐
│ 1. Tailscale → ACCEPT            ← VPN pasa      │
│ 2. Oficina → Servidores → ACCEPT ← Empleados     │
│ 3. Establecidas → ACCEPT         ← Respuestas    │
│ 4. Invitados → WP 80/443 → ACCEPT ← Solo web     │
│ 5. Invitados → Gestión → DROP    ← BLOQUEADO 🔒  │
│ 6. Internet → Gestión → DROP     ← BLOQUEADO 🔒  │
│ 7. SSH → ACCEPT                  ← Admin         │
│ 8. → Gestión → DROP (final)      ← Candado 🔒    │
│ Si nada → ACCEPT (política)      ← Resto pasa    │
└───────────────────────────────────────────────────┘
```

**[📸 Lanza `sudo iptables -L FORWARD -n --line-numbers` en el router y haz una captura mostrando las reglas DROP]**

**[📸 Desde un PC de invitados, lanza `curl -k https://10.0.10.10` (debe funcionar → WordPress) y luego `curl -k https://10.0.10.20` (debe dar timeout → Gestión bloqueada). Haz captura de ambos resultados]**

---

### **4.4. Conectividad Remota: Tailscale (VPN Mesh)**

Para poder administrar la infraestructura desde casa sin abrir puertos en el router, instalé Tailscale en el router. Tailscale crea una red VPN mesh cifrada con WireGuard que conecta los dispositivos de los administradores directamente.

El router actúa como **Subnet Router**, exponiendo las redes internas `10.0.10.0/24` y `10.0.20.0/24` a través de la VPN.

**Dispositivos conectados a la red VPN (verificado 18 Abril 2026):**

| IP Tailscale | Nombre | SO | Estado |
|:---|:---|:---|:---|
| `100.101.99.58` | `canarias` (Router) | Linux | Nodo actual |
| `100.112.104.42` | `desktop-1l6ounq` | Windows | Activo |
| `100.76.0.75` | `desktop-pasmvha` | Windows | Idle |
| `100.64.199.121` | `krm` | Windows | Activo |
| `100.116.69.27` | `xiaomi-13t-pro` | Android | Idle |

**[📸 Lanza `tailscale status` en el router y haz una captura mostrando los dispositivos conectados]**

---

### **4.5. Infraestructura de Clave Pública (PKI)**

Vaultwarden requiere obligatoriamente una conexión HTTPS válida. Como no tenemos un dominio público registrado, creé una **Autoridad Certificadora (CA) propia** llamada "CanarIAs Root CA" con OpenSSL.

**El problema que resolví:** Al principio, el certificado solo era válido para `canarias.local`. Cuando cambié la arquitectura a subdominios (`vault.canarias.local`, `docker.canarias.local`), Firefox bloqueaba las conexiones con el error `SSL_ERROR_BAD_CERT_DOMAIN`. La solución fue usar la extensión **SAN (Subject Alternative Name)** para incluir todas las direcciones.

**Archivo de extensiones: `infraestructura/certs/v3.ext`**

```ini
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = canarias.local
DNS.3 = empresa.canarias.local
DNS.4 = vault.canarias.local
DNS.5 = mail.canarias.local
DNS.6 = docker.canarias.local
DNS.7 = pki.canarias.local
DNS.8 = status.canarias.local
DNS.9 = backup.canarias.local
IP.1 = 127.0.0.1
IP.2 = 10.0.10.10
IP.3 = 10.0.10.20
```

**Comandos de generación de certificados:**

```bash
# 1. Generar clave privada de la CA raíz
openssl genrsa -aes256 -out canarias_root.key 4096

# 2. Crear el certificado raíz (autofirmado, válido 10 años)
openssl req -x509 -new -key canarias_root.key -sha256 -days 3650 \
  -out canarias_root.pem \
  -subj "/C=ES/ST=Santa Cruz de Tenerife/L=Adeje/O=CanarIAs S.L.L./OU=IT Security/CN=CanarIAs Root CA"

# 3. Generar clave del servidor y solicitud de firma (CSR)
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
  -subj "/C=ES/ST=Santa Cruz de Tenerife/L=Adeje/O=CanarIAs S.L.L./CN=canarias.local"

# 4. Firmar el certificado con la CA inyectando los SANs
openssl x509 -req -in server.csr -CA canarias_root.pem -CAkey canarias_root.key \
  -CAcreateserial -out server.crt -days 365 -sha256 -extfile v3.ext
```

Para que los navegadores confíen en nuestros certificados, creé un **Portal PKI** (`pki.html`) donde los empleados pueden descargar e instalar el certificado raíz.

**[📸 Abre `https://pki.canarias.local` en el navegador y haz una captura del portal de descarga de certificados]**

**[📸 Muestra el candado verde en el navegador al acceder a `https://vault.canarias.local` después de instalar la CA]**

---

### **4.6. Servicios Docker — Zona Pública (WordPress HA)**

La web pública de la empresa se despliega con **Alta Disponibilidad**: 3 réplicas de WordPress corriendo en paralelo, balanceadas por Nginx con `ip_hash` para mantener las sesiones de usuario.

**Archivo: `infraestructura/publico/docker-compose.yml`**

```yaml
version: '3.8'
services:
  # Balanceador de carga Nginx
  nginx-web:
    image: nginx:alpine
    container_name: nginx_publico
    ports:
      - "10.0.10.10:80:80"     # Solo escucha en la IP pública
      - "10.0.10.10:443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ../certs:/etc/nginx/certs:ro

  # WordPress con 3 réplicas (Alta Disponibilidad)
  wordpress:
    image: bitnami/wordpress:latest
    deploy:
      replicas: 3              # 3 instancias simultáneas
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
    environment:
      - WORDPRESS_DATABASE_HOST=mariadb
      - WORDPRESS_DATABASE_PASSWORD_FILE=/run/secrets/db_pass  # Docker Secrets
    secrets:
      - db_pass
    volumes:
      - ../wordpress_data:/bitnami/wordpress

  # Base de datos MariaDB
  mariadb:
    image: bitnami/mariadb:latest
    container_name: base_datos
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
    environment:
      - MARIADB_PASSWORD_FILE=/run/secrets/db_pass
      - MARIADB_ROOT_PASSWORD_FILE=/run/secrets/db_root_pass
    volumes:
      - ../db_data:/bitnami/mariadb

# Las contraseñas se leen de archivos (Docker Secrets)
secrets:
  db_pass:
    file: ../secrets/db_password.txt
  db_root_pass:
    file: ../secrets/db_root_password.txt
```

La configuración de Nginx para el balanceo utiliza `ip_hash` para garantizar la **persistencia de sesión** (siempre envía al mismo usuario al mismo contenedor):

**Fragmento clave de `infraestructura/publico/nginx.conf`:**

```nginx
upstream wordpress_cluster {
    ip_hash;                    # Persistencia de sesión por IP
    server wordpress:8080;      # Docker balancea entre las 3 réplicas
}

server {
    listen 443 ssl;
    server_name canarias.local 10.0.10.10;
    ssl_certificate     /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;

    location / {
        proxy_pass http://wordpress_cluster;
    }
}
```

**[📸 Abre `https://canarias.local` en el navegador y haz una captura de la web de WordPress funcionando]**

**[📸 Lanza `docker ps --filter name=publico-wordpress` para mostrar las 3 réplicas corriendo]**

---

### **4.7. Servicios Docker — Zona de Gestión (Privada)**

Los servicios internos están protegidos por el firewall y solo son accesibles desde la red de oficina o por VPN.

**Archivo: `infraestructura/gestion/docker-compose.yml`** (servicios principales):

```yaml
services:
  # Vaultwarden — Gestor de contraseñas (compatible Bitwarden)
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: cofre_seguro
    environment:
      - SIGNUPS_ALLOWED=true
    volumes:
      - ../vault_data:/data

  # Portainer — Panel gráfico de gestión de Docker
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer_web
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # Acceso al motor Docker

  # Rainloop — Cliente webmail
  webmail:
    image: hardware/rainloop:latest
    container_name: webmail_canarias
    volumes:
      - ../correo/rainloop-data:/rainloop/data

  # Uptime Kuma — Monitor de estado
  monitor_kuma:
    image: louislam/uptime-kuma:1
    container_name: monitor_kuma
    dns:
      - 10.0.10.1               # Usa el DNS del router
    volumes:
      - ../kuma_data:/app/data

  # Nginx — Proxy inverso de gestión
  nginx-admin:
    image: nginx:alpine
    container_name: nginx_empresa
    ports:
      - "10.0.10.20:80:80"
      - "10.0.10.20:443:443"
```

El Proxy Inverso de gestión (`nginx.conf`) ofrece **dos modos de acceso**: por dominio (Virtual Hosts) y por IP (rutas de emergencia). Esto es lo que yo llamo la **Arquitectura Híbrida**:

```nginx
# MODO 1: Acceso por DOMINIO (recomendado)
server {
    listen 443 ssl;
    server_name vault.canarias.local;
    location / { proxy_pass http://cofre_seguro:80; }
}

# MODO 2: Acceso por IP (emergencia, sin DNS)
server {
    listen 443 ssl default_server;
    server_name 10.0.10.20;

    location /mail/   { proxy_pass http://webmail_canarias:8888/; }
    location /vault/  { proxy_pass http://cofre_seguro:80/; }
    # Kuma es SPA Vue.js, no soporta subpath → redirige al dominio
    location /status  { return 302 https://status.canarias.local/; }

    # Página principal: Portal PKI
    location / {
        root /usr/share/nginx/html;
        index pki.html;
    }
}
```

**[📸 Abre `https://vault.canarias.local` y haz una captura de Vaultwarden funcionando]**

**[📸 Abre `https://docker.canarias.local` y haz una captura del dashboard de Portainer con los contenedores visibles]**

**[📸 Abre `https://status.canarias.local` y haz una captura del dashboard de Uptime Kuma mostrando todos los servicios en verde]**

---

### **4.8. Servidor de Correo Corporativo**

Para el correo electrónico interno, desplegué Docker-Mailserver con Postfix (envío), Dovecot (lectura), SpamAssassin (antispam) y Fail2Ban (protección contra fuerza bruta).

**Archivo: `infraestructura/correo/docker-compose-mail.yml`**

```yaml
services:
  mailserver:
    image: docker.io/mailserver/docker-mailserver:latest
    container_name: servidor_correo
    hostname: mail.canarias.local
    domainname: canarias.local
    ports:
      - "25:25"     # SMTP (entrada entre servidores)
      - "143:143"   # IMAP (lectura de correo)
      - "465:465"   # SMTPS (envío seguro)
      - "587:587"   # Submission (envío desde clientes)
      - "993:993"   # IMAPS (lectura segura)
    environment:
      - ENABLE_SPAMASSASSIN=1     # Filtro antispam
      - ENABLE_FAIL2BAN=1          # Protección contra fuerza bruta
      - SSL_TYPE=manual            # Usa nuestros propios certificados
      - SSL_CERT_PATH=/tmp/certs/server.crt
      - SSL_KEY_PATH=/tmp/certs/server.key
    volumes:
      - ./mail-data/:/var/mail/
      - ./mail-config/:/tmp/docker-mailserver/
      - ../certs/:/tmp/certs/:ro
```

Las cuentas de correo se configuran en `mail-config/postfix-accounts.cf` y los alias de distribución en `postfix-virtual.cf`:

```
# postfix-accounts.cf — Cuentas de correo
admin@canarias.local|{SHA512-CRYPT}$6$...
jeremy@canarias.local|{SHA512-CRYPT}$6$...

# postfix-virtual.cf — Listas de distribución  
equipo@canarias.local admin@canarias.local,...
soporte@canarias.local admin@canarias.local,...
```

**[📸 Abre `https://mail.canarias.local/mail/` y haz una captura de Rainloop con la bandeja de entrada]**

**[📸 Envía un correo de prueba entre dos cuentas y haz una captura mostrando el envío y la recepción]**

---

### **4.9. Scripts de Resiliencia y Auto-Reparación**

Uno de los problemas que encontré con VMware es que al reiniciar las máquinas virtuales, a veces las configuraciones de red se pierden. Para solucionarlo, creé dos scripts de auto-reparación:

**Script 1: `auto_reparar_router.sh`** — Se ejecuta en el **router** y reconstruye todas las reglas de iptables con la DMZ incluida (ya mostrado en la sección 4.3).

**Script 2: `auto_reparar.sh`** — Se ejecuta en el **servidor Docker** y realiza 4 tareas:

```bash
#!/bin/bash
# 1. Espera a que el router (10.0.10.1) esté online
while ! ping -c 1 -W 1 10.0.10.1 > /dev/null; do
    sleep 2
done

# 2. Desactiva rp_filter (necesario para IPs virtuales múltiples)
sudo sysctl -w net.ipv4.conf.all.rp_filter=0

# 3. Añade la ruta hacia la red de oficina
sudo ip route add 10.0.20.0/24 via 10.0.10.1 dev ens33

# 4. Configura DNAT bypass para redirigir tráfico a contenedores Docker
sudo iptables -t nat -A PREROUTING -d 10.0.10.10 -p tcp --dport 80 \
  -j DNAT --to-destination 172.18.0.6:80
sudo iptables -t nat -A PREROUTING -d 10.0.10.20 -p tcp --dport 443 \
  -j DNAT --to-destination 172.18.0.10:443
```

**[📸 Ejecuta `sudo bash auto_reparar.sh` en el servidor y haz una captura del resultado]**

---

### **4.10. Copias de Seguridad**

Para proteger los datos críticos, implementé un script de backup automatizado que realiza copias de la base de datos y los archivos de WordPress:

```bash
#!/bin/bash
# hacer_backup.sh — Backup de MariaDB y WordPress
BACKUP_DIR="/home/admin1234/backups"
DATE=$(date +%Y-%m-%d_%H%M%S)

# 1. Backup de la BD (dump en caliente, sin parar el servicio)
docker exec base_datos mysqldump -u admin1234 -padmin1234 admin1234 \
  > $BACKUP_DIR/db_backup_$DATE.sql

# 2. Backup de archivos WordPress (temas, plugins, uploads)
tar -czf $BACKUP_DIR/wp_files_$DATE.tar.gz \
  /home/admin1234/infraestructura/wordpress_data

# 3. Limpieza: borrar backups de más de 7 días
find $BACKUP_DIR -type f -mtime +7 -delete
```

**[📸 Ejecuta `sudo bash hacer_backup.sh` y luego `ls -lh ~/backups/` mostrando los archivos generados]**

---

## **5. CONCLUSIONES**

### Dificultades encontradas

1. **Enrutamiento asimétrico en VMware:** Al tener dos interfaces de red en la misma subred, el kernel Linux descartaba los paquetes de retorno. Tuve que consolidar ambas IPs en una sola interfaz con IP Aliasing y desactivar `rp_filter`.

2. **Conflicto del puerto 53 (DNS):** El servicio `systemd-resolved` de Ubuntu secuestraba el puerto 53, impidiendo que Dnsmasq arrancara. La solución fue desactivarlo y purgar el servicio:
   ```bash
   sudo systemctl stop systemd-resolved && sudo systemctl disable systemd-resolved
   sudo fuser -k 53/udp && sudo fuser -k 53/tcp
   ```

3. **Certificados SSL rechazados:** Firefox bloqueaba todos los accesos HTTPS con `SSL_ERROR_BAD_CERT_DOMAIN`. El certificado original solo era válido para un dominio. Tuve que rehacer toda la PKI con extensiones SAN para incluir todos los subdominios e IPs.

4. **Uptime Kuma y subpaths:** Kuma es una SPA (Vue.js) que no soporta correr bajo un subpath como `/status/`. Intenté soluciones con `sub_filter` y con iframes, pero la primera no reescribe el JavaScript y la segunda es bloqueada por `X-Frame-Options`. La solución final fue una simple redirección 302 al dominio.

5. **Pérdida de reglas de firewall:** Cada vez que ejecutaba el script de reparación del router, las reglas DROP de la DMZ se perdían porque el script original no las incluía. Tuve que reescribir `auto_reparar_router.sh` incluyendo todas las reglas de seguridad para que la DMZ se reconstruya correctamente.

6. **Persistencia tras reinicios:** Las rutas estáticas y las reglas de iptables se perdían tras cada reinicio. Creé scripts de auto-reparación y configuré `iptables-persistent` para que las reglas se carguen automáticamente.

### Aportaciones nuevas respecto a lo aprendido en los módulos

- **Docker y Docker Compose** no se vieron en profundidad en el módulo. He aprendido a crear clústeres con réplicas, balanceo de carga, Docker Secrets para gestión segura de contraseñas y redes Docker compartidas entre múltiples `docker-compose.yml`.

- **PKI y certificados X.509v3** con SANs se vieron de forma muy teórica. En este proyecto he implementado una CA real completa con OpenSSL, generando la cadena de confianza desde la raíz y distribuyéndola con un portal web propio.

- **Iptables con DNAT/MASQUERADE** en combinación con la segmentación en 3 subredes y una VPN mesh es algo que va más allá del módulo de redes. He aprendido a diseñar una DMZ funcional con reglas de bloqueo explícitas que protegen los servicios sensibles.

- **Tailscale como Subnet Router** no se mencionó en ningún módulo. Lo implementé para poder trabajar desde casa y ha resultado ser una herramienta imprescindible para la administración remota sin comprometer la seguridad.

- **Scripts de resiliencia** con espera activa al router, desactivación de `rp_filter` y bypass DNAT son soluciones que tuve que investigar por mi cuenta para resolver problemas específicos de VMware.