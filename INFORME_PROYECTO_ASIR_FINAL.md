# **Memoria Técnica y Proyecto Final de ASIR: Infraestructura Segura, Alta Disponibilidad y Servicios Corporativos**

**Empresa Ficticia:** CanarIAs S.L.L.  
**Ciclo Formativo:** Administración de Sistemas Informáticos en Red (ASIR)  
**Autor:** [Tu Nombre / admin1234]  
**Fecha:** Abril 2026

---

## **1. Introducción y Objetivos del Proyecto**
El objetivo fundamental de este proyecto ha sido diseñar, configurar y poner en producción la infraestructura tecnológica completa para la empresa CanarIAs S.L.L., cumpliendo con los estándares actuales de la industria (Enterprise-grade). 

El diseño se centra en tres pilares:
1.  **Alta Disponibilidad (HA) y Escalabilidad:** Garantizar que los servicios orientados al público soporten alta carga de tráfico mediante balanceo y replicación.
2.  **Seguridad Perimetral y Segmentación (Zero Trust):** Separar redes (Servidores, Oficina, Invitados) y blindar los accesos administrativos mediante DMZ (Zona Desmilitarizada) y Firewall.
3.  **Modernización e Infraestructura Inmutable:** Centralizar los servicios web, correo y gestión en contenedores Docker, desacoplando la capa de red (Router) de la capa de aplicación (Servidor).

---

## **2. Arquitectura de Red y Enrutamiento (Router Perimetral)**
El núcleo de la topología es un Router virtualizado (`192.168.139.131`) con Ubuntu Server. Utiliza un esquema Multi-NIC para separar el tráfico en distintas VLAN lógicas, ejerciendo labores de Gateway, Firewall, DNS y DHCP.

*   **`ens33` (WAN):** Salida a Internet y entrada de peticiones públicas.
*   **`ens37` (VLAN 10 - 10.0.10.0/24):** Red de Servidores y DMZ.
*   **`ens38` (VLAN 20 - 10.0.20.0/24):** Red de la Oficina (Empleados).
*   **`ens39` (VLAN 30 - 10.0.30.0/24):** Red de Invitados (Aislada).

### **2.1. Gestión Dinámica de IP y Enrutamiento (DHCP)**
Se utiliza `isc-dhcp-server` para repartir direcciones. Una configuración destacable es el uso de la **Opción 121 (RFC 3442)**, que permite "empujar" rutas estáticas directamente a los PCs de los empleados sin intervención manual, asegurando que sepan llegar a la red de servidores.

```text
# Fragmento de /etc/dhcp/dhcpd.conf
subnet 10.0.20.0 netmask 255.255.255.0 {
    option routers 10.0.20.1;
    option domain-name-servers 10.0.20.1;
    range 10.0.20.100 10.0.20.200;
    
    # OPCIÓN 121: Enviar ruta estática a los clientes (10.0.10.0/24 vía 10.0.20.1) y Puerta de enlace predeterminada
    option classless-static-routes 24, 10,0,10, 10,0,20,1, 0, 10,0,20,1;
}

host servidor-canarias {
    hardware ethernet 00:0c:29:de:1b:a1;
    fixed-address 10.0.10.10;
}
```
> 📸 **[Haz una captura en la terminal del cliente Windows/Linux con el comando `ip route` o `route print` para que se vea mejor cómo la ruta hacia 10.0.10.0/24 ha sido inyectada automáticamente]**

### **2.2. Resolución de Nombres (DNS)**
Se implementa `dnsmasq` como servidor DNS ligero. Centraliza los registros DNS de la empresa y resuelve los nombres a las dos IPs virtuales del servidor Docker:
*   Zonas Públicas (`canarias.local`, `wp`) resuelven a `10.0.10.10`.
*   Zonas Privadas (`vault`, `docker`, `mail`, `pki`) resuelven a `10.0.10.20`.

