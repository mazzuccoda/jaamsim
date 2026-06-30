# syntax=docker/dockerfile:1
#
# JaamSim headless runner
# Imagen base oficial de Adoptium (OpenJDK / Eclipse Temurin)
FROM eclipse-temurin:21-jre

# --- Argumentos de build ---------------------------------------------------
# Versión de JaamSim a descargar. Se puede sobreescribir con:
#   docker build --build-arg JAAMSIM_VERSION=2025-02 .
ARG JAAMSIM_VERSION=2025-02
# URL del JAR construida a partir de la versión. Permite override completo.
ARG JAAMSIM_JAR_URL=https://github.com/jaamsim/jaamsim/releases/download/v${JAAMSIM_VERSION}/JaamSim${JAAMSIM_VERSION}.jar

LABEL org.opencontainers.image.title="jaamsim-runner" \
      org.opencontainers.image.description="JaamSim ${JAAMSIM_VERSION} headless/batch runner para Portainer" \
      org.opencontainers.image.source="https://github.com/jaamsim/jaamsim" \
      org.opencontainers.image.licenses="Apache-2.0"

# --- Dependencias del sistema ----------------------------------------------
# wget          -> descarga del JAR
# ca-certificates -> validación TLS de GitHub
# tini          -> init/PID 1 para manejo correcto de señales
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        wget \
        ca-certificates \
        tini \
    && rm -rf /var/lib/apt/lists/*

# --- Descarga del JAR ------------------------------------------------------
# El JAR NO se versiona en el repo: se baja en build desde GitHub Releases.
# Verificamos que el archivo no esté vacío y mostramos su tamaño en el log.
RUN echo "Descargando JaamSim ${JAAMSIM_VERSION} desde: ${JAAMSIM_JAR_URL}" \
    && wget --progress=dot:giga -O /opt/jaamsim.jar "${JAAMSIM_JAR_URL}" \
    && test -s /opt/jaamsim.jar \
    && echo "JAR descargado correctamente. Tamaño:" \
    && ls -lh /opt/jaamsim.jar

# --- Usuario no-root -------------------------------------------------------
# Creamos el usuario/grupo jaamsim y los directorios de trabajo.
RUN groupadd --system jaamsim \
    && useradd --system --gid jaamsim --create-home --home-dir /home/jaamsim jaamsim \
    && mkdir -p /models /output /data \
    && chown -R jaamsim:jaamsim /models /output /data /opt/jaamsim.jar

# --- Entrypoint ------------------------------------------------------------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Variables de entorno por defecto
ENV JAAMSIM_MODEL=/models/model.cfg \
    JAAMSIM_ARGS="" \
    JAVA_OPTS="-Xms256m -Xmx1g"

# Volúmenes persistentes declarados explícitamente
VOLUME ["/models", "/output", "/data"]

WORKDIR /output

# Healthcheck: el JAR existe y Java responde
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=20s \
    CMD test -s /opt/jaamsim.jar && java -version >/dev/null 2>&1 || exit 1

USER jaamsim

# tini como PID 1 + nuestro entrypoint
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
