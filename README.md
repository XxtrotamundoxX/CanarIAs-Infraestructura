# [📄 Ver Informe Técnico Final (Local)](./Informe_Final_ASIR_CanarIAs.md) | [📅 Organización del Proyecto](./Organizacion_Proyecto_ASIR.md)

---

# Infraestructura CanarIAs

Este repositorio contiene la arquitectura completa de servicios web, gestion y correo basada en Docker para el proyecto CanarIAs. Todo el despliegue esta contenerizado y orquestado mediante archivos docker-compose.yml.

## Estructura del Proyecto

```text
/home/admin1234/
├── infraestructura/
│   ├── publico/            # ZONA DMZ (IP: 10.0.10.10)
│   │   ├── docker-compose.yml
│   │   └── nginx.conf
│   ├── gestion/            # ZONA ADMIN (IP: 10.0.10.20)
│   │   ├── docker-compose.yml
│   │   └── nginx.conf
│   ├── router/             # CONFIGURACIÓN ROUTER (DHCP/NAT)
│   │   ├── dhcpd.conf
│   │   └── instalar_router.sh
│   ├── correo/             # SERVIDOR MAIL
│   │   ├── docker-compose-mail.yml
│   │   └── mail-config/
│   ├── certs/              # CERTIFICADOS SSL (CA PROPIA)
│   └── secrets/            # CLAVES DE BASE DE DATOS
├── backups/                # COPIAS DE SEGURIDAD (.sql / .tar.gz)
├── hacer_backup.sh         # SCRIPT AUTOMATIZADO DE BACKUP
└── instalar_dependencias.sh # SCRIPT DE INSTALACIÓN EN LIMPIO
```

El servidor se divide en tres grandes modulos de red, conectados mediante la red puente infraestructura_app_net:

- **/gestion (IP: 10.0.10.20)**
  - Nginx proxy: Balanceador interno para herramientas de gestion.
  - Vaultwarden: Gestor de contrasenas (puerto 8443).
  - Portainer: Panel de administracion de contenedores Docker (puerto 9443).
  - Rainloop: Cliente Webmail (puerto 8888, expuesto en /mail/).

- **/publico (IP: 10.0.10.10)**
  - Nginx proxy: Balanceador web principal con redireccion HTTP a HTTPS.
  - WordPress: Despliegue en alta disponibilidad con 3 replicas.
  - MariaDB: Base de datos relacional para el sitio WordPress.

- **/correo (mail.canarias.local)**
  - Docker-MailServer: Servidor completo SMTP/IMAP con SpamAssassin, Fail2Ban y ClamAV.
  - Incluye configuraciones de dominios y enrutamiento interno.

## Matriz de Accesos y Seguridad (DMZ Blindada)

Tras la actualización del router perimetral (Abril 2026), los accesos han sido blindados mediante un sistema de "Búnker de Gestión":

| Origen | Destino | Servicio | Estado |
| :--- | :--- | :--- | :--- |
| **Cualquiera (WAN/Invitados)** | `10.0.10.10` | WordPress (80/443) | ✅ **PERMITIDO** |
| **Cualquiera (WAN/Invitados)** | `10.0.10.20` | Gestión (Vault/Portainer) | ❌ **BLOQUEADO (DROP)** |
| **Oficina (10.0.20.X)** | `10.0.10.20` | Gestión Completa | ✅ **PERMITIDO** |
| **Administrador (SSH)** | Cualquier IP | Consola (22) | ✅ **PERMITIDO** |

### Automatización de Red y Resolución de Nombres (DNS)
La infraestructura cuenta con servicios de red autogestionados para facilitar la administración:

*   **DNS Interno (Bind9):** Resolución de nombres en el dominio `.canarias.local`.
    *   `wp.canarias.local` -> Web Pública (10.0.10.10)
    *   `gestion.canarias.local` -> Administración (10.0.10.20)
    *   `pki.canarias.local` -> Portal de Seguridad y Certificados (10.0.10.20)
