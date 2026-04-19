# **Guía Maestra de Organización y Control del Proyecto ASIR**

Este documento es la "biblia" de la infraestructura CanarIAs. Detalla exactamente dónde está cada configuración, qué IPs se usan, cómo entrar a los servicios y qué credenciales utilizar. Está diseñado para que cualquier administrador pueda entender y operar la red sin perderse.

## **🖥️ 1. Dispositivos: El Router Perimetral**

El Router es el cerebro de la red. Gestiona el tráfico, la seguridad, los nombres y las direcciones IP.

### 🌐 Interfaces y Redes

* **`ens33` (WAN / Internet):** IP Dinámica (Asignada por el router físico/VMware, ej. `192.168.75.x` o `192.168.139.x`). Es la salida al exterior.
* **`ens37` (Red Servidores):** IP `10.0.10.1`. Abarca la red `10.0.10.0/24`. Es la zona de máxima seguridad (DMZ interna) donde residen los Docker.
* **`ens38` (Red Oficina):** IP `10.0.20.1`. Abarca la red `10.0.20.0/24`. Es la red de confianza para empleados y administradores.
* **`ens39` (Red Invitados):** IP `10.0.30.1`. Abarca la red `10.0.30.0/24`. Red aislada solo con salida a Internet.

### 📂 Rutas de Configuración del Router

Si necesitas modificar el comportamiento del router, debes editar estos archivos (conectándote por SSH a `10.0.10.1` o a su IP WAN):

#### DHCP (Asignación de IPs)

* **Ruta:** `/etc/dhcp/dhcpd.conf`
* **Para qué sirve:** Este es el archivo maestro del servidor DHCP (ISC DHCP Server). Define los **rangos de IPs** que se asignan automáticamente a cada red (Pools), hace **reservas fijas** por dirección MAC (para que el servidor siempre reciba `10.0.10.10`) y configura la **Opción 121** que inyecta rutas estáticas directamente en las tablas de enrutamiento de los PCs de la oficina sin intervención manual.

```conf
# @File: /etc/dhcp/dhcpd.conf
# @Description: Configuración del Servidor DHCP del Router Perimetral.
# @Logic: Asigna IPs dinámicas a Oficinas/Invitados, reserva IP estática
#         para el servidor e inyecta rutas (Opción 121).

# --- DECLARACIÓN DE OPCIONES PERSONALIZADAS ---
# @Logic: La Opción 121 (RFC 3442) y la 249 (Microsoft) permiten al DHCP
# "empujar" rutas estáticas directamente a la tabla de enrutamiento de los
# clientes, evitando que el administrador tenga que ir PC por PC.
option classless-static-routes code 121 = array of unsigned integer 8;
option ms-classless-static-routes code 249 = array of unsigned integer 8;

# --- RED SERVIDORES (ens37 - 10.0.10.0/24) ---
# @Detalle: Esta subred contiene la infraestructura crítica (Docker, DMZ).
# No tiene 'range' porque no queremos que se asignen IPs aleatorias aquí;
# solo el servidor tiene IP reservada por MAC.
subnet 10.0.10.0 netmask 255.255.255.0 {
    option routers 10.0.10.1;
    option domain-name-servers 10.0.20.1;
    option domain-name "canarias.local";
}

# @Detalle: Reserva de IP Estática basada en la dirección MAC.
# Garantiza que el servidor Docker SIEMPRE reciba la IP 10.0.10.10.
host servidor-canarias {
    hardware ethernet 00:0c:29:de:1b:a1;
    fixed-address 10.0.10.10;
}

# --- RED OFICINA (ens38 - 10.0.20.0/24) ---
# @Detalle: Red segura para empleados. Tienen acceso tanto a Internet
# como a los servicios de gestión (10.0.10.20).
subnet 10.0.20.0 netmask 255.255.255.0 {
    option routers 10.0.20.1;
    option domain-name-servers 10.0.20.1;
    option domain-name "canarias.local";
    range 10.0.20.100 10.0.20.200;

    # OPCIÓN 121: Enviar rutas estáticas a los clientes automáticamente
    # @Explicación del formato: 24 = máscara /24, seguido de la red destino
    # (10,0,10 = 10.0.10.0) y el gateway (10,0,20,1). El 0 final define
    # la ruta por defecto (0.0.0.0/0) también vía 10.0.20.1.
    option classless-static-routes 24, 10,0,10, 10,0,20,1, 0, 10,0,20,1;
    option ms-classless-static-routes 24, 10,0,10, 10,0,20,1, 0, 10,0,20,1;

    # @Detalle: Reservas de IPs fijas para los equipos de los administradores.
    host pc-principal { hardware ethernet 00:0c:29:85:df:4f; fixed-address 10.0.20.20; }
    host pc-aitor     { hardware ethernet 00:0c:29:33:2d:db; fixed-address 10.0.20.25; }
    host pc-jeremy    { hardware ethernet 00:0c:29:16:6e:b2; fixed-address 10.0.20.30; }
    host pc-patricia  { hardware ethernet 00:0c:29:95:34:0d; fixed-address 10.0.20.40; }
    host pc-adonay    { hardware ethernet 00:0c:29:c8:d8:39; fixed-address 10.0.20.50; }
    host pc-ikram     { hardware ethernet 00:0c:29:4c:87:db; fixed-address 10.0.20.60; }
}

# --- RED EXTERNA / INVITADOS (ens39 - 10.0.30.0/24) ---
# @Detalle: Red aislada por Iptables. Los invitados solo tienen acceso a
# Internet y a la web pública (10.0.10.10). El acceso a gestión está BLOQUEADO.
subnet 10.0.30.0 netmask 255.255.255.0 {
    option routers 10.0.30.1;
    option domain-name-servers 10.0.30.1;
    option domain-name "canarias.local";
    option classless-static-routes 24, 10,0,10, 10,0,30,1, 0, 10,0,30,1;
    option ms-classless-static-routes 24, 10,0,10, 10,0,30,1, 0, 10,0,30,1;
    range 10.0.30.100 10.0.30.200;
    default-lease-time 1800;  # 30 min para liberar IPs de invitados rápido
}
```

