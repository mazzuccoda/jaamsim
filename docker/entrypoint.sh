#!/bin/sh
# entrypoint.sh — Ejecuta un modelo JaamSim en modo headless/batch.
# Compatible con POSIX sh (NO usa bash).
set -e

# --- Colores ANSI ----------------------------------------------------------
# Se desactivan automáticamente si la salida no es una terminal.
if [ -t 1 ]; then
    C_RESET="$(printf '\033[0m')"
    C_INFO="$(printf '\033[0;36m')"   # cyan
    C_OK="$(printf '\033[0;32m')"     # verde
    C_WARN="$(printf '\033[0;33m')"   # amarillo
    C_ERR="$(printf '\033[0;31m')"    # rojo
else
    C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""
fi

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()      { printf '%s[%s] [INFO]  %s%s\n'  "$C_INFO" "$(ts)" "$1" "$C_RESET"; }
log_ok()   { printf '%s[%s] [OK]    %s%s\n'  "$C_OK"   "$(ts)" "$1" "$C_RESET"; }
log_warn() { printf '%s[%s] [WARN]  %s%s\n'  "$C_WARN" "$(ts)" "$1" "$C_RESET"; }
log_err()  { printf '%s[%s] [ERROR] %s%s\n'  "$C_ERR"  "$(ts)" "$1" "$C_RESET" >&2; }

# --- Manejo de error: NO terminar, dormir para poder leer logs -------------
fail() {
    log_err "$1"
    log_err "El contenedor permanecerá vivo (sleep infinity) para que puedas"
    log_err "revisar estos logs desde Portainer. Corrige el problema y reinicia."
    sleep infinity
}

JAR="/opt/jaamsim.jar"
MODEL="${JAAMSIM_MODEL:-/models/model.cfg}"
EXTRA_ARGS="${JAAMSIM_ARGS:-}"
JVM_OPTS="${JAVA_OPTS:--Xms256m -Xmx1g}"
RUN_AS="${JAAMSIM_USER:-jaamsim}"

# --- Ajuste de permisos + baja de privilegios ------------------------------
# Si arrancamos como root (caso normal en Docker/Portainer), ajustamos el
# propietario del volumen bind-montado /output (su dueño en el host puede ser
# root, 1000, etc.) y luego RE-EJECUTAMOS este mismo script como el usuario
# no-root `jaamsim`. Así la simulación corre sin privilegios y los bind mounts
# funcionan sin configuración manual en el host (zero-config en Portainer).
if [ "$(id -u)" = "0" ]; then
    mkdir -p /output
    # Solo /output necesita escritura; /models y /data van montados :ro.
    chown -R "${RUN_AS}:${RUN_AS}" /output 2>/dev/null \
        || printf '[WARN] No se pudo ajustar el propietario de /output (continuo)\n'
    exec setpriv --reuid "$RUN_AS" --regid "$RUN_AS" --init-groups "$0" "$@"
fi

# --- Banner ----------------------------------------------------------------
printf '%s\n' "$C_INFO"
printf '%s\n' "============================================================"
printf '%s\n' "   JaamSim headless runner  —  jaamsim-portainer-stack"
printf '%s\n' "   Etapa 1 / Plataforma logística inteligente open source"
printf '%s\n' "============================================================"
printf '%s\n' "$C_RESET"

# --- Validaciones ----------------------------------------------------------
# 1. JAR existe y no está vacío
log "Verificando JAR de JaamSim en ${JAR} ..."
[ -s "$JAR" ] || fail "No se encontró ${JAR} o está vacío. Reconstruye la imagen (docker compose build)."
log_ok "JAR encontrado ($(ls -lh "$JAR" | awk '{print $5}'))."

# 2. Java disponible
log "Verificando Java ..."
command -v java >/dev/null 2>&1 || fail "Java no está disponible en el contenedor."
java -version 2>&1 | sed 's/^/    /'
log_ok "Java disponible."