*   **Portal de Seguridad (PKI):** Acceso centralizado en `http://pki.canarias.local` para la descarga e instalación del Certificado Raíz (CA) de la empresa, garantizando conexiones HTTPS verificadas sin errores de seguridad.
*   **DHCP Avanzado (Opción 121):** Configuración automática de rutas estáticas en los clientes. Los empleados reciben automáticamente la ruta hacia la red de servidores (`10.0.10.0/24`) sin intervención manual.
*   **Salida a Internet:** El router realiza NAT/Masquerade para todas las subredes internas.


## Guía de Despliegue Rápido (Servidor Limpio)

Si está instalando esta infraestructura en un servidor totalmente nuevo, siga estos pasos para automatizar la configuración de Docker y redes:

```bash
# 1. Clonar el repositorio
git clone git@github.com:XxtrotamundoxX/CanarIAs-Infraestructura.git .

# 2. Ejecutar el instalador de dependencias y recursos
bash instalar_dependencias.sh

# 3. Iniciar los contenedores (Siga el orden de la sección 'Guia de Despliegue')
```

## Migración Completa a otro Servidor

Para mover toda su infraestructura (incluyendo datos de WordPress y correos) de un servidor a otro:

1. **En el Servidor Antiguo:** Ejecute `./hacer_backup.sh` para generar los archivos `.sql` y `.tar.gz`.
2. **Transferencia:** Mueva los archivos generados en la carpeta `backups/` al nuevo servidor (usando `scp` o un pendrive).
3. **En el Servidor Nuevo:** 
   - Realice el **Despliegue Rápido** (pasos anteriores).
   - Restaure los archivos según la sección **Restauracion de Datos** de este documento.

## Configuración de Red Avanzada (Segmentación Multi-NIC)

Si se utilizan múltiples interfaces de red (NICs) en el mismo rango de subred (ej: `10.0.10.x`), es necesario ajustar el kernel y las rutas para evitar conflictos de "Asymmetric Routing" (Rutas Asimétricas).

### 1. Ajustes del Kernel (rp_filter)
Para permitir que el servidor responda por la interfaz correcta cuando recibe peticiones en una subred compartida, desactive el filtrado de ruta inversa:
```bash
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.ens33.rp_filter=0
sudo sysctl -w net.ipv4.conf.ens37.rp_filter=0
```
*Nota: Para que estos cambios sean persistentes tras un reinicio, añádalos al archivo `/etc/sysctl.conf`.*

### 2. Advertencia sobre el Cortafuegos (UFW / Iptables)
**¡CUIDADO!** Si el servidor tiene activo un firewall (como `ufw`), este puede bloquear las peticiones externas aunque las IPs y rutas estén bien configuradas. Para evitar problemas de "NetworkError" o pings fallidos:

- **Comprobar estado:** `sudo ufw status`
- **Permitir tráfico en las interfaces específicas:**
  ```bash
  sudo ufw allow in on ens33 to any port 80,443 proto tcp
  sudo ufw allow in on ens37 to any port 8443,9443 proto tcp
  ```
- **Si hay problemas persistentes:** Pruebe a desactivar temporalmente el firewall (`sudo ufw disable`) para descartar que sea el causante del bloqueo.

### 3. Priorización de Rutas (Métricas)
Es crucial definir qué interfaz tiene prioridad para el tráfico saliente de la subred compartida:
```bash
# Prioridad para el tráfico general en la red pública
sudo ip route add 10.0.10.0/24 dev ens33 proto kernel scope link src 10.0.10.10 metric 100
# Ruta específica para la IP de gestión
sudo ip route add 10.0.10.20 dev ens37 scope link src 10.0.10.20 metric 50
```

## Guía de Verificación de Conectividad

Para validar que la infraestructura está operativa desde un cliente externo (ej. IP `10.0.10.51`):

1. **Prueba de Red Básica (ICMP):**
   ```bash
   ping -c 4 10.0.10.10  # Debe responder la interfaz de WordPress (ens33)
   ping -c 4 10.0.10.20  # Debe responder la interfaz de Gestión (ens37)
   ```