#### DNS (Resolución de Nombres locales)

* **Ruta principal:** `/etc/hosts` (en el router)
* **Para qué sirve:** Contiene el listado maestro de **Nombres ↔ IPs** del dominio `canarias.local`. El servicio **Dnsmasq** lee este archivo automáticamente y responde a las consultas DNS de todos los clientes de la red. Así, cuando un empleado escribe `vault.canarias.local` en su navegador, Dnsmasq resuelve la IP `10.0.10.20` sin necesidad de un servidor DNS externo.

```text
# /etc/hosts (en el router 10.0.10.1)
127.0.0.1 localhost
127.0.1.1 canarias

# --- INFRAESTRUCTURA CANARIAS ---
# IPs Directas (Zona de Servidores)
10.0.10.1  router.canarias.local
10.0.10.10 wp.canarias.local publico.canarias.local www.canarias.local
10.0.10.20 gestion.canarias.local vault.canarias.local docker.canarias.local mail.canarias.local pki.canarias.local status.canarias.local
```

* **Ruta del servicio Dnsmasq:** `/etc/dnsmasq.d/` (3 archivos de configuración)
* **Para qué sirve:** Dnsmasq actúa como servidor DNS ligero. Lee `/etc/hosts` para resolver nombres básicos, pero además tiene **archivos de configuración propios** que definen resoluciones forzadas (`address=`) y en qué interfaces escuchar.

**Archivo 1:** `/etc/dnsmasq.d/asir-config` — Opciones generales de seguridad DNS:

```conf
# /etc/dnsmasq.d/asir-config — Opciones base
interface=*        # Escuchar en todas las interfaces
bind-interfaces    # Asociarse explícitamente a cada interfaz
domain-needed      # No reenviar consultas sin dominio (ej. "localhost")
bogus-priv         # No reenviar consultas inversas de IPs privadas a Internet
```

**Archivo 2:** `/etc/dnsmasq.d/canarias.conf` — Resolución forzada de dominios internos:

```conf
# /etc/dnsmasq.d/canarias.conf — Mapeo de dominios a IPs
# Estas líneas tienen PRIORIDAD sobre /etc/hosts para Dnsmasq.
# Garantizan que los subdominios siempre apunten a la IP correcta.

# --- ZONA PÚBLICA (DMZ) ---
address=/canarias.local/10.0.10.10
address=/www.canarias.local/10.0.10.10
address=/wp.canarias.local/10.0.10.10

# --- ZONA PRIVADA (GESTIÓN) ---
address=/vault.canarias.local/10.0.10.20
address=/mail.canarias.local/10.0.10.20
address=/docker.canarias.local/10.0.10.20
address=/pki.canarias.local/10.0.10.20
address=/status.canarias.local/10.0.10.20
```

**Archivo 3:** `/etc/dnsmasq.d/interfaces.conf` — Interfaces de escucha explícitas:

```conf
# /etc/dnsmasq.d/interfaces.conf — En qué "cables" escucha el DNS
interface=ens37       # Red Servidores (10.0.10.0/24)
interface=ens38       # Red Oficina (10.0.20.0/24)
interface=ens39       # Red Invitados (10.0.30.0/24)
interface=tailscale0  # VPN Tailscale (acceso remoto)
interface=lo          # Loopback local
bind-interfaces
```

#### DMZ y Firewall (Iptables)

* **Para qué sirve:** Iptables es el cortafuegos del kernel Linux. Define exactamente qué tráfico se permite y qué se bloquea entre las tres redes. Las reglas se cargan al arrancar y Tailscale añade sus propias cadenas automáticamente.

**Cómo leer las reglas** — El firewall se divide en tres tablas:

1. **`*mangle`** — Optimización de paquetes TCP:

```bash
# Tabla MANGLE — Ajuste del tamaño de segmentos TCP
*mangle
# Corrige problemas de MTU en VPN/túneles ajustando el MSS automáticamente
-A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT
```

2. **`*filter`** — Reglas de filtrado (permitir/bloquear tráfico):

```bash
# Tabla FILTER (volcado real del router — 18 Abril 2026)
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:ts-forward - [0:0]    # Cadena creada automáticamente por Tailscale
:ts-input - [0:0]      # Cadena creada automáticamente por Tailscale

# --- INPUT: Tráfico dirigido al propio router ---
-A INPUT -p tcp --dport 22 -j ACCEPT                         # SSH siempre accesible
-A INPUT -i lo -j ACCEPT                                      # Loopback local
-A INPUT -i tailscale0 -j ACCEPT                              # VPN Tailscale
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT  # Conexiones activas

# --- FORWARD: Tráfico que pasa A TRAVÉS del router ---

# Tailscale: la VPN pasa todo
-A FORWARD -i tailscale0 -j ACCEPT
# Oficina (10.0.20.x) → Servidores (10.0.10.x) = TODO permitido
-A FORWARD -s 10.0.20.0/24 -d 10.0.10.0/24 -j ACCEPT
# Conexiones ya establecidas (respuestas) pueden continuar
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# ===== DMZ: PROTECCIÓN DE LA ZONA DE GESTIÓN =====
# Invitados → WordPress público = SOLO puertos 80 y 443
-A FORWARD -s 10.0.30.0/24 -d 10.0.10.10 -p tcp --dport 80 -j ACCEPT
-A FORWARD -s 10.0.30.0/24 -d 10.0.10.10 -p tcp --dport 443 -j ACCEPT
# Invitados → Gestión = BLOQUEADO 🔒
-A FORWARD -s 10.0.30.0/24 -d 10.0.10.20 -j DROP
# Internet (WAN) → Gestión = BLOQUEADO 🔒
-A FORWARD -i ens33 -d 10.0.10.20 -j DROP
# SSH entre redes = PERMITIDO (administración)
-A FORWARD -p tcp --dport 22 -j ACCEPT
# CANDADO FINAL: Todo lo demás hacia gestión = BLOQUEADO 🔒
-A FORWARD -d 10.0.10.20 -j DROP
COMMIT
```

3. **`*nat`** — Traducción de direcciones (DNAT/MASQUERADE):

```bash
# Tabla NAT (volcado real del router — 18 Abril 2026)
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
:ts-postrouting - [0:0]   # Cadena creada por Tailscale

# DNAT: Tráfico que entra por Internet (ens33) puertos 80/443
# se redirige automáticamente al WordPress (10.0.10.10)
-A PREROUTING -i ens33 -p tcp -m tcp --dport 80 -j DNAT --to-destination 10.0.10.10:80
-A PREROUTING -i ens33 -p tcp -m tcp --dport 443 -j DNAT --to-destination 10.0.10.10:443

# MASQUERADE: Las redes internas salen a Internet con la IP pública del router
-A POSTROUTING -o ens33 -j MASQUERADE     # Salida a Internet (todas las redes)
-A POSTROUTING -o ens37 -j MASQUERADE     # Salida hacia la red de servidores
COMMIT
```

#### Servicios activos en el router

Los tres servicios críticos del router están **activos** y arrancan automáticamente:

| Servicio | Estado | Para qué sirve |
|:---|:---|:---|
| `isc-dhcp-server` | ✅ Activo | Asigna IPs automáticas a todas las redes |
| `dnsmasq` | ✅ Activo | Resuelve nombres de dominio `*.canarias.local` |
| `tailscaled` | ✅ Activo | VPN mesh para acceso remoto |

El reenvío de paquetes IP está habilitado: `net.ipv4.ip_forward = 1`

### 🦎 Conectividad Remota: Tailscale

