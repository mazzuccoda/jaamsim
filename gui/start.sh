#!/bin/bash
# start.sh — Arranca la GUI nativa de JaamSim y la expone por noVNC.
#
# Cadena: Xvfb (X virtual) -> fluxbox (WM) -> x11vnc (VNC) ->
#         websockify/noVNC (web) -> JaamSim (java -jar, GUI).
set -euo pipefail

DISPLAY_NUM="${DISPLAY:-:0}"
W="${SCREEN_WIDTH:-1440}"
H="${SCREEN_HEIGHT:-900}"
D="${SCREEN_DEPTH:-24}"
NOVNC_PORT="${NOVNC_PORT:-8080}"
VNC_PORT="${VNC_PORT:-5900}"
JAR="/opt/jaamsim.jar"
JVM_OPTS="${JAVA_OPTS:--Xms256m -Xmx1536m}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] [gui] %s\n' "$(ts)" "$*"; }

# Directorio para el socket de noVNC y ubicación del cliente web
NOVNC_WEB=""
for d in /usr/share/novnc /usr/share/webapps/novnc; do
    [ -d "$d" ] && NOVNC_WEB="$d" && break
done
if [ -z "$NOVNC_WEB" ]; then
    log "ERROR: no se encontró el cliente noVNC (/usr/share/novnc)."
    exit 1
fi
# El index.html que redirige '/' -> vnc.html se crea en build (ver Dockerfile).

# --- Limpieza al salir -----------------------------------------------------
PIDS=()
cleanup() {
    log "Apagando procesos..."
    for p in "${PIDS[@]:-}"; do
        [ -n "${p:-}" ] && kill "$p" 2>/dev/null || true
    done
}
trap cleanup TERM INT EXIT

# --- 1) Xvfb ---------------------------------------------------------------
log "Iniciando Xvfb en ${DISPLAY_NUM} (${W}x${H}x${D}) ..."
rm -f /tmp/.X*-lock 2>/dev/null || true
Xvfb "${DISPLAY_NUM}" -screen 0 "${W}x${H}x${D}" -nolisten tcp -ac &
PIDS+=($!)
export DISPLAY="${DISPLAY_NUM}"

# Esperar a que el display esté disponible
for i in $(seq 1 30); do
    if xdpyinfo -display "${DISPLAY_NUM}" >/dev/null 2>&1; then break; fi
    sleep 0.3
done

# --- 2) Window manager -----------------------------------------------------
log "Iniciando fluxbox ..."
fluxbox >/dev/null 2>&1 &
PIDS+=($!)
sleep 1

# --- 3) x11vnc -------------------------------------------------------------
VNC_AUTH_ARGS=(-nopw)
if [ -n "${VNC_PASSWORD:-}" ]; then
    log "Configurando contraseña VNC ..."
    x11vnc -storepasswd "${VNC_PASSWORD}" "${HOME}/.vnc/passwd" >/dev/null 2>&1
    VNC_AUTH_ARGS=(-rfbauth "${HOME}/.vnc/passwd")
else
    log "ADVERTENCIA: VNC sin contraseña. Define VNC_PASSWORD para proteger el acceso."
fi

log "Iniciando x11vnc en el puerto ${VNC_PORT} ..."
x11vnc -display "${DISPLAY_NUM}" -rfbport "${VNC_PORT}" \
       -forever -shared -noxdamage -bg -o /tmp/x11vnc.log \
       "${VNC_AUTH_ARGS[@]}" >/dev/null 2>&1

# --- 4) noVNC / websockify -------------------------------------------------
log "Iniciando noVNC en http://0.0.0.0:${NOVNC_PORT}/ (cliente: ${NOVNC_WEB}) ..."
websockify --web="${NOVNC_WEB}" "${NOVNC_PORT}" "localhost:${VNC_PORT}" >/tmp/websockify.log 2>&1 &
PIDS+=($!)

# --- 5) JaamSim GUI --------------------------------------------------------
JAAMSIM_CMD=(java ${JVM_OPTS} -jar "${JAR}")
if [ -n "${JAAMSIM_MODEL:-}" ] && [ -f "${JAAMSIM_MODEL}" ]; then
    log "Abriendo JaamSim con el modelo: ${JAAMSIM_MODEL}"
    JAAMSIM_CMD+=("${JAAMSIM_MODEL}")
else
    [ -n "${JAAMSIM_MODEL:-}" ] && log "Modelo '${JAAMSIM_MODEL}' no encontrado; abriendo JaamSim vacío."
    log "Abriendo JaamSim (sin modelo)."
fi

log "================================================================"
log " JaamSim GUI lista."
log " Abrí en el navegador:  http://<IP-del-host>:${NOVNC_PORT}/vnc.html"
log "================================================================"

# JaamSim corre en primer plano: mientras viva, el contenedor sigue arriba.
# Si el usuario cierra la GUI, reabrimos automáticamente para mantener el
# servicio disponible (útil en Portainer).
while true; do
    "${JAAMSIM_CMD[@]}" >/tmp/jaamsim-gui.log 2>&1 || \
        log "JaamSim se cerró (code $?). Reabriendo en 3s ... (logs en /tmp/jaamsim-gui.log)"
    sleep 3
done
