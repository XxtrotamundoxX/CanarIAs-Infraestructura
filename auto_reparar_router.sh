#!/bin/bash
# =============================================================
# @File: auto_reparar_router.sh (VERSIÓN BLINDADA CON DMZ)
# @Description: Reconstruye las reglas de iptables protegiendo
#               la gestión de accesos no autorizados.
# =============================================================

echo "🛡️ --- Iniciando Blindaje de DMZ (CanarIAs Router) ---"

# ---- PASO 1: LIMPIAR REGLAS PREVIAS ----
iptables -F
iptables -t nat -F
iptables -t mangle -F

# ---- PASO 2: POLÍTICA BASE ----
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# ---- PASO 3: OPTIMIZACIÓN (Mangle) ----
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# ---- PASO 4: TABLA FILTER — INPUT ----
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -i tailscale0 -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# ---- PASO 5: TABLA FILTER — FORWARD (SEGURIDAD DMZ) ----
# 5.1. Tailscale: Acceso Total
iptables -A FORWARD -i tailscale0 -j ACCEPT

# 5.2. Oficina (10.0.20.x) -> Servidores: Acceso Total
iptables -A FORWARD -s 10.0.20.0/24 -d 10.0.10.0/24 -j ACCEPT

# 5.3. Mantener conexiones activas
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# --- REGLAS DE BLOQUEO EXPLÍCITO ---
# 5.4. Invitados -> WordPress (Solo Web)
iptables -A FORWARD -s 10.0.30.0/24 -d 10.0.10.10 -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -s 10.0.30.0/24 -d 10.0.10.10 -p tcp --dport 443 -j ACCEPT

# 5.5. BLOQUEO CRÍTICO: Invitados -> Gestión (.20)
iptables -A FORWARD -s 10.0.30.0/24 -d 10.0.10.20 -j DROP

# 5.6. BLOQUEO CRÍTICO: Internet (ens33) -> Gestión (.20)
iptables -A FORWARD -i ens33 -d 10.0.10.20 -j DROP

# 5.7. Permitir SSH (Gestión Remota)
iptables -A FORWARD -p tcp --dport 22 -j ACCEPT

# 5.8. CANDADO FINAL: Cualquier tráfico no autorizado hacia Gestión
iptables -A FORWARD -d 10.0.10.20 -j DROP

# ---- PASO 6: TABLA NAT ----
# Redirección al WordPress público
iptables -t nat -A PREROUTING -i ens33 -p tcp --dport 80 -j DNAT --to 10.0.10.10:80
iptables -t nat -A PREROUTING -i ens33 -p tcp --dport 443 -j DNAT --to 10.0.10.10:443

# Masquerade (Salida a Internet)
iptables -t nat -A POSTROUTING -o ens33 -j MASQUERADE
iptables -t nat -A POSTROUTING -o ens37 -j MASQUERADE

# ---- PASO 7: REINICIAR SERVICIOS Y PERSISTENCIA ----
systemctl restart dnsmasq isc-dhcp-server
iptables-save > /etc/iptables/rules.v4

echo "✅ --- Router Blindado y DMZ Activa ---"