2. **Prueba de Servicios Web:**
   ```bash
   # Verificar Nginx Público (WordPress)
   curl -I http://10.0.10.10
   
   # Verificar Nginx Gestión (Vaultwarden - Usar -k por certificado auto-firmado)
   curl -k -I https://10.0.10.20:8443
   ```

3. **Monitorización de Tráfico Real:**
   En el servidor, puede verificar por qué "cable" físico entra el tráfico usando tcpdump:
   ```bash
   sudo tcpdump -i ens33 icmp  # Monitoriza pings al WordPress
   sudo tcpdump -i ens37 icmp  # Monitoriza pings a la Gestión
   ```

## Acceso a las aplicaciones

- **Sitio Web Público:** [https://canarias.local](https://canarias.local)
- **Gestor de Contraseñas (Vaultwarden):** [https://10.0.10.20:8443](https://10.0.10.20:8443)
- **Gestión Docker (Portainer):** [https://10.0.10.20:9443](https://10.0.10.20:9443)
- **Correo Web (Rainloop):** [https://10.0.10.20/mail/](https://10.0.10.20/mail/)

## Credenciales de Acceso (Entorno de Pruebas)

| Servicio | Usuario | Contraseña | URL de Admin |
| :--- | :--- | :--- | :--- |
| **WordPress** | `admin1234` | `admin1234` | `/wp-admin` |
| **Webmail** | `admin@canarias.local` | `admin1234` | `/mail/` |
| **Vaultwarden (Panel Admin)** | `admin` | `admin1234` | `/admin` |
| **Portainer** | `admin1234` | `admin1234admin` | `https://10.0.10.20:9443` |

*Nota: Todas las cuentas de correo adicionales (`jeremy`, `adonay`, etc.) también utilizan la contraseña `admin1234` por defecto.*

## Guia de Despliegue

Siga estos pasos para levantar la infraestructura en un servidor Ubuntu o Debian con Docker instalado:

### 1. Clonar el repositorio
Clone el proyecto en el directorio deseado:

```bash
git clone git@github.com:XxtrotamundoxX/CanarIAs-Infraestructura.git .
```

### 2. Instalacion de Dependencias
Asegurese de tener Docker y Docker Compose instalados:

```bash
sudo apt update && sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker
```

### 3. Crear red externa de Docker
Es necesario crear la red comun manualmente antes de iniciar los servicios:

```bash
docker network create infraestructura_app_net
```

### 4. Levantar los servicios
Inicie los modulos en el siguiente orden para gestionar correctamente las dependencias:

```bash
# 1. Servidor de correo
cd infraestructura/correo
docker-compose -f docker-compose-mail.yml up -d

# 2. Servicios web publicos (WordPress + MariaDB)
cd ../publico
docker-compose up -d

# 3. Servicios de gestion interna
cd ../gestion
docker-compose up -d
```

### 5. Configurar el acceso (Hosts / DNS)
Configure las IPs en su servidor DNS o en el archivo hosts local:

```text
10.0.10.10    canarias.local  mail.canarias.local
```

## Sistema de Backups

El script hacer_backup.sh en la raiz del proyecto realiza las siguientes tareas:
1. Exportacion de la base de datos MariaDB (Hot Backup).
2. Compresion de la carpeta wordpress_data (Plugins, temas e imagenes).
3. Limpieza automatica de copias de seguridad con mas de 7 dias de antiguedad.

Se recomienda programar su ejecucion mediante Cron:
```bash
0 3 * * * /home/admin1234/hacer_backup.sh >> /home/admin1234/backups/cron.log 2>&1
```

## Restauracion de Datos

Para restaurar una instalacion previa a partir de un backup:
1. Copie el archivo .sql a la carpeta backups/.
2. Ejecute: sudo docker exec -i base_datos mysql -u admin1234 -padmin1234 admin1234 < backups/nombre_archivo.sql
3. Descomprima los archivos de WordPress en infraestructura/wordpress_data/.

## Advertencia sobre Datos Sensibles

Este repositorio incluye configuraciones y claves en las carpetas /secrets/ y /certs/ para facilitar la portabilidad. Las bases de datos masivas y los buzones de correo estan excluidos de Git por seguridad y rendimiento.
