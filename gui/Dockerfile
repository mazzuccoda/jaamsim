# syntax=docker/dockerfile:1
#
# JaamSim GUI accesible desde el navegador (noVNC)
# Ejecuta la interfaz gráfica NATIVA de JaamSim dentro de un X virtual (Xvfb)
# y la expone por web mediante x11vnc + noVNC/websockify.
FROM eclipse-temurin:21-jre

# --- Argumentos de build ---------------------------------------------------
ARG JAAMSIM_VERSION=2026-04
ARG JAAMSIM_JAR_URL=https://github.com/jaamsim/jaamsim/releases/download/v${JAAMSIM_VERSION}/JaamSim${JAAMSIM_VERSION}.jar

LABEL org.opencontainers.image.title="jaamsim-gui" \
      org.opencontainers.image.description="GUI nativa de JaamSim ${JAAMSIM_VERSION} accesible por navegador (noVNC)" \
      org.opencontainers.image.source="https://github.com/jaamsim/jaamsim" \
      org.opencontainers.image.licenses="Apache-2.0"

# --- Dependencias del sistema ----------------------------------------------
# Xvfb        -> servidor X virtual (sin monitor físico)
# fluxbox     -> window manager ligero (mover/maximizar la ventana de JaamSim)
# x11vnc      -> sirve el display X por VNC
# novnc +     -> cliente VNC web (HTML5) y proxy WebSocket
#   websockify
# mesa/libgl  -> OpenGL por software (vista 3D de JaamSim sin GPU)
# libx*       -> librerías X requeridas por Swing/AWT/JOGL
# tini        -> init/PID 1
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        wget ca-certificates tini \
        xvfb fluxbox x11vnc x11-utils \
        novnc websockify \
        libgl1-mesa-dri libglu1-mesa libgl1 \
        libxext6 libxrender1 libxtst6 libxi6 libxrandr2 libxxf86vm1 \
        libxcursor1 libxfixes3 libxdamage1 libxcomposite1 \
        fonts-dejavu-core \
        net-tools procps \
    && rm -rf /var/lib/apt/lists/*

# --- Descarga del JAR ------------------------------------------------------
RUN echo "Descargando JaamSim ${JAAMSIM_VERSION} desde: ${JAAMSIM_JAR_URL}" \
    && wget --progress=dot:giga -O /opt/jaamsim.jar "${JAAMSIM_JAR_URL}" \
    && test -s /opt/jaamsim.jar \
    && echo "JAR descargado. Tamaño:" \
    && ls -lh /opt/jaamsim.jar

# --- Usuario no-root + directorios -----------------------------------------
RUN groupadd --system jaamsim \
    && useradd --system --gid jaamsim --create-home --home-dir /home/jaamsim jaamsim \
    && mkdir -p /models /output /data /home/jaamsim/.vnc /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix \
    && chown -R jaamsim:jaamsim /models /output /data /home/jaamsim /opt/jaamsim.jar

# --- Script de arranque ----------------------------------------------------
COPY gui/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Página raíz: redirige '/' a vnc.html con autoconexión (se crea como root en
# build, ya que /usr/share/novnc no es escribible por el usuario no-root).
RUN NOVNC_DIR=$(test -d /usr/share/novnc && echo /usr/share/novnc || echo /usr/share/webapps/novnc) \
    && printf '<!doctype html><meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=remote">' \
        > "${NOVNC_DIR}/index.html"

# Variables configurables
ENV DISPLAY=:0 \
    SCREEN_WIDTH=1440 \
    SCREEN_HEIGHT=900 \
    SCREEN_DEPTH=24 \
    NOVNC_PORT=8080 \
    VNC_PORT=5900 \
    VNC_PASSWORD="" \
    JAAMSIM_MODEL="" \
    JAVA_OPTS="-Xms256m -Xmx1536m" \
    LIBGL_ALWAYS_SOFTWARE=1

VOLUME ["/models", "/output", "/data"]
WORKDIR /home/jaamsim

EXPOSE 8080

# Healthcheck: el puerto de noVNC responde y el JAR existe
HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=40s \
    CMD test -s /opt/jaamsim.jar \
        && wget -q -O /dev/null "http://localhost:${NOVNC_PORT}/vnc.html" \
        || exit 1

USER jaamsim

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/start.sh"]