* **Para qué sirve:** Tailscale permite acceder a la red de la empresa **desde casa** sin abrir puertos físicos en el router real, creando una VPN Mesh cifrada con WireGuard. El router actúa como "Subnet Router" permitiendo el paso a las redes `10.0.10.0/24` y `10.0.20.0/24`.
* **Dónde se configuró:** Se instaló a nivel de Sistema Operativo en el Router. Se autorizó la ruta en la consola web de administración de Tailscale ([Admin Console](https://login.tailscale.com/admin)).
* **IP del router en la VPN:** `100.101.99.58`

**Dispositivos conectados** (verificado el 18 de Abril de 2026):

| IP Tailscale | Nombre | Cuenta | SO | Estado |
|:---|:---|:---|:---|:---|
| `100.101.99.58` | `canarias` (Router) | jeremira11092005@ | Linux | Nodo actual |
| `100.112.104.42` | `desktop-1l6ounq` | jeremira11092005@ | Windows | Activo (conexión directa) |
| `100.76.0.75` | `desktop-pasmvha` | patix93@ | Windows | Idle |
| `100.64.199.121` | `krm` | uuoo27713@ | Windows | Activo (conexión directa) |
| `100.116.69.27` | `xiaomi-13t-pro` | jeremira11092005@ | Android | Idle |

* **Comandos útiles:**
  * Ver estado: `tailscale status`
  * Ver IP propia: `tailscale ip -4`
  * El estado se guarda cifrado en `/var/lib/tailscale/`

---

## **⚙️ 2. Máquinas con los Servidores (Infraestructura Docker)**

Todos los servicios corren en contenedores Docker y están divididos lógicamente en dos IPs principales del host servidor. Se comunican entre sí a través de la red Docker compartida `infraestructura_app_net`.

### 2.1. WordPress + MariaDB (Sitio Web Público)

* **Qué es:** El CMS principal de la empresa, desplegado en **Alta Disponibilidad** (3 réplicas) conectadas a una base de datos MariaDB centralizada.
* **Conexión:** `https://wp.canarias.local` o `https://canarias.local` → IP **`10.0.10.10`**
* **Ruta de Despliegue:** [`infraestructura/publico/docker-compose.yml`](file:///home/admin1234/infraestructura/publico/docker-compose.yml) — Aquí se levantan **tanto los nodos WordPress como la base de datos MariaDB**, todo en el mismo archivo compose.
* **Datos persistentes:**
  * **WordPress:** `/home/admin1234/infraestructura/wordpress_data/` (temas, plugins, uploads)
  * **MariaDB:** `/home/admin1234/infraestructura/db_data/` (datos binarios de la base de datos)
* **Credenciales:** Usuario WP: `admin1234` / Contraseña: `admin1234`. MariaDB root: ver `secrets/db_root_password.txt`.

**Fragmento clave del código** — [docker-compose.yml (publico)](file:///home/admin1234/infraestructura/publico/docker-compose.yml):

```yaml
  # CLÚSTER DE WORDPRESS (3 Réplicas) — Líneas 25-52
  wordpress:
    image: bitnami/wordpress:latest
    restart: always
    healthcheck:  # Verifica que el contenedor responda antes de darle tráfico
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      replicas: 3  # Alta Disponibilidad: 3 instancias idénticas
    environment:
      - WORDPRESS_DATABASE_HOST=mariadb
      - WORDPRESS_DATABASE_PASSWORD_FILE=/run/secrets/db_pass  # Usa Docker Secrets
    volumes:
      - ../wordpress_data:/bitnami/wordpress  # Datos persistentes fuera del contenedor

  # BASE DE DATOS MARIADB — Líneas 54-75
  mariadb:
    image: bitnami/mariadb:latest
    container_name: base_datos
    restart: always
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
    environment:
      - MARIADB_ROOT_PASSWORD_FILE=/run/secrets/db_root_pass  # Usa Docker Secrets
    volumes:
      - ../db_data:/bitnami/mariadb

# Los secretos se leen de archivos físicos — Líneas 77-82
secrets:
  db_pass:
    file: ../secrets/db_password.txt
  db_root_pass:
    file: ../secrets/db_root_password.txt
```

### 2.2. Portainer (Orquestación de Docker)

* **Qué es:** Interfaz gráfica web para gestionar, reiniciar y ver los logs de todos los contenedores Docker del proyecto.
* **Conexión:**
  * Por dominio: `https://docker.canarias.local` → Nginx redirige a Portainer
  * Por IP directa: `https://10.0.10.20/portainer/`
* **Ruta de Despliegue:** [`infraestructura/gestion/docker-compose.yml`](file:///home/admin1234/infraestructura/gestion/docker-compose.yml) — Servicio `portainer` (líneas 15-23).
* **Datos persistentes:** Portainer accede al socket de Docker (`/var/run/docker.sock`) para leer el estado de los contenedores.
* **Credenciales:** Usuario: `admin1234` / Contraseña: `admin1234admin` (se crea en el primer acceso, dentro de los primeros 5 minutos de arranque).

**Fragmento clave del código** — [docker-compose.yml (gestion)](file:///home/admin1234/infraestructura/gestion/docker-compose.yml):

```yaml
  # PORTAINER — Líneas 15-23
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer_web
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # Acceso al motor Docker del host
      - ../kuma_data:/data
    networks:
      - app_net
```

### 2.3. Uptime Kuma (Monitorización de Servicios)

* **Qué es:** Panel de monitorización en tiempo real que hace "pings" y comprobaciones HTTP periódicas para asegurar que WordPress, el Correo y Vaultwarden están vivos. Envía alertas si algo cae.
* **Conexión:**
  * Por dominio: `https://status.canarias.local` → Nginx proxea directamente a Kuma (**acceso recomendado**)
  * Por IP: `https://10.0.10.20/status/` → Redirige automáticamente a `status.canarias.local`. Kuma es una SPA (Vue.js) y no soporta correr bajo un subpath (`/status/`), por lo que el Nginx de gestión redirige al dominio donde Kuma funciona en la raíz `/`.
* **Ruta de Despliegue:** [`infraestructura/gestion/docker-compose.yml`](file:///home/admin1234/infraestructura/gestion/docker-compose.yml) — Servicio `monitor_kuma` (líneas 34-44).
* **Datos persistentes:** `/home/admin1234/infraestructura/kuma_data/` (historial de caídas, base de datos SQLite de los monitores).
* **Credenciales:** Usuario: `admin` / Contraseña: `admin1234`.

**Fragmento clave del código** — [docker-compose.yml (gestion)](file:///home/admin1234/infraestructura/gestion/docker-compose.yml):

```yaml
  # UPTIME KUMA — Líneas 34-44
  monitor_kuma:
    image: louislam/uptime-kuma:1
    container_name: monitor_kuma
    restart: unless-stopped
    dns:
      - 10.0.10.1    # Usa el DNS del router para resolver canarias.local
      - 8.8.8.8
    volumes:
      - ../kuma_data:/app/data
    networks:
      - app_net
```

### 2.4. Servidor de Correo Electrónico

* **Qué es:** Un servidor completo (Docker-Mailserver con Postfix/Dovecot/SpamAssassin/Fail2Ban) y un cliente web (Rainloop) para enviar y recibir correos corporativos `@canarias.local`.
* **Conexión:**
  * Webmail: `https://mail.canarias.local/mail/` o `https://10.0.10.20/mail/`
  * SMTP/IMAP: Puertos estándar (25, 143, 465, 587, 993)
* **Rutas de Despliegue:**
  * Motor de correo: [`infraestructura/correo/docker-compose-mail.yml`](file:///home/admin1234/infraestructura/correo/docker-compose-mail.yml)
  * Cliente webmail (Rainloop): [`infraestructura/gestion/docker-compose.yml`](file:///home/admin1234/infraestructura/gestion/docker-compose.yml) — Servicio `webmail` (líneas 25-32)

**Archivos de Configuración Críticos:**

* **Cuentas de correo** → [`postfix-accounts.cf`](file:///home/admin1234/infraestructura/correo/mail-config/postfix-accounts.cf): Aquí están los **usuarios reales** del correo. Cada línea es un buzón con su contraseña en hash SHA512.

```text
# infraestructura/correo/mail-config/postfix-accounts.cf
# Formato: usuario@dominio|{HASH}contraseña_cifrada
# Todas estas cuentas usan la contraseña "admin1234" cifrada (entorno de laboratorio)

jeremy@canarias.local|{SHA512-CRYPT}$6$lOq2Ku6ssU12QvI3$sIijWfF4gVb64HxL8L...
adonay@canarias.local|{SHA512-CRYPT}$6$DlkHbjh979MZdnvZ$5Egpna0z45QQkp9at5...
ikram@canarias.local|{SHA512-CRYPT}$6$QRpeol058PgJBMqP$cHluibj/IPCaaUsa83u...
patricia@canarias.local|{SHA512-CRYPT}$6$Vxb1eKYC2.acf78c$XlIJJvBu4UldpImirJ...
aitor@canarias.local|{SHA512-CRYPT}$6$Cnq8hgmSbH9OI/fJ$0UwA22SYtHWnNZBYHGN...
admin@canarias.local|{SHA512-CRYPT}$6$j/FDaBOZuxdqteK3$Qg2NbHrT2wqtn07nhOI...
facturacion@canarias.local|{SHA512-CRYPT}$6$Wel/xdTi1uuBNuyt$UoIaYYjXMZTWhd...
```

* **Aliases y listas de distribución** → [`postfix-virtual.cf`](file:///home/admin1234/infraestructura/correo/mail-config/postfix-virtual.cf): Redirige correos de direcciones genéricas (como `ventas@`) a los buzones reales de los empleados.

```text
# infraestructura/correo/mail-config/postfix-virtual.cf
# Formato: correo_genérico  correos_reales_separados_por_comas

# Lista global — un correo a equipo@ le llega a todos
equipo@canarias.local jeremy@canarias.local,adonay@canarias.local,ikram@canarias.local,patricia@canarias.local,aitor@canarias.local

# Departamentos
info@canarias.local   ikram@canarias.local,patricia@canarias.local
ventas@canarias.local ikram@canarias.local,patricia@canarias.local

# Soporte técnico
soporte@canarias.local aitor@canarias.local,adonay@canarias.local
```

**Fragmento clave del motor de correo** — [docker-compose-mail.yml](file:///home/admin1234/infraestructura/correo/docker-compose-mail.yml):

```yaml
  # DOCKER-MAILSERVER — Líneas 8-35
  mailserver:
    image: docker.io/mailserver/docker-mailserver:latest
    container_name: servidor_correo
    hostname: mail.canarias.local
    domainname: canarias.local
    ports:
      - "25:25"    # SMTP (Envío de correo entre servidores)
      - "143:143"  # IMAP (Lectura de correo)
      - "465:465"  # ESMTP (SMTP seguro con TLS implícito)
      - "587:587"  # Submission (Envío desde clientes autenticados)
      - "993:993"  # IMAPS (IMAP seguro)
    environment:
      - ENABLE_SPAMASSASSIN=1   # Filtro antispam
      - ENABLE_FAIL2BAN=1       # Banea IPs tras intentos fallidos de login
      - SSL_TYPE=manual         # Usa nuestros propios certificados CA
      - SSL_CERT_PATH=/tmp/certs/server.crt
      - SSL_KEY_PATH=/tmp/certs/server.key
```

* **Credenciales:**
  * Cuentas de correo (ej. `admin@canarias.local`): Contraseña `admin1234`
  * Administración de Rainloop (`?admin`): Usuario `admin`, Contraseña `admin1234`

### 2.5. Vaultwarden (Gestor de Contraseñas)

* **Qué es:** Un cofre de contraseñas seguro, compatible con Bitwarden. Los empleados guardan sus credenciales aquí de forma cifrada.
* **Conexión:**
  * Por dominio: `https://vault.canarias.local`
  * Por IP directa: `https://10.0.10.20/vault/`
* **Ruta de Despliegue:** [`infraestructura/gestion/docker-compose.yml`](file:///home/admin1234/infraestructura/gestion/docker-compose.yml) — Servicio `vaultwarden` (líneas 4-13).
* **Datos persistentes:** `/home/admin1234/infraestructura/vault_data/` (base de datos SQLite `db.sqlite3` + archivos adjuntos).

**Fragmento clave del código** — [docker-compose.yml (gestion)](file:///home/admin1234/infraestructura/gestion/docker-compose.yml):

```yaml
  # VAULTWARDEN — Líneas 4-13
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: cofre_seguro
    restart: unless-stopped
    environment:
      - SIGNUPS_ALLOWED=true   # Cualquiera puede registrarse (entorno de lab)
    volumes:
      - ../vault_data:/data    # Base de datos SQLite + adjuntos
    networks:
      - app_net
```

* **Credenciales:** El registro es libre (`SIGNUPS_ALLOWED=true`). No hay `ADMIN_TOKEN` configurado, por lo que el panel de administración `/admin` no está habilitado. Para gestionar usuarios, se hace directamente desde la interfaz web de Vaultwarden registrándose como cualquier usuario.

### 2.6. PKI (Portal de Seguridad y Certificados)

* **Qué es:** Una página web estática que permite a los empleados **descargar el certificado Root CA** de la empresa e instalarlo en su navegador para evitar alertas de seguridad al acceder a los servicios HTTPS internos.
* **Conexión:** `https://pki.canarias.local` → IP **`10.0.10.20`** (Nginx redirige automáticamente HTTP a HTTPS)
* **Ruta del código fuente:** [`infraestructura/gestion/pki.html`](file:///home/admin1234/infraestructura/gestion/pki.html) — Servido por el Nginx de gestión.

**Fragmento clave** — [pki.html](file:///home/admin1234/infraestructura/gestion/pki.html):

```html
<!-- infraestructura/gestion/pki.html — Líneas 16-21 -->
<div class="container">
    <h1>🔐 Portal de Seguridad CanarIAs</h1>
    <p>Para acceder a los servicios de Gestión de forma segura,<br>
       debe instalar nuestro Certificado Raíz en su navegador.</p>
    <a href="/certs/canarias_root.pem" class="btn">📥 Descargar Certificado Raíz (CA)</a>
</div>
```

---

## **🔀 3. Nginx: Los Proxies Inversos (Los "Porteros")**

Para que todo funcione por el puerto 443 sin conflictos, usamos **dos servidores Nginx distintos**, uno por cada zona de red. Son la pieza clave que permite acceder a 6 servicios distintos usando solo 2 IPs.

### 3.1. Nginx Público (`nginx_publico`)

* **Ruta de configuración:** [`infraestructura/publico/nginx.conf`](file:///home/admin1234/infraestructura/publico/nginx.conf) (63 líneas)
* **Contenedor:** `nginx_publico`
* **IP:** `10.0.10.10`
* **Para qué sirve:** Es un **balanceador de carga** puro. Recibe el tráfico masivo de Internet (redirigido por el router vía DNAT 80/443) y lo reparte entre los 3 contenedores de WordPress usando `ip_hash` (persistencia de sesión). Solo maneja tráfico público.

**Fragmento clave** — [nginx.conf (publico)](file:///home/admin1234/infraestructura/publico/nginx.conf):

```nginx
    # BALANCEADOR WORDPRESS CON IP_HASH — Líneas 30-33
    upstream wordpress_cluster {
        ip_hash;  # Garantiza que cada usuario vaya siempre al mismo contenedor
        server wordpress:8080;  # Docker Compose redirige a las 3 réplicas
    }

    # REDIRECCIÓN HTTP → HTTPS — Líneas 36-40
    server {
        listen 80;
        server_name canarias.local 10.0.10.10;
        return 301 https://$host$request_uri;
    }

    # SERVIDOR HTTPS — Líneas 43-61
    server {
        listen 443 ssl;
        ssl_certificate     /etc/nginx/certs/server.crt;
        ssl_certificate_key /etc/nginx/certs/server.key;

        location / {
            proxy_pass http://wordpress_cluster;  # Envía al clúster balanceado
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
```

### 3.2. Nginx de Empresa (`nginx_empresa`)

* **Ruta de configuración:** [`infraestructura/gestion/nginx.conf`](file:///home/admin1234/infraestructura/gestion/nginx.conf) (123 líneas)
* **Contenedor:** `nginx_empresa`
* **IP:** `10.0.10.20`
* **Para qué sirve:** Es el **guardián** de la gestión privada. Funciona con dos estrategias simultáneas:
  * **Por dominio** (Virtual Hosts): `docker.canarias.local` → Portainer, `vault.canarias.local` → Vaultwarden, etc.
  * **Por ruta** (cuando se accede por IP directa): `10.0.10.20/portainer/` → Portainer, `10.0.10.20/vault/` → Vaultwarden, etc.

**Fragmento clave** — [nginx.conf (gestion)](file:///home/admin1234/infraestructura/gestion/nginx.conf):

```nginx
    # SERVIDOR DEFAULT (PKI) con rutas de emergencia por IP — Líneas 17-69
    server {
        listen 443 ssl default_server;
        server_name 10.0.10.20 pki.canarias.local;

        # Página principal: Portal de descarga de certificados
        location / {
            root /usr/share/nginx/html;
            index pki.html;
        }
        # Acceso directo a los certificados
        location /certs/ {
            alias /etc/nginx/certs/;
            autoindex on;
        }

        # Rutas de emergencia (acceso por IP sin DNS)
        location /mail/      { proxy_pass http://webmail_canarias:8888/; }
        location /vault/     { proxy_pass http://cofre_seguro:80/; }
        location /portainer/ { proxy_pass https://portainer_web:9443/; }
        # Kuma no soporta subpath (SPA Vue.js) → redirige al dominio
        location /status     { return 302 https://status.canarias.local/; }
    }

    # SERVIDORES POR NOMBRE (Virtual Hosts) — Líneas 71-121
    server {
        listen 443 ssl;
        server_name docker.canarias.local;
        location / { proxy_pass https://portainer_web:9443; }
    }
    server {
        listen 443 ssl;
        server_name vault.canarias.local;
        location / { proxy_pass http://cofre_seguro:80; }
    }
    server {
        listen 443 ssl;
        server_name status.canarias.local;
        location / { proxy_pass http://monitor_kuma:3001; }
    }
    server {
        listen 443 ssl;
        server_name mail.canarias.local;
        location / { return 301 https://$host/mail/; }
        location /mail/ { proxy_pass http://webmail_canarias:8888/; }
    }
```

---

## **🔐 4. Cosas Faltantes Vitales (Control del Proyecto)**

Hay carpetas críticas que no son un "servicio" web, pero si se borran, la infraestructura colapsa:

### Carpeta de Certificados SSL (PKI)

* **Ruta:** `/home/admin1234/infraestructura/certs/`
* **Para qué sirve:** Contiene la **CA raíz propia** de la empresa y los certificados del servidor. Todos los servicios HTTPS de la infraestructura dependen de estos archivos.

**Contenido real de la carpeta:**

| Archivo | Para qué sirve |
|:---|:---|
| `canarias_root.key` | Clave privada de la CA raíz (¡NUNCA compartir!) |
| `canarias_root.pem` | Certificado público de la CA raíz. Es el que descargan los empleados desde el portal PKI |
| `server.key` | Clave privada del servidor web |
| `server.csr` | Solicitud de firma del certificado (se usó para generar `server.crt`) |
| `server.crt` | Certificado público del servidor, firmado por la CA raíz |
| `v3.ext` | Extensiones X.509v3 — Define los **dominios alternativos** (SAN) que el certificado considera válidos |

**Fragmento clave** — [`v3.ext`](file:///home/admin1234/infraestructura/certs/v3.ext) (los dominios que el certificado reconoce como seguros):

```ini
# infraestructura/certs/v3.ext — 19 líneas
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

> **⚠️ Importante:** Si en el futuro añades un nuevo subdominio (ej. `grafana.canarias.local`), debes:
> 1. Añadir una nueva línea `DNS.10 = grafana.canarias.local` en este archivo
> 2. Regenerar el `server.crt` usando `openssl x509` con este `v3.ext`
> 3. Reiniciar los Nginx para que carguen el nuevo certificado

### Carpeta de Secretos (Docker Secrets)

* **Ruta:** `/home/admin1234/infraestructura/secrets/`
* **Para qué sirve:** Contiene archivos `.txt` planos con las contraseñas de las bases de datos. Docker Compose lee estos archivos al arrancar para inyectar las contraseñas dentro de los contenedores **sin escribirlas en texto claro** dentro de los `docker-compose.yml`. Es el mecanismo oficial de [Docker Secrets](https://docs.docker.com/compose/use-secrets/).

**Contenido real de la carpeta:**

| Archivo | Contenido | Usado por |
|:---|:---|:---|
| `db_password.txt` | `admin1234` | MariaDB + WordPress (secreto `db_pass`) |
| `db_root_password.txt` | `admin1234` | MariaDB root (secreto `db_root_pass`) |

### Red Docker compartida

* **Nombre:** `infraestructura_app_net`
* **Para qué sirve:** Es la red Docker tipo `bridge` que conecta **todos** los contenedores entre sí, aunque estén definidos en archivos `docker-compose.yml` diferentes. Sin esta red, el Nginx de gestión no podría acceder a Vaultwarden, ni Kuma podría monitorizar WordPress.
* **Cómo se crea:** Manualmente antes de levantar los servicios:

```bash
docker network create infraestructura_app_net
```

---

## **📋 5. Resumen de Accesos Rápidos**

| Servicio | URL de Acceso | IP Real | Usuario | Contraseña |
|:---|:---|:---|:---|:---|
| **WordPress** | `https://canarias.local` | `10.0.10.10` | `admin1234` | `admin1234` |
| **Portainer** | `https://docker.canarias.local` | `10.0.10.20` | `admin1234` | `admin1234admin` |
| **Vaultwarden** | `https://vault.canarias.local` | `10.0.10.20` | *(registro libre)* | *(usuario define)* |
| **Webmail** | `https://mail.canarias.local/mail/` | `10.0.10.20` | `admin@canarias.local` | `admin1234` |
| **Uptime Kuma** | `https://status.canarias.local` | `10.0.10.20` | `admin` | `admin1234` |
| **PKI** | `https://pki.canarias.local` | `10.0.10.20` | *(sin login)* | — |
| **Router (SSH)** | `ssh admin1234@10.0.10.1` | `10.0.10.1` | `admin1234` | `admin1234` |
