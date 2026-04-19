#!/bin/bash
# =============================================================
# @File: hacer_backup.sh
# @Ubicación: Se ejecuta en el SERVIDOR Docker (10.0.10.10)
# @Description: Script de copias de seguridad automatizadas.
#
# @Para qué sirve: Realiza una copia de seguridad completa de los
#   dos componentes críticos de la infraestructura:
#     1. Base de datos MariaDB (toda la información de WordPress)
#     2. Archivos de WordPress (temas, plugins, imágenes subidas)
#
# @Cómo funciona:
#   - La BD se exporta con 'mysqldump' (backup en caliente, sin
#     parar el servicio). Se genera un archivo .sql que contiene
#     todos los comandos SQL necesarios para reconstruir la BD.
#   - Los archivos de WordPress se comprimen con 'tar' en un
#     archivo .tar.gz (formato estándar de compresión en Linux).
#   - Los backups de más de 7 días se borran automáticamente
#     para no saturar el disco del servidor.
#
# @Cuándo ejecutarlo: Manualmente o con cron (ej. cada noche a las 3AM).
# @Mejora futura: Migrar a Restic para tener cifrado, deduplicación
#   y sincronización a Google Drive (ver analisis_backup_restic.md).
# =============================================================

# Directorio donde se guardan las copias (crear si no existe)
BACKUP_DIR="/home/admin1234/backups"
# Fecha y hora actual para nombrar los archivos de forma única
DATE=$(date +%Y-%m-%d_%H%M%S)

echo "--- Iniciando Backup: $DATE ---"

# ----- PASO 1: BACKUP DE LA BASE DE DATOS -----
# @Para qué sirve: Exporta TODA la base de datos de WordPress a un
#   archivo .sql. Usa '--single-transaction' implícito de mysqldump
#   para no bloquear las tablas mientras se hace la copia (backup
#   en caliente = la web sigue funcionando durante el proceso).
# @Resultado: Un archivo como db_backup_2026-04-18_030000.sql
docker exec base_datos mysqldump -u admin1234 -padmin1234 admin1234 > $BACKUP_DIR/db_backup_$DATE.sql

# ----- PASO 2: BACKUP DE ARCHIVOS WORDPRESS -----
# @Para qué sirve: Comprime la carpeta completa de WordPress que
#   contiene los temas (themes), plugins, archivos multimedia (uploads)
#   y la configuración (wp-config.php). Sin estos archivos, el sitio
#   web no se puede reconstruir aunque tengamos la BD.
# @Resultado: Un archivo como wp_files_2026-04-18_030000.tar.gz
tar -czf $BACKUP_DIR/wp_files_$DATE.tar.gz /home/admin1234/infraestructura/wordpress_data

# ----- PASO 3: LIMPIEZA DE BACKUPS ANTIGUOS -----
# @Para qué sirve: Borra automáticamente los archivos de backup con
#   más de 7 días de antigüedad. Sin esto, el disco se llenaría
#   progresivamente con copias acumuladas.
# @Nota: -mtime +7 significa "modificado hace más de 7 días"
find $BACKUP_DIR -type f -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -type f -name "*.tar.gz" -mtime +7 -delete

echo "--- Backup Finalizado con éxito ---"
