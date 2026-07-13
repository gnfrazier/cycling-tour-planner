# Cycle Tour Planner — Architecture Design

**Status**: Draft
**Author**: Greg Frazier
**Version**: 1.0 (2026-07-13)
**Companion doc**: `Cycle_Tour_Planner_PRD.md` v2.0 — the PRD is the source of truth for *what* and *why*; this document covers *how*.

---

## 1. Purpose & Reading Guide

This document describes the structure of the system: its components, their boundaries, how data moves between them, and the decisions that shape those boundaries.

**What this document is not**: it is not an implementation plan, a schedule, or a restatement of requirements. Where a decision was already made in the PRD, this document builds on it rather than re-arguing it.

**Reading order for a newcomer** (human or LLM):
1. §2 (Principles) — the rules everything else follows
2. §3 (Component Map) — what exists
3. §4 (The Portability Problem) — the single most consequential decision in the build
4. §5–§9 — each tier in detail
5. §12 (Decision Log) — why things are the way they are

---

## 2. Architectural Principles

These are load-bearing. A design that violates one of these is wrong, not merely different.

### P1 — The routing core is a pure library

The routing core (OSMnx, scoring, elevation, export) knows nothing about HTTP, users, accounts, sessions, or platforms. It takes inputs, returns routes, and touches only the filesystem for its own caches.

This is what makes the same code run on a laptop and on Render without a fork. Every temptation to reach "up" into web concerns from inside the core must be refused. If the core needs to know who the user is, the design is wrong — the caller should have resolved that and passed down plain values.

### P2 — Local-first means the network is an optimization, never a dependency

On Desktop and Mobile, every P0 capability works with the network unplugged. The network makes things *better* (fresher forecast, synced trips, a tile someone else already fetched), never *possible*.

Web is the deliberate, stated exception (PRD §3.2). It is not a violation of this principle; it is an acknowledged different shape, and it is the *only* one.

### P3 — Server-side state is exceptional and enumerable

The hosted service does exactly four things. If a fifth appears, that is a design event requiring an explicit decision, not a quiet addition:

1. Broker authentication (passkeys, magic links, share tokens)
2. Hold the canonical copy of an account's trips for sync
3. Cache expensive external fetches (tiles, elevation) so they happen once for everyone
4. Run stateless compute for clients that cannot compute locally (Web, both signed-in and guest)

Anything else — analytics, telemetry, user tracking, a general-purpose "backend" — is out of scope by default.

### P4 — Guest sessions leave no server-side trace

Not "minimal data." Not "anonymized data." **None.** A guest's compute request is served and forgotten. Their work lives in their own browser. This is a hard guarantee, not a best effort, and it is why guest compute is stateless rather than merely un-authenticated.

### P5 — The user's work is never silently destroyed

