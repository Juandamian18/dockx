# DockX

[English](README.md) | [Espanol](README.es.md)

DockX es un rework del Dock de elementary OS (Pantheon), basado en un fork y extendido con un nuevo sistema de widlets.

Mantiene el comportamiento principal del dock (launchers, apps en ejecucion, integracion de workspaces, controles MPRIS) y agrega componentes configurables nativos del dock.

## Que Es Un Widlet

Un **widlet** es una combinacion de **widget + docklet**.

Un widlet vive dentro del dock, se adapta al tamano de icono del dock y puede ofrecer:

- UI compacta o tipo tarjeta dentro del dock
- popovers de detalle al hacer hover/click
- ventanas de configuracion por widlet
- toggle para habilitar/deshabilitar desde **New Widlet**
- ordenamiento con flechas arriba/abajo

## Widlets Incluidos

| Widlet | Proposito | Interacciones | Configuracion |
|---|---|---|---|
| Now Playing | Cancion actual, controles, seek | Controles por click/hover, menu contextual | Si |
| Weather | Clima actual + pronostico | Click abre pronostico, modo minimal opcional | Si |
| Stocks | Rotacion de simbolos bursatiles | Click abre detalles, rotacion automatica | Si |
| Clipboard | Estado de portapapeles + historial/pines | Click abre historial y textos fijados | Si |
| CPU | Medidor de uso de CPU | Click abre detalles de CPU | Si (alertas) |
| RAM | Medidor de uso de RAM | Click abre detalles de RAM | Si (alertas) |
| CPU Temp | Medidor de temperatura CPU | Click abre detalles de temperatura | Si (alertas) |
| GPU | Medidor de uso de GPU | Click abre detalles de GPU | Si (alertas) |
| Hard Disk | Medidor de actividad de disco | Click abre detalles de disco | Si (alertas) |
| Trash | Estado vacio/lleno de papelera | Click izquierdo abre papelera, click derecho vaciar | No |
| Workspace Widlet | Seccion de workspaces + entrada a New Widlet | Click izquierdo abre gestor de widlets, click derecho crear workspace | Basica |

## Capturas

### Ventana New Widlet

![New Widlet window](docs/images/new%20widlet.png)

### Weather Widlet

![Weather widlet normal](docs/images/weather%20widlet/normal.png)
![Weather widlet minimal](docs/images/weather%20widlet/minimal.png)
![Weather widlet forecast popup](docs/images/weather%20widlet/popup.png)

### Stocks Widlet

![Stocks widlet](docs/images/stocks%20widlet/stock.png)

### Clipboard Widlet

![Clipboard widlet](docs/images/clipboard%20widlet/clipboard.png)
![Clipboard widlet popup](docs/images/clipboard%20widlet/popup.png)

### Widlets de PC (CPU/RAM/Temp/GPU/Disk)

![PC widlets](docs/images/pc%20widlets/all.png)
![PC widlets popup](docs/images/pc%20widlets/popup.png)

### Trash Widlet

![Trash widlet empty](docs/images/trash%20widlet/empty.png)
![Trash widlet full](docs/images/trash%20widlet/full.png)

### Now Playing (Implementacion Actual)

![Now Playing normal mode](docs/images/normal-mode.png)
![Now Playing minimal mode](docs/images/minimal-mode.png)
![Now Playing seek bar](docs/images/seek-bar.png)
![Now Playing animation](docs/images/animation.gif)

## APIs Y Recursos Externos

DockX usa actualmente estas APIs/recursos de red:

- Open-Meteo Forecast API (clima actual + pronostico diario)
  - `https://api.open-meteo.com/v1/forecast`
- Open-Meteo Geocoding API (ciudad -> lat/lon)
  - `https://geocoding-api.open-meteo.com/v1/search`
- Endpoints de Yahoo Finance para cotizaciones/tendencia
  - `https://query2.finance.yahoo.com/v8/finance/chart/...`
  - `https://query1.finance.yahoo.com/v8/finance/chart/...`
- TradingView scanner/logos (resolucion de logos)
  - `https://scanner.tradingview.com/america/scan`
  - `https://s3-symbol-logo.tradingview.com/...`
