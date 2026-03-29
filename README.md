# DockX

[English](README.md) | [Espanol](README.es.md)

DockX is a rework of the elementary OS Dock (Pantheon), built as a fork and extended with a new widlet system.

It keeps the core dock behavior (launchers, running apps, workspace integration, MPRIS media controls) and adds configurable dock-native mini components.

## What Is a Widlet?

A **widlet** is a combination of **widget + docklet**.

A widlet lives inside the dock, adapts to dock icon size, and can provide:

- compact or card-like UI inside the dock
- hover/click popovers for details
- per-widlet settings windows
- enable/disable toggle from the **New Widlet** window
- up/down ordering inside the widlet area

## Widlets Included

| Widlet | Purpose | Interactions | Settings |
|---|---|---|---|
| Now Playing | Current media track, controls, seek | Click/hover controls, context menu | Yes |
| Weather | Current conditions + forecast | Click opens forecast, optional minimal mode | Yes |
| Stocks | Rotating list of stock symbols | Click opens details, auto-rotate symbols | Yes |
| Clipboard | Clipboard status + recent/pinned items | Click opens clipboard history/pinned panel | Yes |
| CPU | CPU usage meter | Click opens CPU details | Yes (alerts) |
| RAM | RAM usage meter | Click opens RAM details | Yes (alerts) |
| CPU Temp | CPU temperature meter | Click opens temperature details | Yes (alerts) |
| GPU | GPU usage meter | Click opens GPU details | Yes (alerts) |
| Hard Disk | Disk activity meter | Click opens disk activity details | Yes (alerts) |
| Trash | Empty/full trash state | Left click opens Trash, right click empty | No |
| Workspace Widlet | Workspace section + New Widlet entrypoint | Left click opens widlet manager, right click create workspace | Basic |

## Screenshots

### New Widlet Window

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

### PC Widlets (CPU/RAM/Temp/GPU/Disk)

![PC widlets](docs/images/pc%20widlets/all.png)
![PC widlets popup](docs/images/pc%20widlets/popup.png)

### Trash Widlet

![Trash widlet empty](docs/images/trash%20widlet/empty.png)
![Trash widlet full](docs/images/trash%20widlet/full.png)

### Now Playing (Current Implementation)

![Now Playing normal mode](docs/images/normal-mode.png)
![Now Playing minimal mode](docs/images/minimal-mode.png)
![Now Playing seek bar](docs/images/seek-bar.png)
![Now Playing animation](docs/images/animation.gif)

## APIs And External Resources

DockX currently uses these network APIs/resources:

- Open-Meteo Forecast API (weather current + daily forecast)
  - `https://api.open-meteo.com/v1/forecast`
- Open-Meteo Geocoding API (city -> lat/lon)
  - `https://geocoding-api.open-meteo.com/v1/search`
- Yahoo Finance chart endpoints (quotes/trend data)
  - `https://query2.finance.yahoo.com/v8/finance/chart/...`
  - `https://query1.finance.yahoo.com/v8/finance/chart/...`
- TradingView scanner/logos (stock logo resolution)
  - `https://scanner.tradingview.com/america/scan`
  - `https://s3-symbol-logo.tradingview.com/...`
- Stock logo fallback providers
  - `https://financialmodelingprep.com/image-stock/...`
  - `https://eodhd.com/img/logos/US/...`

UI/icon resources:

- Weather icon pack source used for weather widlet assets:
  - `https://www.figma.com/community/file/1469636700953030456`
- Lucide icon set (for consistent New Widlet UI actions/icons):
  - `https://lucide.dev/`

System integrations:

- MPRIS (DBus) for Now Playing media state and controls
- GLib notifications for threshold-based widlet alerts
- Local Linux system files (`/proc`, `/sys`) and optional `nvidia-smi` for system metrics

## Requirements

Build dependencies (elementary OS / Ubuntu):

- `meson`
- `ninja-build`
- `valac`
- `libgtk-4-dev`
- `libadwaita-1-dev`
- `libgranite-7-dev`
- `libsoup-3.0-dev`
- `libx11-dev`
- `libwayland-dev`

Install:

```bash
sudo apt update
sudo apt install -y \
  meson ninja-build valac \
  libgtk-4-dev libadwaita-1-dev libgranite-7-dev \
  libsoup-3.0-dev libx11-dev libwayland-dev
```

Runtime notes:

- Internet connection is required for Weather and Stocks widlets.
- `nvidia-smi` is optional but improves GPU usage detection on NVIDIA systems.
- A MPRIS-compatible player is required for Now Playing.

## Build And Replace Your Current Dock (User-Local)

### 1. Clone

```bash
git clone https://github.com/Juandamian18/dockx.git
cd dockx
```

### 2. Configure Meson prefix to your local user path

```bash
meson setup build --prefix="$HOME/.local"
```

If `build` already exists:

```bash
meson setup build --reconfigure --prefix="$HOME/.local"
```

### 3. Compile

```bash
meson compile -C build
```

### 4. Install

```bash
meson install -C build
```

### 5. Restart dock process

```bash
pkill -f '^io.elementary.dock$' || true
```

### 6. Verify binary path

```bash
which io.elementary.dock
```

Expected path:

```text
/home/your-user/.local/bin/io.elementary.dock
```

## Daily Development Loop

After each code change:

```bash
meson compile -C build
meson install -C build
pkill -f '^io.elementary.dock$' || true
```

## First Run: Managing Widlets

- Click the `+` dock item to open **New Widlet**.
- Toggle widlets on/off with each row switch.
- Reorder with up/down arrows.
- Open widlet-specific settings using the settings icon (only shown when that widlet has settings).
- Right click the `+` item and choose **Create Workspace**.

## Optional Helper Script

To prefetch TradingView stock logos into cache:

```bash
./scripts/prefetch_tradingview_stock_logos.sh
```

## Relevant Project Structure

- `src/ItemManager.vala`: widlet orchestration, ordering, layout, enable/disable state
- `src/WorkspaceSystem/DynamicWorkspaceItem.vala`: New Widlet window + widlet settings windows
- `src/WeatherSystem/WeatherWidletItem.vala`: weather card/minimal mode + forecast popover
- `src/SystemWidlets/StockWidletItem.vala`: stocks data, rotation, logos, details
- `src/SystemWidlets/ClipboardWidletItem.vala`: clipboard history + pinned text behavior
- `src/SystemWidlets/*WidletItem.vala`: CPU/RAM/Temp/GPU/Disk/Trash widlets
- `src/MediaSystem/NowPlayingItem.vala`: now playing card/minimal mode controls
- `data/Application.css`: all widlet visual styling
- `data/dock.gschema.xml`: widlet settings keys and defaults
- `data/weather-icons/`: weather icon assets
- `data/widlet-icons/`: custom widlet icon assets

## Base Project

DockX is based on the elementary OS Dock project:

- `https://github.com/elementary/dock`

## License

Distributed under **GPL-3.0**. See [LICENSE](LICENSE).