Conflicts surface. Overwrites are chosen, never inferred. Guest work is offered a home when signing in, not discarded. This principle is enforced structurally (§8.4's version-check protocol), not left to careful coding.

### P6 — Plugins extend; they do not modify

The core defines the schema and the extension points. A plugin fills in behavior at those points. A plugin that requires a change to core code to work is not a plugin — it is a core feature wearing a costume, and it should be built as one.

### P7 — External resources are borrowed, not owned

Every external API (OpenTopography, Open-Meteo, Nominatim) is a shared commons with real limits. Fetch once, cache with a TTL matched to actual volatility, and never re-request what is already held. OpenTopography's 50-calls/24h ceiling makes this a functional constraint, not an etiquette preference.

---

## 3. Component Map

```
┌───────────────────────────────────────────────────────────────────────┐
│                         FLUTTER CLIENT (Dart)                         │
│                                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  ┌──────────────┐  │
│  │ UI / State  │  │ Local Store  │  │ Sync Agent │  │   Plugin     │  │
│  │ (Riverpod)  │  │   (drift)    │  │            │  │  Registry    │  │
│  └─────────────┘  └──────────────┘  └────────────┘  └──────────────┘  │
│         │                 │                │                │         │
│         └─────────────────┴────────────────┴────────────────┘         │
│                                  │                                    │
│                    ┌─────────────┴──────────────┐                     │
│                    │   Routing Client (facade)  │                     │
│                    └─────────────┬──────────────┘                     │
└──────────────────────────────────┼────────────────────────────────────┘
                                   │
              ┌────────────────────┴────────────────────┐
              │                                         │
    Desktop / Mobile                                  Web
    (local sidecar)                            (network → Render)
              │                                         │
┌─────────────┴──────────────┐          ┌───────────────┴───────────────┐
│    LOCAL ROUTING SIDECAR   │          │      RENDER (hosted)          │
│    ─ FastAPI (loopback)    │          │                               │
│    ─ ctp-core (library)    │          │  ┌─────────────────────────┐  │
│    ─ Local caches on disk  │          │  │   FastAPI (public)      │  │
└────────────────────────────┘          │  │   ─ auth / sync / share │  │
                                        │  │   ─ guest compute       │  │
                                        │  │   ─ tile + elev cache   │  │
                                        │  └───────────┬─────────────┘  │
                                        │              │                │
                                        │  ┌───────────┴─────────────┐  │
                                        │  │   ctp-core (library)    │  │
                                        │  └─────────────────────────┘  │
                                        │  ┌─────────────────────────┐  │
                                        │  │   Postgres              │  │
                                        │  └─────────────────────────┘  │
                                        └───────────────────────────────┘
                                                       │
                                   ┌───────────────────┴──────────────────┐
                                   │       EXTERNAL (borrowed, cached)    │
                                   │  OpenTopography · Open-Meteo ·       │
                                   │  Nominatim · OSM Overpass            │
                                   └──────────────────────────────────────┘
```

**The key structural insight**: `ctp-core` appears *twice* — once inside the local sidecar on Desktop/Mobile, once inside the Render service. Same library, same version, two deployments. The Flutter client talks to a FastAPI over HTTP in both cases; only the base URL differs (`http://127.0.0.1:PORT` vs `https://api.…`).

This is why §4 matters so much.

---

## 4. The Portability Problem

**The problem**: the routing core is Python. Flutter is Dart. Desktop and Mobile must run OSMnx *on the device* (P2). Therefore a Python runtime must ship inside a Flutter application on Windows, macOS, Linux, Android, and iOS.

This is the hardest technical constraint in the entire project, and the PRD's local-first guarantee stands or falls on it. Three approaches, evaluated honestly:

### Option A — Rewrite the routing core in Dart

**Verdict: rejected.**

Kills the OSMnx learning goal outright, which is a stated project purpose (PRD §1). Would mean reimplementing graph construction, Overpass querying, simplification, and raster elevation reads from scratch in a language with no meaningful geospatial ecosystem. The product might survive this; the project's *reason for existing* would not.

### Option B — Embedded Python interpreter (in-process)

Bundle CPython into the Flutter app and call it via FFI (e.g. `dart:ffi` against `libpython`, or a package like `serious_python`).

**Pros**: no separate process, no port management, no IPC.

**Cons that sink it**: OSMnx's dependency tree is heavy native code — `numpy`, `scipy`, `rasterio`/GDAL, `geopandas`/`shapely`/GEOS. Getting that stack cross-compiled and correctly linked inside an embedded interpreter, on five platforms, with iOS's code-signing and no-JIT constraints, is a research project in itself. A GEOS linkage failure on iOS would be discovered late and have no clean workaround.

### Option C — Local sidecar process ✅ **CHOSEN**

Ship the routing core as a **standalone binary** (PyInstaller/Nuitka-frozen, containing Python + OSMnx + its native deps) that the Flutter app launches as a child process on startup. It runs FastAPI bound to `127.0.0.1` on an ephemeral port. Flutter talks to it over HTTP — exactly as it talks to Render.

**Why this wins**:

- **The client has one transport.** `RoutingClient` issues HTTP requests against a base URL. Local vs. hosted is a *configuration difference*, not a code path. This single fact removes an enormous class of divergence bugs and makes Web a natural third case rather than a special one.
- **The FastAPI layer gets exercised on every platform**, not just Web — which serves the FastAPI learning goal far better than a local FFI path that bypasses it.
- **Native dependency hell is solved once per platform, by a packaging tool built for exactly that**, rather than being fought inside an embedded interpreter.
- **Process isolation**: a segfault deep in GEOS kills the sidecar, not the app. Flutter can detect the dead child, surface it honestly, and restart it.

**Costs, stated plainly**:

- Binary size. A frozen OSMnx stack is on the order of 150–300 MB per platform. This is real and it is accepted — it lands on top of the PRD's already-acknowledged bundled-region size risk (PRD §7).
- Process lifecycle management (spawn, health-check, port discovery, graceful shutdown, orphan cleanup) is genuine work. §6.3 specifies it.
- **iOS is the open risk.** iOS prohibits `fork`/`exec` of arbitrary executables in sandboxed apps. The sidecar-as-child-process model does not translate directly. See §4.1.

### 4.1 The iOS Exception — an honest open problem

On iOS, Option C's child-process model is not permitted. Options, none yet chosen:

| Approach | Assessment |
|-|-|
| Embedded interpreter on iOS only (Option B, scoped to one platform) | Contains the blast radius, but means iOS runs a genuinely different execution model — the exact fork this architecture exists to avoid |
| iOS is online-only (routes computed on Render, like Web) | Simple and honest, but **breaks the PRD's offline-mobile guarantee** (FR16/FR17) specifically on iOS — a real product regression, not a shrug |
| Precompute-and-download: iOS never routes locally, but downloads fully-computed routes for offline *viewing/navigation* | Preserves the offline field use case (which is mostly *following* a route, not *generating* one) while conceding local generation. Arguably matches actual usage |

**Recommendation**: defer this decision to M7, but **prototype the frozen-binary sidecar on Android during M3** — Android permits child processes and will validate the model. Do not let iOS's constraint dictate the Desktop/Android architecture, and do not discover the iOS problem at M7 having assumed it away.

**This is the single largest open technical risk in the project.** It is tracked in §11 rather than buried here.

---

## 5. Tier 1 — `ctp-core` (Routing Library)

### 5.1 Boundary

`ctp-core` is a pure Python package. It has **no** FastAPI import, no request objects, no user IDs, no session concepts (P1). Its entire surface is functions over plain data.

```python
# The shape of the contract — not final signatures, but the right *shape*

def build_graph(bbox: BBox, network_type: str, cache_dir: Path) -> Graph: ...

def enrich_elevation(graph: Graph, tiles: list[Path]) -> Graph: ...

def score_edges(graph: Graph, weights: WeightProfile) -> Graph: ...

def solve_route(
    graph: Graph,
    start: Coord,
    end: Coord | None,
    waypoints: list[Coord],
    shape: RouteShape,       # loop | out_and_back | point_to_point
    theme: Theme,            # flattest | most_climbing | lowest_traffic | fewest_turns | most_art
    weights: WeightProfile,
    cpus: int,
) -> Route: ...

def export_route(route: Route, fmt: ExportFormat) -> bytes: ...
```

Note `cpus` is a **parameter**, not something the library discovers. The caller decides (PRD §5.1: `floor(cores/2)` on device; a fixed value on Render). The library does not know or care where it runs — that is P1 in practice.

### 5.2 Internal structure

```
ctp-core/
├── graph/         # OSMnx construction, caching, simplification
├── elevation/     # GEDTM30 GeoTIFF reads (rasterio), void handling
├── scoring/       # The five theme scoring functions + WeightProfile
├── routing/       # Dijkstra/A* solve, shape handling (loop/OAB/P2P)
├── trips/         # Multi-day splitting, waypoint ordering
├── export/        # GPX / TCX / FIT / GeoJSON writers
└── providers/     # Interfaces for pluggable data (§10) — interfaces only
```

### 5.3 Scoring model

The five themes (FR1–FR5) are **not five algorithms**. They are five `WeightProfile` instances fed to one scoring function. This matters: it keeps the "add a theme" cost near zero, and it makes FR13's per-segment weighting a natural extension rather than a rewrite.

```python
@dataclass
class WeightProfile:
    elevation_gain: float      # negative = avoid climbing, positive = seek it
    traffic_class: float
    turn_count: float
    surface_penalty: dict[str, float]
    poi_bonus: dict[str, float]   # {"tourism=artwork": 2.0, "historic=*": 1.5}
    detour_budget: float          # max multiple of shortest-path distance
```

| Theme | Profile shape |
|-|-|
| Flattest (FR1) | `elevation_gain` strongly negative |
| Most climbing (FR2) | `elevation_gain` strongly positive |
| Lowest traffic (FR3) | `traffic_class` strongly negative |
| Fewest turns (FR4) | `turn_count` strongly negative |
| Most art/history (FR5) | `poi_bonus` populated, `detour_budget` loosened |

**On FR4 specifically** — the turn signal is computed at graph-simplification time, not at solve time. A "turn" is an edge transition where the OSM `way` id or `name` changes, or where the node's street count indicates a decision point. Because OSMnx's `simplify_graph` already collapses interstitial nodes, a curving road *is one edge* — so curvature is invisible to the turn counter by construction, which is exactly the FR4 requirement. This is the cheapest possible implementation of that requirement and it falls out of the tool's own model.

### 5.4 Elevation — void handling

GEDTM30 has no fallback service by design (PRD §5.2). The void policy is therefore load-bearing:

```
read coordinate from local GeoTIFF
  ├── value present        → use it
  ├── nodata / void        → elevation delta = 0.0 for that coordinate
  └── tile missing on disk → elevation delta = 0.0, log once per tile
```

**Never** raise, never block, never spin waiting for a network fetch mid-solve. A route through a data void is a slightly-wrong route; a route that hangs is a broken product.

### 5.5 Why FR13 is not a rewrite

`WeightProfile` is looked up **per edge**, not per solve. In the single-scalar case (FR1–FR5), every edge resolves to the same profile. In the FR13 case, an edge resolves to the profile governing its position (tour default → day override → segment override). The solver never learns the difference:

```python
def edge_cost(edge, position: float) -> float:
    profile = weights.at(position)   # scalar case: always the same object
    return apply(profile, edge)
```

This is the whole reason FR13 is "an iteration on the same functions, not a rewrite" (PRD §7). Build `weights.at()` returning a constant in M1, and FR13 becomes a change to *one function* in M5.

---

## 6. Tier 2 — `ctp-service` (FastAPI)

### 6.1 One codebase, two deployment profiles

`ctp-service` wraps `ctp-core` in FastAPI. It runs in two modes, differing by **configuration, not code**:

| | **Sidecar mode** (Desktop/Mobile) | **Hosted mode** (Render) |
|-|-|-|
| Bind | `127.0.0.1`, ephemeral port | `0.0.0.0`, public |
| Auth | None (loopback is the trust boundary) | Passkey / session cookie / guest |
| Database | None | Postgres |
| Routing endpoints | ✅ | ✅ |
| Auth / sync / share endpoints | ❌ disabled | ✅ |
| Tile + elevation cache | Local disk | Shared server-side |
| CORS | Not applicable | Strict allowlist |

Mode is selected by an env var at startup. Endpoints not valid for a mode are **not registered** — not merely guarded. A sidecar has no `/auth/*` routes to attack.

### 6.2 Endpoint surface

```
# Routing — both modes
POST   /routes/generate          # theme + shape + start/waypoints → Route
POST   /routes/{id}/export       # → GPX | TCX | FIT | GeoJSON
POST   /trips/split              # multi-day splitting (FR11)
GET    /geocode?q=…              # OSMnx geocoder.geocode() (Nominatim)

# Content — both modes (cache-backed)
GET    /tiles/{z}/{x}/{y}        # basemap tiles
GET    /elevation?bbox=…         # GEDTM30 GeoTIFF
GET    /weather?lat=…&lon=…&date=…   # Open-Meteo (historical | forecast)

# Accounts — hosted mode only
POST   /auth/passkey/register
POST   /auth/passkey/verify
POST   /auth/magic-link
POST   /auth/qr-authorize        # FIDO2/CTAP hybrid
GET    /trips                    # library (FR36)
PUT    /trips/{id}               # write, with version check (FR32)
GET    /trips/{id}/version       # cheap version probe (FR32)
POST   /trips/{id}/share         # → revocable token (FR20)
DELETE /shares/{token}
GET    /profile                  # rider profile (FR40)
PUT    /profile/grants           # per-field sharing grants (FR41)
```

### 6.3 Sidecar lifecycle (Desktop/Mobile)

The failure modes here are the ones that will actually bite in the field, so they are specified rather than assumed:

```
App start
  ├── Find free port (bind :0, read assigned port, release)
  ├── Spawn sidecar binary with --port=N --mode=sidecar --cache-dir=…
  ├── Poll GET /health until 200 (timeout: 30s — cold graph load is slow)
  │     └── on timeout → surface honestly: "routing engine failed to start",
  │                       offer retry; do NOT fail silently or hang a spinner
  ├── App runs; sidecar is a child process
  │
  ├── Sidecar dies mid-session
  │     └── Flutter detects (health poll / connection refused)
  │         → restart once, transparently
  │         → if restart fails, degrade honestly: cached trips still viewable,
  │            new route generation unavailable, stated inline (PRD §4.4)
  │
  └── App exit → SIGTERM sidecar → SIGKILL after grace period
        └── Orphan sweep on next launch (stale PID file) — a crashed app
            must not leave a Python process holding a port forever
```

**Health endpoint returns readiness, not liveness.** A sidecar that is up but still loading a large graph is *not* ready, and the client must know the difference or it will fire requests into a void.

### 6.4 Guest compute — enforcing P4

Guest requests are served with **no session, no ID, no row, no log line containing request content**. The only guest state that exists anywhere on the server is the rate-limiter's in-memory IP counter, which:

- lives in process memory (not Postgres, not Redis)
- holds a count and a timestamp — never a request body, never a coordinate
- evaporates on restart

This is what "leaves no trace" means concretely. If a future change would require persisting anything keyed to a guest, that change violates P4 and needs an explicit decision, not an implementation.

### 6.5 Rate limiting

Per PRD §5.3: in-memory per-IP counter (`slowapi`), UAT-calibrated mean+2σ with progressive cool-off, single Render instance, no Redis.

**The known break condition, stated so it is not a surprise**: this is correct *only* on a single instance. If Render ever scales horizontally, each instance counts independently and the effective limit multiplies by N. That is the accepted MVP simplification (PRD §7) — but the *trigger* for revisiting it is "a second instance exists," not "abuse was observed." Write it down as a deployment invariant: **one instance, or redesign the limiter.**

---

## 7. Tier 3 — Flutter Client

### 7.1 Layering

```
┌────────────────────────────────────────────┐
│ Presentation — screens, widgets            │
├────────────────────────────────────────────┤
│ State — Riverpod providers                 │
├────────────────────────────────────────────┤
│ Domain — Trip, Route, WeightProfile,       │
│          RiderProfile (pure Dart, no I/O)  │
├────────────────────────────────────────────┤
│ Data                                       │
│  ├── RoutingClient  → HTTP (local | Render)│
│  ├── TripRepository → drift (local) + sync │
│  ├── PluginRegistry → §10                  │
│  └── SecureStore    → OAuth tokens only    │
└────────────────────────────────────────────┘
```

**`RoutingClient` is the linchpin.** It holds a base URL. On Desktop/Mobile that is `http://127.0.0.1:{sidecarPort}`; on Web it is the Render origin. **Nothing above the Data layer knows which.** That is the payoff of §4's sidecar decision, and it should be defended: any `if (kIsWeb)` appearing above the Data layer is a design smell and probably a bug.

### 7.2 Storage, by platform

| Platform | Trips | Tiles / elevation | Tokens |
|-|-|-|-|
| Desktop | drift (SQLite) | App-support dir | OS keychain |
| Mobile | drift (SQLite) | App-support dir | Keychain / Keystore |
| Web (signed-in) | Server (Postgres) | Browser HTTP cache | Session cookie |
| Web (guest) | IndexedDB | Browser HTTP cache | — |

**One `TripRepository` interface, three implementations.** Web's is server-backed; guest's is IndexedDB-backed and never syncs. The interface does not expose sync as an operation the UI can call — sync is a property of the implementation, so guest mode cannot accidentally sync.

### 7.3 Layer preferences and size classes (FR8)

Size class is derived from **viewport at runtime**, not from platform identity — a resized desktop window genuinely crosses classes, and the PRD calls that intentional:

```
viewport.width >= LARGE_THRESHOLD  →  large/fullscreen
                          otherwise →  compact/phone
```

Each class holds its own layer set. On first entry to an unused class, seed from that class's default — **never** copy the other class's set (a dense desktop config would flood a phone). Both sets sync per account (FR21); guests keep both in browser storage, unsynced.

---

## 8. Data Architecture

### 8.1 Postgres schema (hosted mode only)

```sql
account(id, created_at)
  -- deliberately no email column; passkeys need no email
  -- magic-link email is transient (§8.2), never stored on the account

passkey(id, account_id → account, credential_id, public_key,
        sign_count, transports, label, created_at, last_used_at)
  -- N per account (FR19); losing one device is not lockout

session(token_hash, account_id → account, expires_at, revoked_at)
  -- Web only; Desktop/Mobile use passkey assertions, not cookies

trip(id, account_id → account, name, version, updated_at,
     payload JSONB, deleted_at)
  -- version is the FR32 comparison key: a monotonic int, bumped on write
  -- payload holds route geometry, waypoints, day splits, weight profiles

share(token_hash, trip_id → trip, created_at, revoked_at, expires_at)
  -- recipient needs no account (FR20)

rider_profile(account_id → account, fields JSONB, updated_at)

profile_grant(id, owner_account_id → account,
              grantee_account_id → account,
              granted_fields TEXT[],       -- FR41: explicit allowlist
              created_at, revoked_at)
  -- Empty array = nothing shared. This is the DEFAULT.
  -- There is no "share all" flag — only an enumerated field list.

preference(account_id → account, size_class, key, value)
  -- FR8 layer sets + contrast override (FR21)
```

**Two schema decisions worth defending:**

**`granted_fields` is an allowlist, never a denylist.** A new sensitive field added to `rider_profile` later is *automatically not shared* with existing grantees, because it is not in anyone's array. A denylist would silently expose it to every existing grant the moment it shipped. This is P5 applied to schema design.

**`trip.payload` is JSONB, not normalized.** Trips are read and written whole (FR32 reconciles whole trips, not fields — the PRD explicitly rejects per-field merging). Normalizing route geometry into relational tables would buy query power the product does not need and impose a join cost on every read that it does.

### 8.2 What is deliberately absent

- **No email on `account`.** Passkeys do not need one. A magic-link request holds an email in memory long enough to send, then discards it. Nothing to breach, nothing to leak.
- **No guest table.** (P4.)
- **No analytics/telemetry tables.** (P3.)
- **No password column.** Not "unused" — *absent*, so it cannot be quietly reintroduced.

### 8.3 Local schema (drift, Desktop/Mobile)

Mirrors `trip` plus a sync-tracking column:

```
trip(id, name, version, updated_at, payload, dirty, server_version)
```

- `dirty` — has this device changed the trip since its last successful sync?
- `server_version` — the version this device last saw on the server; the input to FR32's comparison

### 8.4 The version-check protocol (FR32)

This is the mechanism behind P5. It runs at **two** points, and the second one is the one people forget:

```
ON OPEN
  local.server_version  vs  GET /trips/{id}/version
    ├── equal        → proceed
    └── server newer → PROMPT: keep both (save-as) | take server copy
                       (never auto-merge, never auto-overwrite)

ON SAVE  ← the check most implementations omit
  re-probe GET /trips/{id}/version immediately before PUT
    ├── unchanged since open → PUT, bump version
    └── changed since open   → PROMPT (same two choices)
```

**Why the second check is not redundant**: two devices can open the *same* version, both pass the open-check cleanly, then both save. An open-only check lets the second write silently destroy the first. The save-time probe is the only thing standing between the user and exactly the data loss P5 forbids.

Implemented as a conditional write (`PUT` carrying the expected version; the server rejects with `409 Conflict` if it has moved), so the check and the write are not racy against each other.

---

## 9. External Integrations

All four follow P7: fetch once, cache with a volatility-matched TTL, never re-request what is held.

| Service | Used for | Auth | Cache TTL | Attribution |
|-|-|-|-|-|
| **OpenTopography** | GEDTM30 elevation GeoTIFF | API key | Long (terrain is static) | **CC BY — required** |
| **Open-Meteo** | Historical + forecast weather | None | Forecast: short. Historical: long/bundled | **CC BY 4.0 — required** |
| **Nominatim** (via OSMnx `geocoder.geocode()`) | Location search | None | Medium | OSM/ODbL |
| **OSM Overpass** (via OSMnx) | Graph + POI tags | None | Long (OSMnx handles) | OSM/ODbL |

### 9.1 Elevation cache — the two-phase model

Per PRD §5.2, this changes shape at M6, and the change is architectural, not incidental:

```
MVP (M1–M5)          each device → OpenTopography directly
                     ⚠ works only because users ≈ 1
                     ⚠ 50 calls/24h ceiling is a hard wall
                     ⚠ EXPLICITLY DISPOSABLE — do not build on it

M6+                  device → Render cache → (miss) → OpenTopography
                     ✅ one fetch serves every user, forever
                     ✅ enables the packaged NC bundle + Marion, NC default
```

**Design consequence, and it is the important part**: the client must talk to the elevation cache through the *same interface* in both phases, so that M6 changes a base URL and a cache-lookup step — not the client. Build the indirection at M1 even though M1 does not need it. The alternative is a client rewrite at M6, which is exactly the kind of avoidable cost this document exists to prevent.

### 9.2 Attribution is a build artifact, not a nicety

GEDTM30 (CC BY) and Open-Meteo (CC BY 4.0) require attribution wherever their data appears. This means:

- A visible credit in the app's about/info surface
- Attribution embedded in exported files where the format permits (GPX `<metadata>`)

Treat a missing attribution as a **build failure**, not a polish item. It is a license condition, and the entire free-core-app strategy (PRD §3.5) rests on honoring the terms of these non-commercial licenses.

---

## 10. Plugin Architecture

Per PRD §3.5: **data elements live in the core schema; interface and business logic live in the plugin.** P6 is the rule; this section is the mechanism.

### 10.1 Two plugin runtimes — this is not a compromise, it is the shape of the problem

The PRD's four categories do not share an execution environment, and forcing them into one would be a design error:

| Category | Runs in | Why there |
|-|-|-|
| **Output/integration** (Garmin, Wahoo, Coros) | **Flutter (Dart)** | Holds the user's OAuth token; must reach the vendor API from the user's own device. Routing it through the server would make Greg's service a credential custodian for every user — a liability the PRD explicitly declines |
| **Data-provider input** (traffic, POI, boundaries) | **Python (`ctp-core`)** | Must feed the routing graph *during* scoring. A data source that cannot influence edge cost is not a data provider — it is a map overlay |
| **Route-creation input** | **Python** | Produces waypoints with attributes, consumed at solve time |
| **Premium features** (streetview, hyperlapse, history) | Case-by-case | Hyperlapse is a desktop CLI shell-out; version history is a server concern. These share a *billing* boundary, not a runtime |

### 10.2 Python-side provider interfaces (`ctp-core/providers/`)

The core defines these; it ships **zero** implementations beyond OSM defaults:

```python
class EdgeDataProvider(Protocol):
    """Road/edge attributes: traffic, construction, scenic byways."""
    def annotate_edges(self, graph: Graph, bbox: BBox) -> Graph: ...

class NodeDataProvider(Protocol):
    """Point data: restaurants, lodging, bike shops."""
    def fetch_nodes(self, bbox: BBox, categories: list[str]) -> list[Node]: ...

class ShapeDataProvider(Protocol):
    """Polygon data: parks, property boundaries. First polygon geometry in the app."""
    def fetch_shapes(self, bbox: BBox, kinds: list[str]) -> list[Shape]: ...
```

The core's own OSM-tag lookups (FR14 lodging, FR5 art/history POIs) **implement these same interfaces**. That is not decoration — it is the proof that the interfaces are real. If the built-in OSM path cannot be expressed as a `NodeDataProvider`, the interface is wrong, and we find that out at M1 instead of at M9.

### 10.3 Dart-side integration interface

```dart
abstract class OutputIntegration {
  String get id;
  String get displayName;
  Future<void> authenticate();          // OAuth, token → SecureStore
  Future<void> pushRoute(Route route);  // → vendor API, direct from device
}
```

`PluginRegistry` discovers implementations; the UI renders whatever is registered. The core app has no compile-time knowledge of Garmin. **Tokens go to `SecureStore` (Keychain/Keystore) — never to drift, never to the server.**

### 10.4 The boundary that must not be crossed

**A plugin may not require a change to core code.** If it does, the extension point is missing or wrong — fix the extension point, do not special-case the plugin. That is P6 stated as a build rule, and it is the difference between a plugin architecture and a plugin-shaped pile of conditionals.

---

## 11. Risks (Architectural)

These are risks introduced *by this design* — distinct from the product risks in PRD §7.

| # | Risk | Severity | Mitigation |
|-|-|-|-|
| A1 | **iOS cannot spawn the sidecar** (§4.1). Threatens FR16/FR17's offline guarantee on one platform | **HIGH** | Prototype the frozen sidecar on Android at M3. Decide iOS at M7 from three named options (§4.1). **Do not assume it away.** |
| A2 | Frozen Python binary is 150–300 MB per platform, stacking on the bundled-region size risk | Medium | Accepted. Strip unused deps aggressively; consider on-demand sidecar download post-install rather than bundling in the installer |
| A3 | Sidecar process lifecycle bugs (orphans, port collisions, zombie processes after a crash) | Medium | §6.3's explicit protocol: PID file, orphan sweep on launch, readiness (not liveness) health check, bounded restart |
| A4 | Rate limiter is correct only on a single Render instance (§6.5) | Medium | Written down as a **deployment invariant**. The trigger to redesign is "a second instance exists," not "abuse observed" |
| A5 | `ctp-core` drifts toward web-awareness — someone passes a `Request` in, or reaches for a user ID | Medium | P1 enforced by lint: `ctp-core` may not import `fastapi`. Make it a CI check, not a code-review hope |
| A6 | Two `ctp-core` deployments (sidecar + Render) drift to different versions, causing routes that differ by platform | Medium | Version-pin the sidecar binary to the service release. Surface both versions in `/health` so a mismatch is visible, not mysterious |
| A7 | The M6 elevation-cache transition requires a client rewrite because M1 hardcoded direct OpenTopography calls | Medium | §9.1: build the interface indirection at M1. The cost is one afternoon now versus a client rewrite later |

---

## 12. Decision Log

Decisions made *in this document* (PRD decisions are logged in the PRD).

| # | Decision | Rationale | Alternatives rejected |
|-|-|-|-|
| D1 | **Local sidecar process** for the routing core on Desktop/Mobile | One HTTP transport for all platforms; native deps solved by a packaging tool; process isolation | Dart rewrite (kills the OSMnx learning goal); embedded interpreter (GDAL/GEOS linkage on 5 platforms is a research project) |
| D2 | **`ctp-core` is a pure library** with no web awareness | Same code runs local and hosted without a fork | A service-only core would forbid offline; a client-only core would forbid Web |
| D3 | **Themes are `WeightProfile` data, not five algorithms** | Adding a theme costs a config entry; FR13 becomes a change to one function | Five bespoke solvers — five places for a bug to hide |
| D4 | **`trip.payload` as JSONB** | Trips are read/written whole; FR32 reconciles whole trips by design | Normalized geometry tables — join cost on every read, query power the product never uses |
| D5 | **`profile_grant.granted_fields` is an allowlist** | A future sensitive field is not shared by default. A denylist would leak it on the day it ships | Denylist; a boolean `share_all` flag |
| D6 | **No email column on `account`** | Passkeys need none; magic-link email is transient. Nothing stored is nothing breached | Storing email "for convenience" |
| D7 | **Conditional write (`409 Conflict`)** for FR32's save-time check | The check and the write cannot race each other | Check-then-write (a race window between them is exactly the bug FR32 exists to prevent) |
| D8 | **Plugins split across two runtimes** (Dart for output, Python for data providers) | Each category runs where its data must live: OAuth tokens on-device, edge scoring in the graph | A single plugin runtime — would force OAuth tokens through the server, making the service a credential custodian |
| D9 | **Built-in OSM lookups implement the provider interfaces** | Proves the interfaces are real at M1, not at M9 | Bolting interfaces on later, discovering they don't fit |
| D10 | **Elevation-cache indirection built at M1**, before it is needed | M6's shared-cache transition becomes a config change, not a client rewrite | Hardcoding direct calls, paying for it at M6 (A7) |

---

## 13. Open Architectural Questions

| # | Question | Needed by |
|-|-|-|
| Q1 | **iOS sidecar strategy** — embedded interpreter, online-only, or precomputed-routes-for-offline-viewing? (§4.1) | **M7** — but prototype on Android at M3 |
| Q2 | Tile generation tool (`tilemaker` → MBTiles, or alternative)? Inherited from PRD §9 Q1 | M6 |
| Q3 | Frozen-binary tool: PyInstaller vs. Nuitka vs. platform-specific? Affects size (A2) and startup time | M3 |
| Q4 | Does the sidecar ship *in* the installer, or download on first run? Trades install size against a network dependency at first launch | M3 |
| Q5 | Plugin distribution: pub.dev + PyPI, or a bundled registry? Inherited from PRD §9 Q2 | M9 |

---

## Appendix: Glossary

| Term | Meaning |
|-|-|
| **`ctp-core`** | The pure Python routing library. No web awareness (P1) |
| **`ctp-service`** | FastAPI wrapping `ctp-core`. Runs as local sidecar *or* hosted on Render |
| **Sidecar** | The `ctp-service` child process running on the user's own device (Desktop/Mobile) |
| **Hosted mode** | `ctp-service` on Render, serving Web and the shared caches |
| **`WeightProfile`** | The data structure defining a routing theme. Five themes = five profiles, one solver |
| **Size class** | large/fullscreen vs. compact/phone. Derived from viewport at runtime, not platform identity (FR8) |
| **Version check** | FR32's open-time *and* save-time comparison against the server's trip version |