- Fallbacks de logos bursatiles
  - `https://financialmodelingprep.com/image-stock/...`
  - `https://eodhd.com/img/logos/US/...`

Recursos de UI/iconos:

- Fuente de iconos de clima usada para el weather widlet:
  - `https://www.figma.com/community/file/1469636700953030456`
- Set de iconos Lucide (para consistencia visual en New Widlet):
  - `https://lucide.dev/`

Integraciones de sistema:

- MPRIS (DBus) para estado y controles de Now Playing
- Notificaciones GLib para alertas por umbral
- Archivos locales Linux (`/proc`, `/sys`) y `nvidia-smi` opcional para metricas de sistema

## Requisitos

Dependencias de build (elementary OS / Ubuntu):

- `meson`
- `ninja-build`
- `valac`
- `libgtk-4-dev`
- `libadwaita-1-dev`
- `libgranite-7-dev`
- `libsoup-3.0-dev`
- `libx11-dev`
- `libwayland-dev`

Instalacion:

```bash
sudo apt update
sudo apt install -y \
  meson ninja-build valac \
  libgtk-4-dev libadwaita-1-dev libgranite-7-dev \
  libsoup-3.0-dev libx11-dev libwayland-dev
```

Notas de runtime:

- Weather y Stocks requieren conexion a internet.
- `nvidia-smi` es opcional pero mejora deteccion de uso GPU en NVIDIA.
- Now Playing requiere un reproductor compatible con MPRIS.

## Compilar Y Reemplazar Tu Dock Actual (Instalacion Local)

### 1. Clonar

```bash
git clone https://github.com/Juandamian18/dockx.git
cd dockx
```

### 2. Configurar prefix local de Meson

```bash
meson setup build --prefix="$HOME/.local"
```

Si `build` ya existe:

```bash
meson setup build --reconfigure --prefix="$HOME/.local"
```

### 3. Compilar

```bash
meson compile -C build
```

### 4. Instalar

```bash
meson install -C build
```

### 5. Reiniciar proceso del dock

```bash
pkill -f '^io.elementary.dock$' || true
```

### 6. Verificar ruta del binario

```bash
which io.elementary.dock
```

Ruta esperada:

```text
/home/tu-usuario/.local/bin/io.elementary.dock
```

## Flujo Diario De Desarrollo

Despues de cada cambio:

```bash
meson compile -C build
meson install -C build
pkill -f '^io.elementary.dock$' || true
```

## Primer Uso: Gestion De Widlets

- Haz click en el item `+` del dock para abrir **New Widlet**.
- Activa/desactiva widlets con el switch de cada fila.
- Reordena con flechas arriba/abajo.
- Abre configuracion por widlet desde el icono de settings (solo aparece si ese widlet tiene settings).
- Haz click derecho en `+` y elige **Create Workspace**.

## Script Opcional

Para precargar logos de TradingView en cache:

```bash
./scripts/prefetch_tradingview_stock_logos.sh
```

## Estructura Relevante Del Proyecto

- `src/ItemManager.vala`: orquestacion de widlets, orden, layout, estado on/off
- `src/WorkspaceSystem/DynamicWorkspaceItem.vala`: ventana New Widlet + ventanas de configuracion
- `src/WeatherSystem/WeatherWidletItem.vala`: weather card/minimal + popover de pronostico
- `src/SystemWidlets/StockWidletItem.vala`: datos de stocks, rotacion, logos, detalles
- `src/SystemWidlets/ClipboardWidletItem.vala`: historial de portapapeles + textos fijados
- `src/SystemWidlets/*WidletItem.vala`: widlets CPU/RAM/Temp/GPU/Disk/Trash
- `src/MediaSystem/NowPlayingItem.vala`: tarjeta now playing + modo minimal
- `data/Application.css`: estilos visuales de widlets
- `data/dock.gschema.xml`: claves de configuracion y defaults
- `data/weather-icons/`: assets de iconos de clima
- `data/widlet-icons/`: assets de iconos custom de widlets

## Proyecto Base

DockX se basa en el proyecto original de Dock de elementary OS:

- `https://github.com/elementary/dock`

## Licencia

Distribuido bajo **GPL-3.0**. Ver [LICENSE](LICENSE).
