# jaamsim-portainer-stack

Stack Docker para ejecutar **JaamSim 2026-04** en modo *headless / batch* sobre
un servidor Linux propio (mini PC con Docker + Portainer). Pensado para
desplegarse directamente desde **Portainer → Stacks → Repository**.

> **Etapa 1** de una plataforma logística inteligente *open source* que busca
> reemplazar AnyLogic. Ver [Próximos pasos](#9-próximos-pasos).

---

## 1. ¿Qué hace este stack?

- Descarga automáticamente el JAR oficial de JaamSim durante el `docker build`
  (el JAR **no** se incluye en el repositorio).
- Ejecuta un modelo `.cfg` en **modo headless** (`-h`, sin GUI ni OpenGL) y
  **batch** (`-b`, sale al terminar).
- Guarda los resultados organizados por *timestamp* en `output/run_YYYYMMDD_HHMMSS/`
  y mantiene un enlace `output/latest/` a la corrida más reciente.
- Corre como **usuario no-root** dentro del contenedor, con `tini` como PID 1,
  *healthcheck*, límites de recursos y logging rotado.
- En caso de error **no** termina silenciosamente: muestra el problema y queda
  vivo (`sleep infinity`) para que puedas leer los logs desde Portainer.

---

## 2. Estructura del repositorio

```
jaamsim-portainer-stack/
├── docker-compose.yml      # Stack principal: GUI (8090) + runner headless
├── docker-compose.gui.yml  # Stack alternativo: SOLO la GUI por navegador
├── Dockerfile              # Imagen headless: temurin:21-jre + JaamSim + tini
├── .env.example            # Plantilla de variables de entorno
├── .gitignore
├── README.md
├── models/                 # Tus modelos .cfg  -> /models (ro)
│   └── .gitkeep
├── output/                 # Resultados de cada corrida -> /output (rw)
│   └── .gitkeep
├── data/                   # CSV / parámetros auxiliares -> /data (ro)
│   └── .gitkeep
├── docker/
│   └── entrypoint.sh       # Validaciones + ejecución + organización de output
└── gui/
    ├── Dockerfile          # Imagen GUI: + Xvfb + fluxbox + x11vnc + noVNC
    └── start.sh            # Arranque de X virtual, VNC, noVNC y JaamSim
```

> El **`docker-compose.yml`** principal levanta **dos servicios** en un solo stack:
> - **`jaamsim-gui`** — la interfaz gráfica nativa de JaamSim por navegador (noVNC), en el puerto **8090**. Ver [sección GUI](#gui-de-jaamsim-en-el-navegador-novnc).
> - **`jaamsim-runner`** — ejecución headless/batch de modelos `.cfg`.
>
> Si querés **solo la GUI** (sin el runner headless), existe también `docker-compose.gui.yml`.

---

## 3. Despliegue desde Portainer (paso a paso)

1. En Portainer ve a **Stacks → Add stack**.
2. Selecciona el método **Repository**.
3. Completa:
   | Campo | Valor |
   |-------|-------|
   | **Name** | `jaamsim` (o el que prefieras) |
   | **Repository URL** | la URL de este repositorio Git |
   | **Repository reference** | `refs/heads/main` |
   | **Compose path** | `docker-compose.yml` |
4. (Opcional) En **Environment variables** define `JAAMSIM_MODEL`,
   `JAAMSIM_ARGS`, `JAVA_OPTS` (ver [sección 5](#5-configurar-variables-de-entorno)).
   Si no defines nada, se usan los valores por defecto.
5. Pulsa **Deploy the stack**.

Portainer hará el `build` de las imágenes (descargando el JAR) y arrancará los
servicios **`jaamsim-gui`** (GUI por navegador en el puerto **8090**) y
**`jaamsim-runner`** (headless). La primera vez tarda un poco más por la descarga
del JAR y de las imágenes base.

> Una vez desplegado, abrí la GUI en **`http://<IP-del-host>:8090/`**. El
> `jaamsim-runner` solo procesa un modelo si existe `JAAMSIM_MODEL`; si no, queda
> a la espera (no afecta a la GUI).

> **Nota:** este stack hace `build` desde el repositorio, por lo que el host de
> Docker debe tener acceso a Internet para descargar la imagen base y el JAR.

---

## 4. Cómo cargar un modelo `.cfg`

El contenedor lee el modelo desde `/models` (montado en solo lectura desde
`./models` del repositorio/host). Tienes tres opciones:

1. **Vía repositorio (recomendado para versionar modelos):**
   coloca tu archivo en `models/` (ej. `models/almacen.cfg`), haz commit y
   push. Portainer lo tomará al re-desplegar. Ajusta `JAAMSIM_MODEL=/models/almacen.cfg`.

2. **Vía SSH / copia directa en el host:**
   copia el `.cfg` a la carpeta `models/` del stack en el host
   (ej. `/path/al/stack/models/`) y reinicia el contenedor desde Portainer.
   Útil para modelos que no quieres versionar.

3. **Vía API REST (futuro — Etapa 2):**
   la API de FastAPI permitirá subir modelos y disparar corridas
   programáticamente, escribiendo en el mismo volumen `models/`.

---

## 5. Configurar variables de entorno

Copia la plantilla y edítala (o define las variables en Portainer):

```bash
cp .env.example .env
```

| Variable | Default | Descripción | Ejemplos |
|----------|---------|-------------|----------|
| `JAAMSIM_MODEL` | `/models/model.cfg` | Ruta al `.cfg` dentro del contenedor | `/models/almacen.cfg` |
| `JAAMSIM_ARGS` | *(vacío)* | Flags extra de JaamSim (además de `-h -b`) | `-q` |
| `JAVA_OPTS` | `-Xms256m -Xmx1g` | Opciones de la JVM | `-Xms512m -Xmx2g` |

Los flags `-h` (headless) y `-b` (batch) **siempre** se añaden automáticamente;
no necesitas incluirlos en `JAAMSIM_ARGS`.

> **Réplicas:** JaamSim **no** tiene un flag de CLI para el número de réplicas
> (no existe `-r N`). Se define **dentro del modelo** `.cfg`:
> ```
> Simulation NumberOfReplications { 10 }
> ```
> Flags de CLI realmente soportados por JaamSim (verificados sobre el JAR
> 2026-04): `-h`/`-headless`, `-b`/`-batch`, `-q`/`-quiet`,
> `-sg`/`-safe_graphics`, `-og`/`-optional_graphics`, `-script`.

---

## GUI de JaamSim en el navegador (noVNC)

Además del modo headless, podés usar la **interfaz gráfica nativa de JaamSim**
(canvas de modelado, editor de entidades, vista 3D) directamente desde el
navegador, sin instalar nada en tu PC. El contenedor corre la GUI sobre un X
virtual (`Xvfb`) y la expone por web con `x11vnc` + `noVNC`.

### Desplegar
La GUI **ya viene incluida en el `docker-compose.yml` principal** (servicio
`jaamsim-gui`), así que con el despliegue de la [sección 3](#3-despliegue-desde-portainer-paso-a-paso)
ya la tenés. Si preferís un stack **solo-GUI**, usá **Compose path** =
`docker-compose.gui.yml`. En cualquier caso, abrí en el navegador:

```
http://<IP-del-host>:8090/
```

(El `/` redirige automáticamente a `vnc.html` y conecta solo. Si el 8090 también
está ocupado, cambialo con la variable `NOVNC_PORT`.)

Localmente:
```bash
docker compose -f docker-compose.gui.yml up --build
# luego abrí http://localhost:8090/
```

### Variables (GUI)
| Variable | Default | Descripción |
|----------|---------|-------------|
| `NOVNC_PORT` | `8090` | Puerto web (noVNC) publicado en el host |
| `VNC_PASSWORD` | *(vacío)* | Contraseña VNC. **Definila** para proteger el acceso |
| `SCREEN_WIDTH` / `SCREEN_HEIGHT` | `1440` / `900` | Resolución del escritorio virtual |
| `JAAMSIM_MODEL` | *(vacío)* | Modelo `.cfg` a abrir al iniciar (ej. `/models/almacen.cfg`) |
| `JAVA_OPTS` | `-Xms256m -Xmx1536m` | Opciones de la JVM |

Los modelos que crees/edites en la GUI se guardan en `./models` (montado r/w) y
los resultados en `./output`, de modo que podés correrlos luego en modo headless.

> **Seguridad:** sin `VNC_PASSWORD` cualquiera con acceso de red al puerto
> publicado puede usar la GUI. Definí una contraseña y/o poné el servicio detrás de un
> reverse proxy con TLS/autenticación. noVNC viaja sin cifrar salvo que uses
> HTTPS por delante.

> **Rendimiento:** la vista 3D usa OpenGL por software (Mesa llvmpipe); funciona
> sin GPU pero el render 3D puede ir lento en modelos grandes. El modelado 2D y
> la edición van fluidos.

---

## 6. Ver logs

- **Portainer UI:** Stacks → `jaamsim` → contenedor `jaamsim-runner` → **Logs**.
  Verás el banner, las validaciones y la salida de la simulación en tiempo real.
- **Terminal (host):**
  ```bash
  docker logs -f jaamsim-runner
  ```
- **Archivos en disco:** cada corrida guarda su log en
  `output/run_YYYYMMDD_HHMMSS/jaamsim.log` (y `output/latest/jaamsim.log`).

El logging de Docker está limitado a `max-size: 10m` y `max-file: 5` (rotación).

---

## 7. Revisar resultados

Estructura generada en `output/`:

```
output/
├── run_20250630_004200/
│   ├── jaamsim.log         # salida completa de la corrida
│   ├── model.cfg           # copia del modelo ejecutado (trazabilidad)
│   └── ...                 # archivos de salida que genere el modelo (.dat, etc.)
├── run_20250630_010500/
│   └── ...
└── latest -> run_20250630_010500/   # symlink a la corrida más reciente
```

Para acceder a la última corrida desde el host:

```bash
ls -l output/latest/
cat output/latest/jaamsim.log
```

Las salidas propias de JaamSim (reportes, `.dat`, etc.) quedan junto a la copia
del modelo dentro de la carpeta del run, listas para ser consumidas por las
etapas siguientes (API, base de datos, dashboards).

---

## 8. Limitaciones actuales

Siendo honestos sobre el alcance de la Etapa 1:

- **No hay interfaz web.** La ejecución es por línea de comandos / Portainer.
- **Un modelo por contenedor a la vez.** No hay cola ni orquestación de corridas
  concurrentes (llegará con la API + Celery en la Etapa 2).
- **El disparo es manual** (deploy / restart del stack); no hay scheduler aún.
- **Sin persistencia de metadatos.** Los resultados viven solo como archivos en
  `output/` (PostgreSQL llega en la Etapa 4).
- Requiere acceso a Internet en el host para el `build` (descarga del JAR).

---

## 9. Próximos pasos

Roadmap de la plataforma logística inteligente *open source*:

| Etapa | Componente | Estado |
|-------|-----------|--------|
| **1** | **JaamSim headless (este stack)** | ✅ actual |
| 2 | API REST (FastAPI + Celery) | ⏳ |
| 3 | Dashboard (Grafana + Power BI) | ⏳ |
| 4 | PostgreSQL (metadata de runs) | ⏳ |
| 5 | Django + n8n + Power BI | ⏳ |
| 6 | SimPy + Mesa (co-simulación multiparadigma) | ⏳ |
| 7 | YOLO (gemelo digital con visión por computadora) | ⏳ |

El diseño deja `output/` como contrato de integración: las etapas siguientes
leerán las carpetas `run_*` (y `latest`) para registrar metadatos, exponer
resultados vía API y alimentar dashboards.

---

## 10. Construcción local para testing

```bash
# 1. Clonar y entrar al repo
git clone <URL-del-repo> jaamsim-portainer-stack
cd jaamsim-portainer-stack

# 2. Preparar variables y modelo
cp .env.example .env
cp algun_modelo.cfg models/model.cfg      # tu modelo .cfg

# 3. Construir la imagen (descarga el JAR)
docker compose build

# 4. Ejecutar
docker compose up
```

Para correr varias réplicas, define dentro del `.cfg`
`Simulation NumberOfReplications { 10 }` y ejecuta normalmente
(`docker compose up`). Para reducir la salida por consola:

```bash
JAAMSIM_ARGS="-q" docker compose up
```

Detener y limpiar:

```bash
docker compose down
```

---

## 11. Tabla de tecnologías

| Tecnología | Uso | Versión |
|-----------|-----|---------|
| [JaamSim](https://jaamsim.com/) | Motor de simulación de eventos discretos | 2026-04 |
| [Eclipse Temurin (Adoptium)](https://adoptium.net/) | Runtime de Java (OpenJDK) | `21-jre` |
| [Docker](https://www.docker.com/) | Contenerización | Engine 20+ |
| [Docker Compose](https://docs.docker.com/compose/) | Definición del stack | v2 (`docker compose`) |
| [Portainer](https://www.portainer.io/) | Despliegue/gestión (CE y EE) | Stacks → Repository |
| [tini](https://github.com/krallin/tini) | Init / PID 1 (manejo de señales) | paquete distro |
| [noVNC](https://novnc.com/) + [websockify](https://github.com/novnc/websockify) | Cliente VNC web (solo modo GUI) | paquete distro |
| [x11vnc](https://github.com/LibVNC/x11vnc) + [Xvfb](https://www.x.org/) + [fluxbox](http://fluxbox.org/) | X virtual + servidor VNC + WM (solo modo GUI) | paquete distro |

Arquitectura objetivo: **linux/amd64**. Compatible con Docker Standalone
(no requiere Swarm).

---

## 12. Licencia

El código de este stack se publica bajo licencia **MIT** (ver `LICENSE` si se
incluye). **JaamSim** se distribuye bajo su propia licencia
(Apache License 2.0); su JAR se descarga desde el repositorio oficial y no se
redistribuye en este proyecto.