```text
# Fragmento de /etc/dnsmasq.d/canarias.conf
address=/canarias.local/10.0.10.10
address=/vault.canarias.local/10.0.10.20
address=/docker.canarias.local/10.0.10.20
```
> 📸 **[Haz una captura ejecutando un `ping vault.canarias.local` desde un PC de la oficina para demostrar que el DNS responde correctamente con 10.0.10.20 y así evidenciar su funcionamiento]**

### **2.3. Firewall Perimetral (Iptables)**
La seguridad de acceso se gestiona a nivel de kernel con Iptables.
*   **Redirección Externa (DNAT):** Solo se exponen los puertos web (80/443). El router los captura y reenvía a la IP pública del Docker.
*   **Aislamiento (Acl):** Se bloquea expresamente a la red de Invitados (`10.0.30.0/24`) para que no puedan escanear ni acceder a la IP de gestión (`10.0.10.20`), pero sí a la web pública.

```bash
# Reglas DNAT para publicación del puerto 80 y 443 hacia la DMZ
iptables -t nat -A PREROUTING -i ens33 -p tcp --dport 80 -j DNAT --to 10.0.10.10:80
iptables -t nat -A PREROUTING -i ens33 -p tcp --dport 443 -j DNAT --to 10.0.10.10:443

# Aislamiento: Invitados NO entran a la IP de Gestión
iptables -A FORWARD -s 10.0.30.0/24 -d 10.0.10.20/32 -j DROP
```

---

## **3. Capa de Aplicación y Alta Disponibilidad (Docker)**
Toda la carga de trabajo reside en un servidor interno dividido lógicamente en dos interfaces de red: `10.0.10.10` (DMZ Pública) y `10.0.10.20` (Gestión Privada). Todas las aplicaciones están orquestadas mediante Docker Compose y conectadas por una red `bridge` común (`infraestructura_app_net`).

### **3.1. Estructura de Directorios y Persistencia de Datos**
Para mantener un entorno profesional, inmutable y fácil de respaldar, la infraestructura se ha esquematizado separando estrictamente la **configuración** de los **datos persistentes**:

```text
infraestructura/
├── certs/           # ÚNICA carpeta de certificados SSL centralizada
├── correo/          # Configuración del servidor de correo corporativo
├── gestion/         # Herramientas internas (Portainer, Vault, RainLoop)
├── publico/         # Web WordPress (Alta Disponibilidad)
├── secrets/         # Contraseñas cifradas inyectadas en Docker
├── db_data/         # Volúmenes persistentes de MariaDB
├── vault_data/      # Volúmenes persistentes de Vaultwarden
└── wordpress_data/  # Archivos y plugins de WordPress
```
Esta centralización permite que, si un contenedor se destruye, la información crítica (como `db_data` o `wordpress_data`) permanezca intacta en el disco duro físico del servidor. Asimismo, evita la duplicidad de archivos como los certificados SSL, que ahora son consumidos por todos los servicios desde un único punto central (`certs/`).

> 📸 **[Haz una captura en la terminal ejecutando el comando `tree -L 1 infraestructura/` o `ls -lh infraestructura/` para demostrar la organización limpia y profesional de las carpetas del proyecto]**

### **3.2. Entorno Público: Clúster Web y Proxy Inverso Nginx**
Para alojar la web corporativa, se utiliza un Proxy Inverso Nginx que recibe el tráfico de Internet y lo balancea entre múltiples contenedores.

**Configuración Destacada de Nginx Público:**
Se ha habilitado compresión GZIP para acelerar la carga web, cabeceras de seguridad estrictas (HSTS, Anti-XSS) y un balanceador de carga tipo `ip_hash`. El `ip_hash` garantiza que, cuando un usuario inicie sesión, sus peticiones vayan siempre al mismo contenedor de WordPress (persistencia de sesión), algo vital en aplicaciones dinámicas.

