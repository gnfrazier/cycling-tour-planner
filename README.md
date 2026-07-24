# Cycle Tour Planner

A personal route planner for cyclists who care about *why* a route goes where it goes — flattest, hilliest, quietest, straightest, or most interesting — rather than just logging a ride after the fact. It also handles multi-day trip logistics: lodging, water stops, weather, and daily mileage/elevation budgets, not just a single loop around the block.

This is also very much a learning project. The stack is fixed on purpose as a project goal in itself:

- **OSMnx** (Python) for the routing core — custom multi-factor edge weighting over OpenStreetMap data
- **FastAPI** as the middle layer — typed request/response models, auto-generated OpenAPI docs
- **Flutter/Dart**, one codebase across Desktop, Android, iOS, and Web

The app is **local-first, not local-only**: Desktop and Mobile run the routing core on-device inside a local sidecar process, so every P0 capability works offline. Web is a deliberate exception — it always computes server-side, since there's no browser-side path to run OSMnx. (The current milestone runs the backend as a plain dev process rather than the packaged sidecar binary — see the scope note below.)

## Where things stand

**M1–M4 are built**: the OSMnx routing core (all five MVP themes + GEDTM30 elevation), the FastAPI wrap, and a working Flutter Desktop client that generates, renders, and exports routes. See [Running the desktop app](#running-the-desktop-app) below to try it. Everything past M4 (accounts, sync, Web, Mobile, plugins) is still design-only.

| Doc | What it covers |
|-|-|
| [`Cycle_Tour_Planner_PRD.md`](Cycle_Tour_Planner_PRD.md) | Product requirements — problem, personas, functional requirements, milestones. Start here |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | System design — component map, the local-sidecar decision, data model, plugin architecture |
| [`ROADMAP.md`](ROADMAP.md) | Build order, sequenced by dependency (solo project — no calendar dates) |
| [`UX.md`](UX.md) | Outdoor-use UX principles (glare, gloves, offline-as-default, low cognitive load) |
| [`Brand Guide.md`](Brand%20Guide.md) | Visual identity and color system |

Treat the PRD and ARCHITECTURE docs as the current best guess, not a fixed spec — they'll keep evolving as building continues and reality pushes back on the plan.

**Scope notes for this milestone** (deliberate simplifications, tracked in `ROADMAP.md` Leg 2, not oversights):
- No frozen-binary sidecar packaging yet — `ctp-service` runs as a normal `uvicorn` dev process, and the Flutter client points at a fixed local port instead of spawning/discovering one.
- No self-hosted tile-generation pipeline yet — `/tiles/{z}/{x}/{y}` proxies a public OSM tile server for local dev use only. The client still only ever talks to `ctp-service` for tiles, never a third party directly.
- Only **North Carolina** has real data wired up (the region FR38's picker defaults to); Wisconsin and Southern California show as "coming soon" in the app.

### Current wireframe

A route-comparison view from the in-progress design: proposing an alternate segment (climb + gravel) against the current route, with a live delta on distance, climbing, surface, and estimated time before committing.

![Route comparison wireframe — proposing a climbing/gravel alternate for a segment of the Blue Ridge Tour, with distance, climbing, surface, and time deltas against the current route](assets/media/route-compare.jpg)

## Repo layout

```
backend/
  ctp_core/          Pure routing library (no FastAPI import, enforced by test) —
                      OSMnx graph build/cache, GEDTM30 elevation, the five theme
                      weight profiles, route solving, GPX/TCX/FIT export
  ctp_service/       FastAPI wrapper — /routes/generate, /routes/{id}/export,
                      /geocode, /tiles/{z}/{x}/{y}, /health, /admin/clear-cache
  tests/             pytest suite (38 tests)
  sidecar_entrypoint.py  Minimal PyInstaller entrypoint for the frozen ctp-service binary
client/
  lib/               Flutter Desktop app — domain/data/state/presentation layers
  integration_test/  End-to-end test driving the real app against the real backend
  linux/, windows/   Desktop platform targets built by CI
assets/              Design assets (wireframes, rasters)
.github/workflows/   CI — see Build pipeline below
```

## Running the desktop app

Both Linux and Windows are supported — the client, and the CI in
[Build pipeline](#build-pipeline), build for both. Requires:
- Python 3.12+ and [uv](https://docs.astral.sh/uv/):
  - Linux/macOS: `curl -LsSf https://astral.sh/uv/install.sh | sh`
  - Windows (PowerShell): `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
  — then open a **new** terminal so the PATH change takes effect.
- Flutter 3.x, with the platform target enabled:
  - Linux: `flutter config --enable-linux-desktop`
  - Windows: `flutter config --enable-windows-desktop`, plus the "Desktop
    development with C++" workload from Visual Studio Build Tools
    (Flutter's Windows target needs it to compile the runner)
  - Windows also needs **Developer Mode** enabled (`start ms-settings:developers`,
    toggle it on) — Flutter's plugin system symlinks on Windows, and creating
    symlinks without it requires admin privileges

### Troubleshooting (Windows): Smart App Control blocks `uv.exe`

If `uv run ...` fails with *"An Application Control policy has blocked this file"*, that's Windows 11's **Smart App Control** (SAC) — it only allows apps it considers signed and reputable. This isn't a "hasn't built up reputation yet" problem: `uv`'s Windows binaries are not currently Authenticode-signed upstream at all (see [astral-sh/uv#18967](https://github.com/astral-sh/uv/issues/18967) and [astral-sh/uv#10336](https://github.com/astral-sh/uv/issues/10336)), so **switching to winget often does not clear this particular block** — winget improves where the file came from, not whether the binary itself is signed, which is what SAC actually checks. Consumer Windows also has no per-app "allow this one" exception for SAC (unlike SmartScreen) — it's an on/off policy for unsigned apps. Try, in order:

1. Confirm it's actually SAC and not something else: Event Viewer → Applications and Services Logs → Microsoft → Windows → CodeIntegrity → Operational will show the specific blocked file and policy.
2. Reinstall via winget anyway (`winget install astral-sh.uv`) — it sometimes still helps for other blocked tools, just not reliably for uv given the signing gap above.
3. **Recommended**: run the backend inside WSL2 instead of native Windows, and leave everything else unchanged. Install WSL2 (Ubuntu) if you don't have it, then follow the Linux/macOS backend steps above verbatim from inside the WSL shell. Keep running the Flutter client natively on Windows (`flutter run -d windows`) pointed at the default `http://127.0.0.1:8000` — WSL2 forwards localhost to Windows automatically, so the client needs no changes. This sidesteps needing a native `uv.exe` at all, with Smart App Control left fully on.
4. Only as a last resort, turn off Smart App Control: Settings → Privacy & security → Windows Security → App & browser control → Smart App Control → Off. **This is one-way** — once off, it only comes back via a clean Windows reinstall, not a re-toggle — so don't reach for it first.

This section is about the third-party `uv` tool's own signing gap. Whether *this project's* frozen `ctp-service` sidecar and installer get signed is a separate, not-yet-decided question — see the open questions in `ARCHITECTURE.md` §13 and the Leg 2 gate in `ROADMAP.md`. The same SAC policy can block that unsigned frozen binary too once it exists; the fix order above still applies, minus the WSL escape hatch (the sidecar has to run on the target OS).

### 1. Start the backend

**Linux/macOS (bash):**

```sh
cd backend
uv sync

# One-time: extract the local GEDTM30 elevation raster (already downloaded to
# assets/rasters/) into the backend's dev cache
mkdir -p .cache/elevation
tar -xzf ../assets/rasters/rasters_GEDTM30.tar.gz -O output_be.tif > .cache/elevation/nc_gedtm30.tif

uv run uvicorn main:app --host 127.0.0.1 --port 8000
```

**Windows (PowerShell):**

```powershell
cd backend
uv sync

# One-time: extract the local GEDTM30 elevation raster (already downloaded to
# assets/rasters/) into the backend's dev cache. Windows 10/11 ships tar.exe.
# Extract to a file rather than piping stdout through `>` — PowerShell's `>`
# is text-mode redirection and will corrupt binary output.
mkdir .cache\elevation
tar -xzf ../assets/rasters/rasters_GEDTM30.tar.gz -C .cache/elevation output_be.tif
Move-Item .cache\elevation\output_be.tif .cache\elevation\nc_gedtm30.tif -Force

uv run uvicorn main:app --host 127.0.0.1 --port 8000
```

Wait for it to report ready before using the client — first startup fetches and caches the Marion, NC street graph from OpenStreetMap, which takes a few seconds:

```sh
curl http://127.0.0.1:8000/health
# {"status":"ok","ready":true,"osmnx_version":"2.1.0","rasterio_version":"1.5.0"}
```

### 2. Run the client

In a second terminal:

```sh
cd client
flutter pub get
flutter run -d linux     # or: flutter run -d windows
```

The client talks to `http://127.0.0.1:8000` by default (override with `--dart-define=CTP_API_BASE_URL=http://...`). In the app: search "Marion, NC" as a start point (or tap the map), pick a shape and theme, and generate a route.

Note: on both platforms this is still the hand-started dev backend, not the
frozen sidecar binary CI builds — see the scope note in
[Build pipeline](#build-pipeline).

### Running the tests

```sh
# Backend — 38 tests
cd backend && uv run pytest

# Client — unit/widget tests
cd client && flutter test
cd client && flutter analyze

# Client — end-to-end against the real backend (start the backend first, see above)
cd client && flutter test integration_test/app_test.dart -d linux    # or: -d windows
```

## Build pipeline

`.github/workflows/desktop-build.yml` runs on every push/PR to `main` (and
`workflow_dispatch`), on a `[ubuntu-latest, windows-latest]` matrix. It's
**CI validation only** — it proves both desktop targets lint, test, freeze,
and build cleanly; it doesn't publish artifacts or releases. Per run:

1. Backend: `uv sync`, `uv run pytest` (38 tests)
2. Backend: freezes `ctp-service` into a standalone binary with PyInstaller
   (`--onedir`), then smoke-tests the frozen binary by launching it and
   polling `/health`
3. Client: `flutter analyze`, `flutter test`, then `flutter build linux` /
   `flutter build windows`

To reproduce the freeze step locally:

```sh
cd backend
uv sync --all-groups
uv run pyinstaller --onedir --clean --name ctp-service \
  --copy-metadata osmnx --copy-metadata rasterio --collect-submodules rasterio \
  sidecar_entrypoint.py
./dist/ctp-service/ctp-service --port 8123   # then curl http://127.0.0.1:8123/health
```

**Scope note**: `sidecar_entrypoint.py` is a minimal PyInstaller entrypoint —
enough to prove the backend freezes into a working server. It is *not* the
full sidecar lifecycle from `ARCHITECTURE.md` §6.3 (PID file, orphan sweep,
`--mode`/`--cache-dir` wiring, readiness polling from the client). The
Flutter client still talks to a hand-started dev backend (see above); it
does not yet spawn or discover the frozen binary. That client-side
spawn/discovery integration, plus assembling client + sidecar into one
installer, is future work — this pipeline only makes both halves buildable.

## GeoTIFF source

### Citation
European Space Agency (2024). Copernicus Global Digital Elevation Model. Distributed by OpenTopography. https://doi.org/10.5069/G9028PQB. Accessed 2026-07-12

### License
© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.