# 3. JAAMSIM_MODEL no vacía
log "Modelo configurado: '${MODEL}'"
[ -n "$MODEL" ] || fail "JAAMSIM_MODEL está vacía. Define la ruta al .cfg (ej: /models/model.cfg)."

# 4. El .cfg existe
if [ ! -f "$MODEL" ]; then
    log_err "No se encontró el archivo de modelo: ${MODEL}"
    log_warn "Contenido de /models/:"
    if [ -d /models ]; then
        ls -la /models | sed 's/^/    /'
    else
        log_warn "    El directorio /models no existe."
    fi
    fail "Coloca tu .cfg en ./models/ y ajusta JAAMSIM_MODEL si es necesario."
fi
log_ok "Modelo encontrado."

# 5. Permisos de escritura en /output
log "Verificando permisos de escritura en /output ..."
[ -w /output ] || fail "No hay permisos de escritura en /output. Revisa el volumen montado."
log_ok "/output es escribible."

# --- Preparar directorio de la corrida -------------------------------------
RUN_ID="run_$(date '+%Y%m%d_%H%M%S')"
RUN_DIR="/output/${RUN_ID}"
mkdir -p "$RUN_DIR"
RUN_LOG="${RUN_DIR}/jaamsim.log"
log "Directorio de la corrida: ${RUN_DIR}"

# Symlink latest -> última corrida. Usamos una ruta RELATIVA (solo el nombre
# del directorio) para que el enlace funcione tanto dentro del contenedor como
# al inspeccionarlo desde el host (donde la ruta absoluta /output no existe).
ln -sfn "$RUN_ID" /output/latest.tmp 2>/dev/null && mv -Tf /output/latest.tmp /output/latest 2>/dev/null \
    || ln -sfn "$RUN_ID" /output/latest 2>/dev/null \
    || log_warn "No se pudo crear el symlink /output/latest (continuo igual)."

# Copiamos el modelo a la carpeta del run para trazabilidad y para que
# JaamSim escriba sus salidas (.dat, .log internos) junto a él, no en /models (ro).
RUN_MODEL="${RUN_DIR}/$(basename "$MODEL")"
cp "$MODEL" "$RUN_MODEL"

# --- Construir y mostrar el comando ----------------------------------------
# -h : headless (sin GUI),  -b : batch (sale al terminar)
CMD_DISPLAY="java ${JVM_OPTS} -jar ${JAR} ${RUN_MODEL} -h -b ${EXTRA_ARGS}"

log "Comando a ejecutar:"
printf '    %s\n' "$CMD_DISPLAY"
log "Iniciando simulación (logs en ${RUN_LOG}) ..."

# --- Ejecutar --------------------------------------------------------------
# Capturamos el exit code de JaamSim (no el de 'tee') de forma POSIX:
# el lado izquierdo del pipe escribe su código en un archivo temporal.
EXIT_FILE="${RUN_DIR}/.exit_code"
set +e
{
    eval "java $JVM_OPTS -jar \"$JAR\" \"$RUN_MODEL\" -h -b $EXTRA_ARGS"
    echo $? > "$EXIT_FILE"
} 2>&1 | tee "$RUN_LOG"
set -e
EXIT_CODE="$(cat "$EXIT_FILE" 2>/dev/null || echo 1)"
rm -f "$EXIT_FILE"

# --- Resultado -------------------------------------------------------------
if [ "$EXIT_CODE" -eq 0 ]; then
    log_ok "Simulación finalizada correctamente (exit 0)."
    log_ok "Resultados en: ${RUN_DIR}"
    log_ok "Acceso rápido a la última corrida: /output/latest"
    exit 0
else
    log_err "La simulación terminó con código de error: ${EXIT_CODE}"
    log_err "Revisa el log de la corrida: ${RUN_LOG}"
    fail "Fallo en la ejecución de JaamSim. Verifica el modelo y los argumentos (JAAMSIM_ARGS)."
fi