```nginx
# Fragmento de /infraestructura/publico/nginx.conf
http {
    # --- OPTIMIZACIÓN GZIP WORDPRESS ---
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
    
    # --- CABECERAS SEGURIDAD ---
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-XSS-Protection "1; mode=block";

    # --- BALANCEADOR WORDPRESS CON IP_HASH ---
    upstream wordpress_cluster {
        ip_hash;
        server wordpress:8080; # Nginx balancea a las réplicas mediante el DNS de Docker
    }

    server {
        listen 443 ssl;
        server_name canarias.local 10.0.10.10;
        
        location / {
            proxy_pass http://wordpress_cluster;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

**Alta Disponibilidad en Docker Compose:**
El servicio de WordPress se levanta en un clúster utilizando el comando `replicas: 3`. Si una de estas réplicas sufre una caída (por saturación de RAM o ataque), Docker reinicia automáticamente el nodo mientras Nginx deriva el tráfico a los otros dos. Esto garantiza un **tiempo de inactividad casi nulo (Zero Downtime)**.
La base de datos (MariaDB) maneja todas las consultas de este clúster simultáneamente, manteniendo la coherencia de los datos.

> 📸 **[Haz una captura en el servidor Docker con el comando `docker ps --format "table {{.Names}}\t{{.Status}}"` para que se vea mejor cómo las tres instancias de WordPress se están ejecutando simultáneamente y validan el clúster HA]**

---

### **3.2. Entorno de Gestión: El Búnker Interno**
La administración de la infraestructura está aislada en la IP `10.0.10.20`. 
El Proxy Nginx de esta zona actúa como "Gatekeeper", analizando la cabecera HTTP enviada por el cliente y enrutando el tráfico por **subdominios (SNI)** hacia las distintas herramientas internas a través de un solo puerto (443).

```nginx
# Fragmento de /infraestructura/gestion/nginx.conf
server {
    listen 443 ssl;
    server_name docker.canarias.local;
    location / { proxy_pass http://portainer_web:9000/; }
}
```

#### **A. Gestión de Contenedores: Portainer**
Desplegar y mantener múltiples contenedores por CLI puede generar errores humanos. Por ello, se ha integrado **Portainer**, una interfaz gráfica potente.
*   **Funcionamiento:** Portainer monta el socket nativo de Docker (`/var/run/docker.sock`) dentro del contenedor.
*   **Ventaja:** Permite visualizar logs en tiempo real, reiniciar servicios, consultar el uso de CPU/RAM de cada réplica de WordPress e inspeccionar la red interna (`infraestructura_app_net`), todo desde un entorno web accesible en `https://10.0.10.20:9443` o `https://docker.canarias.local`.

#### **B. Gestor de Contraseñas: Vaultwarden**
Las empresas manejan cientos de credenciales compartidas. Para evitar brechas, se usa Vaultwarden (compatible con Bitwarden).
*   **Configuración:** Se habilitaron los WeSockets (`WEBSOCKET_ENABLED=true`) para que la sincronización entre los navegadores y la base de datos local sea instantánea.
*   **Seguridad:** Las claves no salen de la empresa, y la base de datos se cifra en el volumen `vault_data`.

#### **C. Monitorización Visual y Centro de Control (Uptime Kuma)**
Para garantizar la observabilidad de toda la infraestructura en tiempo real, se ha desplegado **Uptime Kuma**, actuando como un centro de control de operaciones de red (NOC).

*   **Página de Estado Corporativa (Dashboard):** Se ha diseñado una interfaz visual unificada en `https://status.canarias.local/status/servicios`. Este panel utiliza un tema oscuro de alta visibilidad y CSS personalizado para facilitar la supervisión rápida por parte del equipo técnico.
*   **Diversidad de Sondas de Monitorización:**
    *   **Sondas HTTP(s):** Verificación de capa de aplicación para WordPress y Vaultwarden, monitorizando tiempos de respuesta y validez de certificados SSL.
    *   **Sondas TCP Port:** Supervisión de servicios críticos sin interfaz web, como la **Base de Datos MariaDB** (puerto 3306) y el servidor de correo **SMTP** (puerto 25).
    *   **Sondas DNS:** Verificación de la salud del Router central, comprobando que resuelve correctamente los dominios internos.
*   **Organización por Etiquetas (Tagging):** Los servicios se han categorizado cromáticamente: `[RED]` (Rojo) para conectividad base, `[WEB]` (Azul) para servicios públicos y `[ADMIN]` (Amarillo) para herramientas internas.
*   **Optimización de Red (WebSockets):** Se ha configurado el proxy inverso Nginx con soporte para WebSockets (`Upgrade` y `Connection`), permitiendo que las gráficas de latencia se actualicen en el navegador de forma instantánea sin refrescar la página.

> 📸 **[Haz una captura de la "Página de Estado" final (la que tiene el logo y el fondo oscuro) donde se vean todos los servicios en verde con sus etiquetas de colores, para demostrar un nivel de monitorización profesional]**

#### **D. Plan de Recuperación ante Desastres (Duplicati)**
Como evolución del script de copias de seguridad local, se ha implementado **Duplicati** para gestionar el Disaster Recovery Plan (DRP) en la nube.
*   **Arquitectura de Respaldo Híbrida:** El servidor realiza volcados locales (`mysqldump` y `tar`) de los datos críticos a la carpeta `/home/admin1234/backups`. El contenedor de Duplicati monta esta carpeta en modo *Solo Lectura* (`:ro`), asegurando que el motor de copia no pueda corromper los datos originales.
*   **Seguridad y Deduplicación:** Duplicati cifra los datos utilizando AES-256 antes de salir de la red corporativa y los sube a **Google Drive**. Además, aplica deduplicación para ahorrar espacio y ancho de banda.
*   **Acceso Web:** Publicado en `https://backup.canarias.local`, ofrece una interfaz gráfica para auditar el estado de los backups y programar tareas `cron` visualmente.

> 📸 **[Haz una captura del panel de Duplicati configurado o conectando con el proveedor de la nube]**

#### **E. Sistema de Correo Corporativo (Docker-Mailserver + RainLoop)**
Uno de los hitos más complejos del proyecto es la implementación de un sistema de correo electrónico completo e independiente. Está conformado por dos contenedores comunicados internamente:

1.  **Backend (El Servidor SMTP/IMAP - Mailserver):**
    Utiliza la imagen `docker-mailserver`. Centraliza todas las cuentas (`jeremy`, `adonay`, `ikram`, `patricia`, `aitor`, `admin`, `facturacion`).
    *   **Seguridad Antispam y Anti-fuerza bruta:** Se han habilitado mediante variables de entorno en el `docker-compose-mail.yml` los módulos `ENABLE_SPAMASSASSIN=1` y `ENABLE_FAIL2BAN=1`. Esto protege el servidor contra bots de envío masivo.
    *   **Certificados SSL:** Para permitir envío por puertos seguros (465, 993, 587), se han montado los mismos certificados de la PKI generada por el servidor (`server.crt` y `server.key`).
    *   **Alias Virtuales (`postfix-virtual.cf`):** Se ha diseñado una lógica de distribución muy útil. Se han creado buzones departamentales; por ejemplo, si alguien escribe a `info@canarias.local` o `ventas@canarias.local`, el correo le llega simultáneamente a *Ikram* y *Patricia*. Si escriben a `soporte@canarias.local`, le llega a *Aitor* y *Adonay*.

2.  **Frontend (El Cliente Web - RainLoop):**
    Los empleados no necesitan configurar Outlook o Thunderbird. Acceden a `https://mail.canarias.local`, gestionado por el contenedor de RainLoop. Este servicio webmail se conecta de forma privada por la red de Docker al `mailserver` en los puertos 25 y 143, por lo que la comunicación es extremadamente rápida y segura.

> 📸 **[Haz una captura en la terminal del servidor haciendo un `cat infraestructura/correo/mail-config/postfix-virtual.cf` para que se vea mejor cómo están mapeados los alias como ventas@ o soporte@ a las cuentas individuales de los empleados]**

---

## **4. Seguridad Criptográfica e Infraestructura de Clave Pública (PKI)**
Para proteger el intercambio de credenciales, todo el tráfico HTTP es redirigido forzosamente a HTTPS (Puerto 443). Dado que es un entorno corporativo privado, se ha implementado una Autoridad de Certificación (CA) propia.

1.  **Creación de Certificados:** Se ha generado una llave privada raíz (`canarias_root.key`) y un certificado firmado (`server.crt`).
2.  **Portal PKI:** En lugar de enviar el certificado por pendrive, el Nginx de gestión cuenta con un bloque `location /certs/` que sirve un pequeño portal web (`pki.canarias.local` o `10.0.10.20`). Desde ahí, los empleados instalan el certificado en el almacén "Entidades de certificación raíz de confianza" de sus navegadores Windows/Linux.

```nginx
# Portal de descarga del Certificado Raíz
location /certs/ {
    alias /etc/nginx/certs/;
    autoindex on;
    add_header Content-Disposition "attachment";
}
```

> 📸 **[Haz una captura accediendo al portal PKI o mostrando el candado verde 🔒 en el navegador accediendo a `https://vault.canarias.local`, indicando que está validado por "CanarIAs Root CA", para justificar el uso de cifrado local]**

---

## **5. Desafíos Técnicos y Resolución de Problemas (Troubleshooting)**
Durante el despliegue se presentaron retos técnicos complejos que requirieron un análisis profundo de protocolos y logs, cuya resolución eleva la robustez final del sistema:

### **5.1. Conflicto de "Agujero Negro" en el DNS (Wildcard Conflict)**
*   **El Problema:** Al intentar acceder a `status.canarias.local`, el sistema redirigía erróneamente al WordPress público. 
*   **Análisis:** Se descubrió que el archivo de zona de BIND tenía un registro tipo "A" comodín (`@ IN A 10.0.10.10`) que capturaba cualquier subdominio no definido.
*   **Solución:** Se reestructuró la configuración de `dnsmasq` en el Router, definiendo subdominios explícitos y eliminando la ambigüedad, garantizando que cada servicio apunte a su interfaz correspondiente (.10 o .20).

### **5.2. Pérdida de Internet por Opción DHCP 121 (RFC 3442)**
*   **El Problema:** Al activar las rutas estáticas para que los clientes llegaran a la red de servidores, estos perdían el acceso a Internet.
*   **Análisis:** Según el estándar RFC 3442, si un cliente recibe rutas estáticas por DHCP (Opción 121), ignora automáticamente la puerta de enlace predeterminada.
*   **Solución:** Se inyectó la ruta `0.0.0.0/0` directamente dentro de la Opción 121 en el archivo `dhcpd.conf`, restaurando la navegación externa y el acceso interno simultáneamente.

### **5.3. Estrategia de Resiliencia: Scripts de Auto-Reparación**
Para mitigar la volatilidad de las configuraciones en memoria (Iptables, rutas temporales), se han desarrollado scripts de "limpieza y re-aprovisionamiento":
*   **`auto_reparar_router.sh`**: Limpia reglas de firewall duplicadas, aplica el MSS Clamping y levanta el DNS/DHCP.
*   **`auto_reparar_servidor.sh`**: Asegura el bypass de Docker y las rutas de retorno a la oficina.
*   **Automatización:** Ambos scripts están programados en el **crontab (@reboot)**, garantizando que el sistema sea capaz de auto-sanarse tras un apagón accidental o reinicio.

---

## **6. Acceso Remoto Seguro y Teletrabajo (VPN Mesh con Tailscale)**
Para modernizar la infraestructura y permitir el acceso seguro de los empleados desde sus hogares (Teletrabajo), se ha implementado una solución de **VPN Mesh basada en el protocolo WireGuard** a través de Tailscale. Esta tecnología permite conectar dispositivos de forma punto a punto mediante túneles cifrados de extremo a extremo, eliminando la necesidad de abrir puertos peligrosos (como el 1194 de OpenVPN) en el router físico de la instalación.

### **6.1. Proceso de Instalación Técnica en el Router**
La instalación se realizó en el Router Ubuntu Server siguiendo un proceso de endurecimiento de repositorios para garantizar la integridad del software:
1.  **Gestión de Claves GPG:** Se importó la clave pública oficial de Tailscale para validar la firma de los paquetes y evitar ataques de suplantación (Man-in-the-Middle).
2.  **Configuración de Repositorios:** Se añadió el repositorio específico para la versión *Jammy (22.04)* en `/etc/apt/sources.list.d/tailscale.list`.
3.  **Despliegue del Binario:** Se instaló el paquete `tailscale`, el cual levanta un demonio (`tailscaled`) que gestiona la interfaz de red virtual `tailscale0`.

### **6.2. Configuración como "Subnet Router" (Puente de Red)**
A diferencia de una VPN tradicional donde cada máquina debe tener el cliente instalado, se ha configurado el Router como un **Subnet Router**. Esto permite que el router actúe como una pasarela (Gateway) transparente.
*   **Publicación de Redes:** Mediante el comando `sudo tailscale up --advertise-routes=10.0.10.0/24,10.0.20.0/24`, el router anuncia a la red Mesh que él conoce el camino para llegar a los servidores y a la oficina.
*   **Aprobación en el Panel de Control:** Se accedió a la consola web de Tailscale bajo la cuenta dedicada `jeremira11092005@gmail.com` para autorizar manualmente estas rutas, cumpliendo con el principio de **mínimo privilegio**.

### **6.3. Implementación de "Split DNS" Corporativo**
Para garantizar una experiencia de usuario fluida, se configuró un sistema de **DNS Dividido**:
*   **Lógica:** Los dispositivos remotos (móviles, portátiles externos) mantienen su DNS normal para navegar por Internet, pero redirigen automáticamente las consultas terminadas en `.canarias.local` hacia la IP interna del router en la VPN (`100.101.99.58`).
*   **Configuración en Dnsmasq:** Se ajustó el servicio DNS del router para que escuche peticiones en la interfaz virtual `tailscale0`, permitiendo la resolución de nombres desde cualquier parte del mundo.

### **6.4. Optimización de Rendimiento y MTU (MSS Clamping)**
Uno de los mayores retos en redes VPN sobre 4G/5G es la fragmentación de paquetes. Para evitar que la conexión se sienta lenta o se "congele", se implementó una regla de **TCP MSS Clamping** en el firewall del router:
```bash
sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```
Esta regla fuerza a que los paquetes de datos se ajusten al tamaño máximo permitido por el túnel WireGuard, garantizando una carga instantánea de la web corporativa y el cofre de contraseñas.

### **6.5. Filosofía Zero Trust y Seguridad**
Gracias a Tailscale, se ha logrado una arquitectura **Zero Trust**:
*   **Cifrado:** Todo el tráfico entre el administrador y el servidor de gestión viaja cifrado con **ChaCha20-Poly1305**.
*   **Visibilidad:** Desde el panel web, el administrador puede ver en tiempo real quién está conectado, desde qué dispositivo y qué IP de la VPN está utilizando, facilitando la auditoría de seguridad.

---

## **7. Conclusiones y Validación Global**
El proyecto "CanarIAs S.L.L." demuestra una implantación completa de los conocimientos adquiridos en el ciclo de ASIR. Se ha logrado pasar de conceptos aislados (DNS, DHCP, Docker, Nginx, Iptables) a una arquitectura integrada, coherente y tolerante a fallos.

**Logros alcanzados:**
*   Aislamiento exitoso entre capas de Red (Capa 3) y Aplicación (Capa 7).
*   Resiliencia garantizada mediante el clúster de contenedores WordPress y persistencia segura de datos.
*   Infraestructura de correo corporativo unificada y segura con alias y webmail integrados.
*   Control centralizado de acceso mediante DMZ, proxy inverso y cifrado SSL auto-gestionado.

### **Futuras Mejoras (Hoja de Ruta)**
*   Implantar un agente de copias de seguridad remotas (BorgBackup / Restic).
*   Despliegue de un entorno de monitorización en tiempo real (Prometheus + Grafana).
*   Automatización de la instalación de los routers utilizando metodologías de Infraestructura como Código (Ansible).
