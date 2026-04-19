# 🏢 Infraestructura CanarIAs - Proyecto Final ASIR

# [📅 Organización del Proyecto](./Organizacion_Proyecto_ASIR.md) 

---

Este repositorio contiene la arquitectura completa de **Servidores, Redes y Seguridad** basada en Docker para la infraestructura empresarial de **CanarIAs**. Un ecosistema blindado, replicado y automatizado bajo estándares profesionales.

## 🚀 Vista General de la Arquitectura

La infraestructura se basa en una **segmentación física Multi-NIC** (ens33, ens37, ens38) para aislar el tráfico público del administrativo, implementando una **DMZ Real** mediante reglas de enrutamiento en el kernel.

### 🗺️ Mapa Estructural del Proyecto

```text
/home/admin1234/
├── 📁 infraestructura/
│   ├── 🌍 publico/            # ZONA DMZ (IP: 10.0.10.10) -> WordPress HA + MariaDB
│   ├── 🛡️ gestion/            # ZONA ADMIN (IP: 10.0.10.20) -> Vaultwarden + Portainer
│   ├── 📟 router/             # NÚCLEO DE RED (NAT/DHCP) -> Configuración Perimetral
│   ├── 📧 correo/             # SERVIDOR MAIL -> Docker-MailServer + Webmail
│   ├── 🔑 certs/              # SEGURIDAD SSL -> Autoridad de Certificación (CA) propia
│   └── 🔒 secrets/            # GESTIÓN DE CLAVES -> Docker Secrets
├── 💾 backups/                # PERSISTENCIA -> Copias de Seguridad (.sql / .tar.gz)
├── ⚡ instalar_dependencias.sh # AUTOMATIZACIÓN -> Despliegue en un solo comando
├── 🛠️ auto_reparar.sh         # RESILIENCIA -> Script de auto-curación del Servidor
└── 🛠️ auto_reparar_router.sh  # RESILIENCIA -> Script de auto-curación del Router
```

---

## 🔐 Matriz de Accesos y Seguridad (DMZ Blindada)

Tras el blindaje del router perimetral, los accesos están estrictamente zonificados:

| Perfil de Usuario | Punto de Entrada | WordPress (.10) | Gestión (.20) | Portainer/Vault |
| :--- | :--- | :--- | :--- | :--- |
| **Cliente (Internet)** | IP del Router | ✅ **Público** | ❌ **RECHAZADO** | ❌ **BLOQUEADO** |
| **Socio (Oficina)** | Red Local 10.0.20.x | ✅ Permitido | ✅ **Acceso Total** | ✅ **Acceso Total** |
| **Administrador** | SSH / Red Mantenimiento | ✅ Gestión | ✅ Gestión | ✅ Gestión |

---

## 🛠️ Guía de Despliegue y Mantenimiento

### 1. Instalación en Limpio
Para levantar toda la infraestructura en un servidor virgen, ejecute el instalador maestro:
```bash
git clone git@github.com:XxtrotamundoxX/CanarIAs-Infraestructura.git .
bash instalar_dependencias.sh
```

### 2. Gestión de Red Avanzada (Métricas)
Se ha implementado una solución de **Rutas Asimétricas** para permitir que el servidor gestione múltiples tarjetas de red en la misma subred:
- **Prioridad Web (.10):** Métrica 100 en `ens33`.
- **Prioridad Gestión (.20):** Métrica 50 en `ens37`.
- **Blindaje Kernel:** Desactivado `rp_filter` para permitir respuestas Multi-Homed.

### 3. Sistema de Backups Automatizado
El script `hacer_backup.sh` garantiza la continuidad del negocio:
- Exportación Hot-Backup de MariaDB.
- Compresión de multimedia y configuraciones.
- Rotación automática de 7 días.

---

## 📋 Documentación de Apoyo

- **[📅 Organización del Proyecto](./Organizacion_Proyecto_ASIR.md):** Metodología, tiempos de entrega y planificación de tareas.
- **[📄 Informe Técnico Final](./Informe_Final_ASIR_CanarIAs.md):** Memoria técnica extensa con detalles de IP, certificados, diagramas ASCII y cuadro maestro de credenciales. *(Nota: Por seguridad, este archivo solo es accesible localmente en el servidor).*

---

## ⚠️ Advertencia de Seguridad
Este repositorio incluye configuraciones de red y certificados raíz para facilitar la portabilidad académica. En un entorno de producción real, las carpetas `/certs` y `/secrets` deben gestionarse mediante gestores de secretos externos (como Vault o AWS Secrets Manager).

---
**Proyecto Final Ciclo Superior ASIR - 2026**
