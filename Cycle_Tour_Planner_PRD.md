# Cycle Tour Planner — Product Requirements Document

**Status**: Ready for MVP
**Author**: Greg Frazier
**Version**: 2.1 (2026-07-21)
**Source spec**: `Cycle Tour Planner.md`

\---

## 1\. Executive Summary

**Problem**: Existing cycle route planners (RideWithGPS, Komoot, Strava) optimize for logging and social sharing, not for planning around a *theme or constraint* — flattest route, least traffic, most art, fewest turns — or for multi-day trip logistics like lodging, water stops, and elevation budgets per day.

**Solution**: A personal, local-first route planning application that generates routes against explicit goals (traffic, surface, elevation, points of interest) and supports multi-day trip planning with offline mobile use.

**Secondary purpose**: This project is explicitly a **learning vehicle**. The technology stack (OSMnx, FastAPI, Flutter/Dart across four targets) is fixed as a project goal in itself, not chosen purely for product fit. Architecture decisions favor hands-on exposure to these tools over the fastest path to shipping.

**Success metrics**:

* A route generates end-to-end (OSMnx → FastAPI → Flutter client) for all five MVP themes
* The Flutter client builds and runs on at least two of the four targets (e.g. Desktop + Android)
* GPX/TCX/FIT export opens correctly in RideWithGPS
* Greg uses it to plan one real ride

\---

## 2\. Problem Definition

### 2.1 Customer Problem

* **Who**: Four personas — Professional Tour Planner, Weekend Outing Cyclist, Day Tripper, Guest Rider (§4.1)
* **What**: No single tool lets a rider plan routes around a specific goal (flattest, least traffic, most art/history, fewest turns) *and* handle multi-day logistics (lodging, water, weather, per-day mileage/elevation caps) — and a rider not ready to install anything or create an account should still be able to use the core of it
* **When**: Pre-trip planning, from a single afternoon loop to a multi-week point-to-point tour
* **Where**: Desktop and Web for deep planning; Mobile for quick route creation, trip edits, and offline use on the road
* **Why**: Mainstream tools are built around segment-chasing and social feeds, not goal-driven route generation or trip-level logistics
* **Cost of not solving**: Manual spreadsheet-and-map planning; no offline-safe navigation; no thematic routing

### 2.2 Context

A personal project, not a commercial product. No market sizing, no revenue goal. The "business case" is personal utility plus deliberate skill-building in geospatial routing (OSMnx), API design (FastAPI), and cross-platform app development (Flutter).

\---

## 3\. Solution Overview

### 3.1 Architecture Shape

Three tiers:

1. **Routing core** — Python + OSMnx over OpenStreetMap data, generating routes scored against configurable goals (elevation, traffic, surface, POIs, turn count). Local-first does not mean local-only: online is the norm, and offline usability is preserved for the features that support it.
2. **Middle layer** — FastAPI exposing routing, trip, and content operations over HTTP, plus account-holder trip sync and a stateless compute path for unauthenticated guests.
3. **Client** — one Flutter/Dart codebase across Android, iOS, Desktop, and Web. Mobile and Desktop work fully offline once trip content is downloaded. Web is server-backed and online-only (§4.4).

### 3.2 Platform Model

The four targets are not uniform, and the differences are deliberate:

||Desktop|Mobile (Android/iOS)|Web (signed-in)|Web (guest)|
|-|-|-|-|-|
|**Routing compute**|Local (OSMnx on device)|Local (OSMnx on device)|Server (FastAPI)|Server (FastAPI)|
|**Offline capable**|Yes|Yes|No|No|
|**Trip storage**|Local (SQLite/drift) + server sync|Local (SQLite/drift) + server sync|Server (Postgres)|Browser only (IndexedDB/localStorage)|
|**Session model**|Passkey|Passkey|Cookie + Postgres session row|None|

**Web is intentionally online-only.** No browser runs the OSMnx routing core without a WASM port that isn't in scope, so Web depends on the hosted service for all compute. There is no offline path to cache against — this is a stated architectural difference, not a gap to close.

**Guest privacy is about server-side storage only.** A guest's in-progress work persists in their own browser so a refresh or closed tab doesn't lose it. Nothing is stored server-side: no email, no account, no personal details. Browser-local state is same-browser/same-device only, is lost if browser data is cleared or private/incognito is used, and never syncs or crosses devices.

### 3.3 MVP Definition

**Core loop**: Set a start location (FR34) → generate a route for each of the five themes (FR1–FR5) via OSMnx → serve through FastAPI → render in the Flutter Desktop client on self-hosted tiles → export as GPX/TCX/FIT (FR9).

**Success criteria**: A real route Greg would actually ride comes out the other end for at least the flattest theme and opens cleanly in RideWithGPS. The other four themes generate and render correctly even if not personally ridden before sign-off.

**In scope for MVP — navigation.** A per-day turn-by-turn **cue sheet** is generated from any routed trip (FR44), and **in-ride live navigation** with graceful GPS-loss degradation ships with the Mobile client (FR45). These were previously neither included nor excluded; they are now explicitly in scope — the cue sheet from the Desktop client onward (M3), live navigation with Mobile (M7).

**Learning goals validated**: non-trivial OSMnx custom weighting functions across distance, elevation, traffic-class, turn-count, and POI-tag signals; local-first elevation sourcing via GEDTM30; a FastAPI service with typed request/response models; a Flutter app rendering self-hosted tiles and a route.

### 3.4 Out of Scope

* Social feed, following, or segment leaderboards
* Non-cycling activity types (running, driving)
* Monetization of the core application (see §3.5 for the plugin exception)

### 3.5 Plugin Model

The core application is free and stays free. That is a deliberate licensing decision, not just a pricing preference: both external data dependencies the core relies on — **OpenTopography** (GEDTM30 elevation) and **Open-Meteo** (weather) — are free specifically for non-commercial use, and OpenTopography's API Agreement requires a paid Enterprise key once its API is integrated into a commercial software package. Keeping the core free sidesteps that classification for both dependencies at once.

Plugins sit outside the core's data dependencies, so a plugin can carry a price without dragging the core into commercial-tier licensing. Plugins also allow outside contribution without touching core code.

**Design principle**: data elements are designed into the core schema; the *interface and business logic* of a plugin feature live in the plugin.

Four plugin categories:

|Category|Examples|Why a plugin|
|-|-|-|
|**Output/integration**|Garmin, Wahoo, Coros, indoor ride simulators|Extensibility — riders pick their own device ecosystem|
|**Route-creation input**|Waypoint sources carrying structured attributes beyond a bare coordinate (amenity type, hours, booking info)|Extensibility|
|**Data-provider input**|*Road/edge*: live traffic, construction, accidents, scenic byways. *Node/point*: restaurants, lodging, bike shops, businesses. *Shape/area*: parks, property boundaries (first polygon geometry in the app)|**Licensing economics** — live traffic (HERE, TomTom) and curated business data (Google Places, Yelp) rarely have a free non-commercial tier. These are *structurally required* to be plugins if added at all|
|**Premium features**|Streetview imagery (FR27), hyperlapse (FR28), trip version history (FR33), popularity/heatmap routing (FR30/FR31)|Paid tier and/or metered third-party API dependencies|

**Execution model for output/integration plugins**: Flutter/client-side. Each integration is its own Flutter plugin package holding its own OAuth token and calling that platform's API directly from the device. FastAPI is not a proxy for this category. Tokens use platform-appropriate secure storage (Keychain/Keystore via `flutter\\\_secure\\\_storage`), never the general trip-data persistence layer.

**Status**: The plugin model is the agreed direction. Individual plugin FRs (FR27, FR28, FR30, FR31, FR33) remain unscoped until each is actually taken up. Rider profile data (FR40/FR41) was considered for this list and resolved as **core**, not a plugin — it's account-scoped data every persona needs, not an alternative implementation of a shared capability.

\---

## 4\. Requirements

### 4.1 Personas

**Professional Tour Planner**

* Optimizes logistics for clients: lodging along the route, restrooms/water at rest stops, weather by trip date
* Sets distance/day, min/max elevation gain, wind influence, surface parameters (paved/gravel/off-road/single-track)
* Plans multi-day point-to-point, loop, or stem-and-loop trips; starts/ends near major cities for airport access
* Wants frequently-cycled routes, greenways, rail trails; wants heatmap-style popularity data
* Wants routes rich with local history, art, murals, side trips, restaurants, local events
* Wants group skill-profile-aware suggestions
* Maintains rider profiles for their clients (FR40, FR41)

**Weekend Outing Cyclist**

* Single-destination or small-overnight trips for a long weekend
* Prefers low-cost state/national park campsites; convenience stores/cafes as rest stops
* Avoids cities; favors rural routes and small towns even at the cost of extra miles
* Strongly prefers loops; out-and-back least preferred
* Cares about surface type, may restrict to one extreme; seeks overlooks, waterfalls, vistas

**Day Tripper**

* Round-trips (same start/end)
* Mileage- and climb-driven, but wants a destination to anchor the ride

**Guest Rider (no account)**

* Uses the web app without creating an account — a Tour Planner's client who won't install anything, or a first-time visitor trying the product
* Can run all five themes, export GPX/TCX/FIT, and view weather — entirely unauthenticated
* Cannot access plugin features or save to an account
* In-progress work persists in their own browser (§3.2); signing in offers to import it (FR37)

### 4.2 Functional Requirements

#### Routing core (P0)

|ID|Requirement|Priority|
|-|-|-|
|FR1|Route generation optimized for the **flattest** theme (minimize elevation gain)|P0|
|FR2|Route generation optimized for the **most-climbing** theme (maximize/target elevation gain)|P0|
|FR3|Route generation optimized for the **lowest-traffic** theme|P0|
|FR4|Route generation optimized for the **fewest-turns** theme. A turn is a *navigational maneuver* — leaving the current OSM way/named road for a different one, or an intersection requiring a decision — **not** a heading-change angle. Staying on one way as it curves counts as zero turns, however much the road bends|P0|
|FR5|Route generation optimized for the **most-art/history** theme (OSM POI/tag-based, e.g. `tourism=artwork`, `historic=\\\*`)|P0|
|FR6|FastAPI endpoint(s) wrapping the OSMnx routing core, with auto-generated OpenAPI docs|P0|
|FR34|User sets start point — and optional destination and waypoints — via geocoded location search (online), map tap, or device GPS. This is the entry step before any theme routing runs. Offline, a point can only be set within the bounds of downloaded content; outside those bounds the user is prompted to restore connectivity|P0|
|FR35|User selects route shape — loop, out-and-back, or point-to-point — independently of the five themes. Any theme works in any shape. Loop is the default. Point-to-point requires a destination|P1|
|FR47|**Target distance control** (loop/out-and-back only; point-to-point has no target-distance input). A slider sets the desired route distance from a **10km floor to a 300km/180mi ceiling**, stepped on a **Fibonacci-like scale** (each step ≈ sum of the previous two) rather than linearly — fine-grained increments for short rides, coarse increments for long tours|P1|
|FR43|**Unsatisfiable constraint handling.** When no route satisfies every active constraint at once, the core reports *which* constraints conflict rather than failing or silently dropping one. The client explains the conflict and offers the nearest relaxations (each with its trade-off), or a manual adjust — never a raw error and never a silently-compromised route|P0|

#### Client \& display (P0–P1)

|ID|Requirement|Priority|
|-|-|-|
|FR7|Flutter client (Desktop first) requests a route and renders it on a map|P0|
|FR8|User-configurable map layers keyed to OSM tag categories (landmarks, POIs, parks, construction). For signed-in accounts, choices sync per **size class** — large/fullscreen (Desktop, fullscreen Web) and compact/phone (phone-sized Web, installed Mobile) — each class remembering its own set. First entry into an unused size class seeds from a class-appropriate default, never inheriting the other class's set wholesale. Guests keep choices per-browser|P0|
|FR9|GPX/TCX/FIT export of a generated route. The rider chooses **what to include** (track + elevation, waypoints/stops, turn-by-turn cue sheet per FR44, and optionally saved variants per FR42) and **how to split** (one file, or one file per day). Post-export hand-off to a connected service is the output-plugin path (§3.5)|P0|
|FR38|On first start with no local map/elevation data, user picks one of **North Carolina, Wisconsin, or Southern California (LA-centered)**, downloaded directly from OpenTopography. **Explicitly a disposable MVP stopgap** — see §5.2|P0|
|FR17|Android/iOS builds from the shared Flutter codebase, with feature parity for offline trips|P1|
|FR18|Flutter Web build reaching as close to Desktop *planning-feature* parity as practical for a server-backed client. Not offline parity — Web is online-only by design (§3.2)|P1|
|FR39|Local data pruning (Desktop and Mobile): user can view and delete downloaded map/elevation content not needed for a current or upcoming trip. Not applicable to Web|P1|
|FR48|**Routing-engine startup wait (Desktop/Mobile sidecar).** While the local backend is still becoming ready (first-run graph fetch and elevation enrichment can take minutes), the client waits indefinitely rather than surfacing a hard failure — a slow cold start is not an error. The wait is shown as an **escalating sequence of cycling-themed messages**, not a raw progress bar: early messages are ordinary pre-ride prep ("Filling up bottles…", "Airing up the tires…", "Lubing the chain…"); if the wait runs long, messages shift to the kind of relatable, lighthearted mishap that delays an actual ride ("Can't find the good pump…", "Forgot where the keys are…") — never a technical/error-toned message. Only the backend process actually dying (not merely slow) is a real failure state|P1|
|FR49|**Reset route-planning controls.** A single, always-visible action reverts theme, shape, start, destination, and target distance to their defaults (flattest, loop, unset, unset, 20km) and clears any generated route — lets the rider back out of an in-progress plan without individually re-toggling every control|P2|
|FR44|**Turn-by-turn cue sheet.** Every routed day produces an ordered maneuver list — cumulative mileage, maneuver (per FR4's navigational-maneuver definition), road name, and notes (surface change, waypoint, climb) — viewable on any platform and included in export (FR9). Derived from the route, so available wherever a route is|P0|
|FR45|**In-ride live navigation (Mobile).** Active guidance off the cue sheet (FR44): next maneuver with distance, upcoming-waypoint proximity, and a live elevation/climb readout, in Outdoor Contrast for sunlight legibility. On GPS loss it degrades gracefully — freezes at last-known position, states the loss once (passively, per §4.4), and the cue sheet stays usable by mileage; the route stays loaded and no data is lost|P0|

#### Trip planning (P1)

|ID|Requirement|Priority|
|-|-|-|
|FR10|Waypoint/checkpoint insertion before routing; route still optimizes for the selected theme *between* waypoints|P1|
|FR11|Min/max daily mileage and elevation caps for multi-day trip splitting|P1|
|FR12|Road surface tagging and surface-based filtering|P1|
|FR13|Sliding-scale weighting for elevation gain and surface preference, scoped to **whole tour / single day / partial day**. Day- or segment-level weights override the tour default only for that scope|P1|
|FR14|Lodging/campground data along a route, sourced from OSM tags|P1|
|FR15|Trip-dated weather via **Open-Meteo**, on all surfaces: **Historical Weather** (seasonal norms, for long-range planning) and **Weather Forecast** (10-day/hourly, as the date nears), both aligned to each day's planned location and date. Attributes: surface temp, min/max, wind speed and direction, precipitation probability and timing, `apparent\\\_temperature` as the combined feels-like reading, plus air quality (PM2.5, PM10, O₃, NO₂, UV, pollen) from Open-Meteo's Air Quality API|P1|
|FR16|Offline package: download a trip's map, route, POI content, and elevation tiles for offline use|P1|
|FR36|Trip library: list, search, rename, duplicate, delete saved trips; view and revoke active shares|P1|
|FR42|**Route alternatives \& variants.** A scoped re-route (FR13) is proposed *alongside* the current route — both drawn on one map (current as a ghost, proposed bold) with a side-by-side comparison of distance, climbing, surface, traffic, time, and day total. The rider takes the new route, keeps the current one, or **saves the alternative as a named variant** scoped to that day/segment. Variants persist on the trip and sync (FR21); "make active" swaps the drawn line and recomputes day totals. Nothing is committed until the rider chooses|P1|
|FR46|**Group-size-aware planning.** A trip carries a rider-band (solo → large organized group). Group size informs lodging/campground sizing (FR14), surfaces road-width and regroup cautions on narrow or gravel segments, and seeds day mileage/climb defaults. Distinct from individual rider profiles (FR40) and skill-profile suggestions (FR29)|P1|

#### Accounts, sync \& sharing (P1)

|ID|Requirement|Priority|
|-|-|-|
|FR19|Biometrics-first passkey auth (Face ID/Touch ID/Windows Hello). New devices authorized preferentially via **QR cross-device authorization** (FIDO2/CTAP hybrid) — no email round-trip. **Magic link** is the fallback when no trusted device is present, and also the explicit account-recovery path. Multiple passkeys bind per account. **No password-only or SMS OTP at any point.** A device awaiting passkey binding is never blocked — it gets full local planning capability immediately; only account-scoped surfaces wait|P1|
|FR20|Share a trip/route with another user (tour planner → client), viewable without the recipient having an account. Revocable|P1|
|FR21|Account holder's own trips sync across their signed-in devices via a canonical per-account copy in Postgres. Also carries non-trip preferences: layer visibility by size class (FR8) and the contrast-mode override (§6)|P1|
|FR22|Unauthenticated guest web sessions run all five themes (FR1–FR5), export GPX/TCX/FIT (FR9), and view both weather types (FR15). In-progress work persists browser-locally; nothing is stored server-side|P1|
|FR32|**Version check on open and on save.** Each signed-in client compares its local/last-loaded trip against the server version at launch *and again immediately before committing a save* — the second check catches two devices editing the same version in parallel. If the server is newer, the user chooses: save-as (keep both) or overwrite in place. **No trip is ever silently overwritten.** Does not apply to guests|P1|
|FR37|On first sign-in from a browser holding guest work-in-progress, offer to import that trip into the account. Explicit choice — never silently discarded, never silently uploaded|P1|

#### Rider profile (P2)

|ID|Requirement|Priority|
|-|-|-|
|FR40|Rider profile: height, weight, FTP, average speed, name, home location, dietary preference, lodging preference, surface preference, climbing preference, per-day distance preference, emergency contact name, emergency contact phone. Riding-preference fields seed the *defaults* that FR12/FR13 already allow to be overridden per trip, day, or segment — not a competing second system. **Core, not a plugin**|P2|
|FR41|Rider profile visibility: restricted by default to the rider. Granting a Tour Planner access presents **per-field checkboxes** — opt-in per field, defaulting to the least-shared state (nothing visible until explicitly checked). A distinct, explicit grant, never an automatic side effect of a shared trip (FR20) or sync (FR21)|P2|

#### Content \& extended features (P2–P3)

|ID|Requirement|Priority|
|-|-|-|
|FR23|"Building/architectural interest" themed tours using OSM tagging|P2|
|FR24|Audio narration for POIs selected during planning|P2|
|FR25|Crowd-sourced image/feedback upload on routes, roads, intersections, POIs, with public/private visibility|P2|
|FR26|Full trip export as GeoJSON with attributes|P2|
|FR29|Route/segment suggestions based on a group's rider skill profiles|P3 (stretch)|

#### Plugin features (unscoped — see §3.5)

|ID|Requirement|Status|
|-|-|-|
|FR27|Streetview-style/point-of-view imagery during planning|Plugin — unscoped|
|FR28|Desktop-only Street View hyperlapse preview via [streetwarp-cli](https://github.com/pelmers/streetwarp-cli). Depends on a Google Maps API key with Street View Static API billing, and `ffmpeg`. Absent on Mobile/Web — that absence is explained in-product at the handoff, never silent|Plugin — unscoped|
|FR30|Route/segment suggestions weighted toward frequently-cycled routes, greenways, rail trails|Plugin — unscoped|
|FR31|Route/segment popularity (heatmap-style) data as a routing input. No OSM-native equivalent|Plugin — unscoped|
|FR33|Trip version history: retain the last 5–10 versions of a trip for rollback. Builds on FR32's server-stored versions|Plugin — unscoped|

### 4.3 Representative User Stories

```
As a Day Tripper
I want a "flattest route" option that minimizes total elevation gain from my start point
So that I can pick a ride that matches an easy-effort day

Acceptance Criteria:
- \\\[ ] Total elevation gain is at or near the minimum achievable within the requested distance range
- \\\[ ] Elevation comes from locally-cached GEDTM30 tiles; a genuine data void falls back to a
      flat-earth assumption (0.0m change) for that coordinate — never stalling or erroring
- \\\[ ] Route remains valid and rideable even when elevation is heavily weighted
```

```
As any persona
I want a "fewest turns" option
So that I can ride a simpler route with less need to check directions

Acceptance Criteria:
- \\\[ ] Route has the lowest count of navigational maneuvers achievable within the distance/theme constraints
- \\\[ ] A single continuous road followed for miles scores well even if curvy
- \\\[ ] A route weaving through a neighborhood grid (turning every block) scores poorly, even though
      each individual segment is straight
- \\\[ ] The maneuver-based turn definition is documented
```

```
As a Professional Tour Planner
I want to weight elevation and surface on a sliding scale, for the whole tour, a day, or part of a day
So that I can front-load climbing on day 1 while riders are fresh, and favor gravel through day 3

Acceptance Criteria:
- \\\[ ] Elevation-gain and surface preference are each settable on a sliding scale (avoid ↔ prefer)
- \\\[ ] A weighting can be scoped to the whole tour, one full day, or a partial-day segment
- \\\[ ] Day/segment weights override the tour default only for that scope, without re-planning
      the whole trip from scratch
```

```
As a mobile user on a multi-day tour
I want previously-downloaded trip content to work with no network connection
So that I can navigate and view POI info in areas with no cell signal

Acceptance Criteria:
- \\\[ ] Route, tiles, elevation, and POI content download in advance
- \\\[ ] App functions with zero errors in airplane mode for a downloaded trip
- \\\[ ] Features that work fully offline show no offline messaging at all — they simply work
- \\\[ ] No feature silently fails: any limitation is passively discoverable (a quiet status indicator,
      or an inline note at that feature's boundary, shown once) — never an interruptive modal or toast
- \\\[ ] A Weather Forecast shown offline is stamped with its retrieval age ("forecast as of Tue 6pm")
      so a stale cached forecast is never mistaken for a current one
```

```
As an account holder
I want to be notified when a trip has a newer version on the server, at open and before save
So that I never silently lose or overwrite my own edits made on another device

Acceptance Criteria:
- \\\[ ] On open, the client compares its local copy against the server version
- \\\[ ] The same check runs again immediately before a save commits — catching two devices that
      opened the same version and edited in parallel
- \\\[ ] If the server is newer, an unmissable notification appears before editing continues
- \\\[ ] The user chooses: save current under a distinct name (keep both), or overwrite with the server version
- \\\[ ] No trip is silently overwritten or discarded
- \\\[ ] Does not apply to guest sessions, which have no server-stored trip
```

```
As a Guest Rider with no account
I want to generate and export a route without installing anything or signing up
So that I can try the product, or use a route someone planned for me, with zero setup friction

Acceptance Criteria:
- \\\[ ] All five themes (FR1–FR5), export (FR9), and both weather types (FR15) work with no account
- \\\[ ] In-progress work persists in the browser, so a refresh or closed tab doesn't lose it
- \\\[ ] Limits are stated plainly, never silently: same browser/device only; lost if browser data is
      cleared or incognito is used; no cross-device, sync, or share-back
- \\\[ ] Messaging reflects this — "saved on this browser — export or sign in to keep it anywhere else"
- \\\[ ] No server-side record of a guest session is ever kept
```

```
As a Professional Tour Planner
I want a proposed re-route shown next to the route it would replace, and the option to save it
So that I can compare a climb-heavy alternative against the valley route without losing either

Acceptance Criteria:
- \\\[ ] Both routes render on one map — current as a ghost, proposed as the bold line — sharing start/end
- \\\[ ] A side-by-side card compares distance, climbing, surface, traffic, time, and day total with deltas
- \\\[ ] I can take the new route, keep the current one, or save the alternative as a named variant on that day
- \\\[ ] A saved variant persists on the trip and syncs; nothing is committed until I choose
- \\\[ ] "Make active" swaps the drawn line and recomputes the day's totals
```

```
As any persona
I want to be told why a route can't be built when my constraints conflict
So that I can relax the right one instead of hitting a dead end

Acceptance Criteria:
- \\\[ ] When no route satisfies every active constraint, the app names the specific conflicting constraints
- \\\[ ] It offers the nearest relaxations, each stating its trade-off, applyable in one action
- \\\[ ] Manual constraint adjustment is always available as an alternative
- \\\[ ] The app never returns a raw error, and never silently drops or compromises a constraint
```

```
As a mobile user riding a planned day
I want turn-by-turn guidance and a cue sheet that keep working when I lose GPS
So that I can follow the route in sun, on the bike, and through dead zones

Acceptance Criteria:
- \\\[ ] Every routed day has an ordered cue sheet: cumulative mileage, maneuver, road name, and notes
- \\\[ ] Live navigation shows the next maneuver with distance, upcoming waypoints, and a climb readout
- \\\[ ] On GPS loss the map freezes at last-known position and states the loss once, passively (§4.4)
- \\\[ ] The cue sheet remains usable by mileage with no signal; the route stays loaded and nothing is lost
- \\\[ ] Guidance is legible outdoors (Outdoor Contrast) with thumb-reachable controls
```

```
As a Professional Tour Planner routing for a group
I want group size to shape lodging and flag narrow or gravel stretches
So that a route that works for one rider also works for eighteen

Acceptance Criteria:
- \\\[ ] A trip carries a rider-band (solo through large organized group)
- \\\[ ] Group size informs lodging/campground sizing along the route
- \\\[ ] Narrow-road and gravel segments raise a road-width / regroup caution for larger groups
- \\\[ ] Group size seeds day mileage/climb defaults, still overridable per FR13
```

### 4.4 Non-Functional Requirements

**Local-first (Desktop and Mobile)**
Core routing runs with no network connection. OSMnx works against locally-cached OSM extracts; elevation reads from local GEDTM30 GeoTIFF tiles bundled per trip bounding box. Two narrow exceptions:

1. **Weather Forecast** (FR15) inherently needs network when available; it degrades to its own last-cached forecast (age-stamped), never falling back to Historical Weather as a substitute.
2. **Cross-device sync** (FR21) — each device keeps a local working copy and works offline; divergence surfaces through FR32's version check, never silent reconciliation.

**Web is server-backed, not local-first**
See §3.2. Signed-in Web uses a conventional cookie + revocable Postgres session row. Guest sessions call FastAPI statelessly and store nothing server-side.

**Offline is expected, not an error**
Downloaded trip content is fully usable with zero errors and zero connectivity. Features that work offline show no offline messaging at all. A persistent, unobtrusive status indicator communicates connectivity passively. When a feature genuinely needs connectivity, that surfaces inline at that feature, once — never as a repeating, interruptive, or modal alert. No feature silently fails.

**Responsible use of shared external resources**
Every external dependency — map tiles, GEDTM30 elevation (OpenTopography), weather (Open-Meteo), geocoding (Nominatim via OSMnx) — is cached with a TTL appropriate to *that data's actual volatility*, a bounded cache size with eviction, and no repeat requests for data already held:

|Data|TTL|Notes|
|-|-|-|
|Weather Forecast|Short|A stale forecast is worse than none|
|Historical Weather|Long / bundled|Effectively static|
|Map tiles|Long|Changes slowly|
|Elevation tiles|Long|Changes slowly|

This is not merely politeness. OpenTopography's free non-academic key is limited to **50 calls/24 hours** — re-fetching a tile someone already downloaded risks exhausting it. The post-MVP shared cache (§5.2) formalizes "fetch once, serve everyone."

**Attribution is a compliance item, not a courtesy**: GEDTM30 is CC BY; Open-Meteo is CC BY 4.0. Both require attribution wherever the data appears.

**Power efficiency**
The Mobile client minimizes GPS/CPU/network wake-ups during long rides. Acceptance criterion: the app runs without errors or crashes while the device's OS-level power-saving mode is active.

**Security**
Passkey-first, per FR19. No password-as-sole-factor and no SMS OTP at any point. Where a platform's passkey plugin proves too immature, fall back to a magic-link session rather than blocking the user.

**Portability**
One Flutter codebase, four targets. Avoid platform-specific forks except where unavoidable.

**Open data / open source bias**
Prefer high-social-worth open-source libraries and open datasets (OSM, GEDTM30, Open-Meteo, Nominatim) over proprietary services wherever a viable option exists.

\---

## 5\. Technology Requirements (Learning Objectives)

The stack is a project goal, not an implementation detail. This section is first-class.

### 5.1 Routing Core — Python + OSMnx

**Learning goal**: OSMnx graph construction (`graph\\\_from\\\_place`/`graph\\\_from\\\_bbox`), custom edge weighting functions, and shortest-path variants (Dijkstra/A\*) applied to real-world constraints.

**Requirements**:

* Graph caching uses OSMnx's own mechanism (`ox.settings.use\\\_cache` + `save\\\_graphml`/`load\\\_graphml`), not a separately managed `.osm.pbf` extract pipeline — one tool for both fetch and cache
* **Themes are data, not code.** The five MVP themes (FR1–FR5) are **not five algorithms**. They are five instances of a single `WeightProfile` structure — elevation gain, traffic class, turn count, surface penalty, POI bonus, detour budget — fed to **one** multi-factor scoring function. Flattest is `elevation\\\_gain` strongly negative; most-climbing is the same field strongly positive; most-art populates `poi\\\_bonus` and loosens `detour\\\_budget`. Adding a sixth theme is then a configuration entry, not new code, and there is one scoring implementation to debug rather than five. The custom-weighting exercise — the core "why OSMnx" learning goal — lives in that single function and in the profiles that drive it
* FR4's turn signal scores navigational maneuvers, not curvature (see FR4). This is computed at graph-simplification time, not solve time: OSMnx's `simplify\\\_graph` already collapses interstitial nodes, so a curving road is a *single edge* and its curvature is invisible to the turn counter **by construction** — the requirement falls out of the tool's own model rather than needing a bespoke angle-threshold implementation
* FR13's weighting functions accept weights that **vary by position along the route** (tour default, overridden per day or partial-day segment), not a single global scalar. This must not become a rewrite: the profile is resolved **per edge** via a `weights.at(position)` lookup, which in the FR1–FR5 scalar case simply returns the same profile every time. Build that lookup returning a constant from M1 — then FR13 at M5 is a change to *one function*, and the solver never learns the difference
* **Core allocation (Desktop/Mobile only)**: the client reads `Platform.numberOfProcessors` (Dart) and passes `floor(coreCount / 2)` to the routing core as its processing core limit, so route computation doesn't starve the UI thread and OS tasks. The core count is a **parameter passed in by the caller**, never something the routing library discovers for itself — the library must not know or care where it is running. This does not apply to the server-side instance, whose allocation is a fixed setting tied to the Render instance size

### 5.2 Elevation — GEDTM30 via OpenTopography

**GEDTM30** is a 30m global ensemble digital terrain model already fusing Copernicus DEM, ALOS World 3D, and ICESat-2/GEDI ground points. Because it is a single best-available source, it needs **no fallback elevation service**.

* Raster GeoTIFF tiles fetched per trip bounding box, cached locally, read via `rasterio`
* A data void or failed fetch falls back to a flat-earth assumption (0.0m change) for that coordinate — never stalls, never errors
* CC BY licensed — **attribution required**

**Two sourcing phases**:

|Phase|Mechanism|Rationale|
|-|-|-|
|**MVP** (M1–M5)|Each device calls the OpenTopography API directly under its own free-tier key (FR38)|Works only because MVP has a handful of users. The 50-calls/24h limit makes this **explicitly disposable** — it is not the target architecture|
|**Post-MVP** (M6+)|Shared Render-hosted cache: any tile downloaded by any user is cached server-side and served to every subsequent requester|Aggregate OpenTopography calls stay low regardless of user count. Also enables the packaged **North Carolina** content bundle with **Marion, NC** as the default start, so a user with no downloads still opens to a populated app|

**The interface does not change between these phases — only the location of the data does.**

The client requests elevation for a bounding box through **one interface**, from M1 onward. What varies is solely where that interface resolves the data from:

|Phase|Resolution order|
|-|-|
|MVP|local cache → OpenTopography|
|Post-MVP|local cache → **shared Render cache** → OpenTopography|

The M6 transition therefore inserts a lookup step and changes a base URL. It **must not** require a client rewrite, a change to the routing core's elevation reads, or a second code path maintained alongside the first.

**This indirection is built at M1, before it is needed.** That is deliberate: the alternative — hardcoding direct OpenTopography calls at M1 because M1 has no cache to talk to — buys a client rewrite at M6. The cost of building the seam early is a few hours; the cost of not building it is paid later, under more code, with more to break.

### 5.3 Middle Layer — FastAPI

**Learning goal**: Typed request/response models with Pydantic, dependency injection, async endpoint design, OpenAPI generation as a byproduct of code.

**Requirements**:

* Route generation, trip CRUD, and export endpoints exposed with auto-generated OpenAPI docs
* Long-running route computations demonstrate async/background-task patterns rather than blocking request handling
* Auth endpoints (WebAuthn passkey registration/verification, multi-passkey binding, FIDO2/CTAP hybrid QR authorization, magic-link issuance/consumption, share-token issuance) plus account sync (FR21) and stateless guest compute (FR22)
* **Hosting**: FastAPI service, Postgres, and the Flutter Web static build on **Render** (Starter web service + Starter Postgres + free static site). Chosen for always-on behavior — OSMnx keeps compiled graphs cached in memory, and a cold start would hit a guest's first request hardest — and for fixed, predictable cost under anonymous traffic
* **Tile service**: FastAPI runs the tile-generation pipeline server-side for a requested bounding box, caches the result, and serves it to Web. Bbox-scoped and on-demand — **not a standing global tile server**. The same cache is the origin for Desktop/Mobile's offline tile bundles, so there is one pipeline, not two
* **Elevation cache**: the same cache-once-serve-many model applies to GEDTM30 tiles (§5.2). A distinct cache from basemap tiles, identical pattern
* **Geocoding**: OSMnx's built-in `geocoder.geocode()`, called server-side. This is OSMnx's own wrapper around the Nominatim API — free, keyless, no self-hosted Nominatim/Photon instance needed, no Google dependency. **One unified path for Desktop, Web, and Mobile alike**
* **Guest rate limiting**: in-memory per-IP counter (e.g. `slowapi`) on the single Render instance, using a UAT-calibrated mean+2σ threshold with progressive cool-off. No Redis. A known simplification that only breaks if Render ever needs a second instance. IP-only key, accepting some false-positive risk for guests behind a shared NAT
* **A custom domain is a hard requirement, not a polish item.** Both the Web static build and the API must be served from subdomains of one registered domain — e.g. `app.example.app` and `api.example.app`. **Render's default `\\\*.onrender.com` hostnames cannot be used for the deployed Web client.** `onrender.com` is on the Public Suffix List, which makes `app.onrender.com` and `api.onrender.com` genuinely **cross-site** (not merely cross-origin) — so the session cookie would be a third-party cookie, silently blocked by Safari's ITP and Firefox's Total Cookie Protection. That failure is invisible in Chrome during development and surfaces as unexplained session dropouts for real users. Two subdomains of one registered domain are **same-site**, which removes the problem entirely rather than mitigating it
* **Web session**: `HttpOnly; Secure; SameSite=Lax` cookie scoped to the shared parent domain (`Domain=.example.app`). Because both surfaces are same-site, this is a **first-party** cookie: no `SameSite=None`, no third-party-cookie exposure, no CORS credentialed-request configuration, and no origin-allowlist to misconfigure. **Session tokens are never stored in `localStorage` or IndexedDB** — those are readable by any XSS, whereas an `HttpOnly` cookie is not. Bearer-token-in-web-storage is explicitly rejected as a session mechanism
* *Stretch*: WebSocket/SSE endpoint streaming route-generation progress

### 5.4 Client — Flutter/Dart

**Learning goal**: one Dart codebase, four build targets, with a real understanding of where platform-specific code is unavoidable (background location, offline storage, map rendering differences).

**Requirements**:

* Map rendering via `flutter\\\_map` over self-hosted tiles, not a proprietary maps SDK. Desktop/Mobile generate locally per trip bbox; Web fetches from the Render cache (§5.3)
* Local persistence (`sqlite`/`drift`) for offline trip storage — core to FR16/FR17, not polish
* Biometric passkey integration (WebAuthn/`passkeys` plugin) with a shared auth flow across mobile and desktop rather than per-platform bespoke logic — **the hardest cross-platform-parity test in the app**
* Layer visibility (FR8) as toggleable `flutter\\\_map` layers keyed to OSM tag categories, not a hardcoded layer set
* Output/integration plugins are Flutter-side packages holding their own OAuth tokens (§3.5)

### 5.5 Explicit Non-Goals

* No native iOS/Android modules beyond what Flutter plugins provide, unless a capability (e.g. background GPS) forces it
* No infrastructure/DevOps learning track (no Kubernetes, no cloud-native deploy) — local-first keeps the ops surface small

\---

## 6\. Design \& UX Principles

* **Goal-driven planning is the primary interaction**, not a filter bolted onto a generic map. Theme selection is a first-run decision, never buried in settings
* **Setting the start point is the first action in every flow** (FR34) and must be frictionless — search, map tap, or current location, never a coordinate-entry chore
* **Loops are the path of least resistance.** Loops > point-to-point > out-and-back, per the Weekend Cyclist persona. Route shape is chosen independently of theme (FR35), with loop pre-selected
* **A user's work is never silently lost at a boundary.** Signing in offers to bring guest work along (FR37); a version conflict lets the user keep both (FR32); saved trips live in one manageable library (FR36)
* **Surface type and traffic level are always visible on a route**, not hidden behind a details screen
* **Offline is a first-class state, not degraded UX.** Quiet, passive, glanceable status — never prompts, toasts, or modals (§4.4)
* **Map content is opt-in and user-configurable.** The default view doesn't force every rider through menus for POI categories irrelevant to them
* **Guest use is first-class for what it supports, not a crippled trial.** Login prompts appear only at a real capability boundary (saving to an account, cross-device access, plugin features) — never preemptively
* **Parity is a direction of travel, not a pass/fail bar.** Where a real behavioral difference exists (Web is online-only; the installed apps work offline), state it plainly rather than papering over it with a parity claim
* **Indoor/Outdoor contrast is one adaptive system, not a manual toggle.** The app senses context (device type, viewport, and where practical, ambient light or OS light/dark) and defaults intelligently — Mobile defaults to Outdoor, Desktop/Web to Indoor. A manual switch exists only as an override when the automatic read is wrong (e.g. planning from a laptop at a sunny trailhead). An override is a synced, account-level preference; the automatic default still evaluates fresh per surface

\---

## 7\. Risks \& Mitigations

|Risk|Prob.|Impact|Mitigation|
|-|-|-|-|
|OSMnx multi-factor weighting across all five themes is harder than expected (elevation/POI/surface data sparse or inconsistent in OSM)|High|Medium|Build and validate the elevation pipeline and POI-tag scoring within M1, before the API/client layers depend on them|
|Chasing full four-target parity balloons scope|High|Medium|Parity is a direction of travel, not a contract (§6). Sequence targets: Desktop → Web → Mobile|
|Biometric passkey support has uneven Flutter plugin maturity across Desktop vs. Mobile|Medium|High|Spike passkey auth early (before M5). Where a platform's support is too immature, fall back to the magic-link session that already serves as the new-device and recovery path|
|Segment-varying weighting (FR13) turns route scoring into a per-position function instead of a scalar|Medium|Medium|Resolve the weight profile **per edge** via `weights.at(position)` from M1, returning a constant in the FR1–FR5 scalar case (§5.1). FR13 then changes that one lookup, not the solver. Building the scalar case *without* this seam is what would turn FR13 into a rewrite|
|The M6 elevation-cache transition forces a client rewrite because M1 hardcoded direct OpenTopography calls|Medium|Medium|Build the elevation interface at M1 (§5.2), before there's a cache to talk to. M6 then inserts a lookup step and changes a base URL. Cost of the seam now: a few hours. Cost of skipping it: a rewrite under more code, later|
|The MVP direct-call elevation flow (FR38) exhausts OpenTopography's 50-calls/24h free-tier limit as users grow even modestly|Medium (rises with users)|Medium|Accepted as a **known throwaway limitation** — FR38 is scoped to a handful of users by design. The M6 shared cache (§5.2) removes it entirely|
|Coordinate-to-tile management and elevation data voids in the routing core|Medium|Medium|Flat-earth fallback (0.0m) per coordinate so routing never stalls. GEDTM30 has no secondary network fallback by design — it's already a single best source|
|Self-hosted tile pipeline adds tooling overhead beyond app code; Web has no local generation path|Medium|Medium|Scope to per-trip bbox generation, not a standing tile server. Web fetches from the bounded Render cache (§5.3). Elevation gets its own distinct cache under the same pattern|
|Packaging North Carolina content into the binary (post-MVP) grows install size|Medium|Low|Accepted trade-off for a populated app on first open with zero downloads. FR39 (pruning) bounds ongoing storage growth, though not binary size|
|Local OSM extract size/performance on mobile devices|Medium|Medium|Scope offline downloads to a per-trip bounding box, not full regional extracts|
|Guest-tier compute is reachable by anonymous traffic, creating a cost/abuse surface|Medium|Medium|In-memory per-IP rate limiting (§5.3). Guest sessions stay fully stateless server-side, so abuse can't accumulate persistent cost. Browser-local guest storage never touches the server and adds no surface|
|Web's session depends on a custom domain being registered and configured. Deploying on Render's default `\\\*.onrender.com` hostnames would silently break sessions in Safari and Firefox (third-party cookie blocking) while appearing to work in Chrome|Low|High *(if missed)*|Custom domain is a **hard prerequisite for M6**, not a launch-day task (§5.3). Register it before Web auth work starts. Verify session persistence in Safari and Firefox — not only Chrome — as an M6 exit criterion. Same-site cookies also remove the CORS-credentialed-request surface entirely, so the "overly permissive origin allowlist" vulnerability class no longer exists to be misconfigured|
|Cross-device sync (FR21) introduces conflict resolution the app never needed while purely local|Medium|Medium|FR32's explicit version check at open *and* save. No silent last-write-wins. Revisit per-field merge only if the whole-trip choice proves inadequate — avoid a speculative CRDT system|
|Rider profile (FR40) introduces sensitive personal data (emergency contact, home location) the app hasn't stored before|Medium|Medium|FR41's field-level, opt-in, least-shared-by-default sharing model. A planner never sees a sensitive field without the rider explicitly checking it|
|Output/integration plugins hold third-party OAuth tokens client-side, and each platform's API drifts independently — N maintenance relationships instead of one|Medium (rises per integration)|Medium/High|Platform-appropriate secure storage (Keychain/Keystore), never the trip-data layer. Curate a small integration list rather than opening a marketplace, so drift stays bounded|
|Desktop/Mobile's hosted-service touchpoints could drift into a general multi-tenant backend|Medium|Medium|Scope each exception separately: auth + share-token brokering (FR20); per-account sync only (FR21); stateless compute only (FR22). Never merge into one general-purpose service|
|Plugin features (FR27/FR28) depend on the metered Google Street View Static API and `ffmpeg` — unlike anything else in the stack|Low (unscoped)|Low|Deliberately deferred. Confirm whether FR27 needs live Street View or can use an open alternative (e.g. Mapillary) before scoping; if both need it, treat as one shared cost/key risk|

\---

## 8\. Milestones

Ordered by dependency, not calendar-dated — this is a solo project.

|#|Milestone|Deliverable|Validates|
|-|-|-|-|
|**M1**|Routing spike|OSMnx generates routes for all five themes (FR1–FR5) between two points from a local OSM extract, including the GEDTM30 elevation pipeline via direct OpenTopography calls. Two seams are built here even though M1 doesn't yet need them: the **elevation interface** (§5.2 — so M6's shared cache is a config change, not a rewrite) and the **`weights.at(position)` lookup** (§5.1 — returning a constant now, so FR13 at M5 is a one-function change)|Core routing feasibility + elevation sourcing, plus the two seams that keep M5 and M6 cheap|
|**M2**|API wrap|FastAPI returns M1's five theme routes as JSON with OpenAPI docs (FR6)|FastAPI learning goal|
|**M3**|Desktop client + tiles|Flutter Desktop app renders routes on self-hosted tiles with toggleable layers (FR7, FR8); start/destination selection (FR34); route shape (FR35); first-start region download (FR38); Desktop data pruning (FR39); per-day turn-by-turn cue sheet (FR44); unsatisfiable-constraint explanation (FR43)|Flutter + client-server integration, tile pipeline, cold-start content|
|**M4**|Export|All five themes export as GPX/TCX/FIT, verified in RideWithGPS (FR9)|**MVP complete** (§3.3)|
|**M5**|Multi-day trips|Daily splitting (FR11), waypoints (FR10), surface scoring (FR12), sliding-scale weighting (FR13), lodging from OSM tags (FR14), route alternatives \& variants (FR42), group-size-aware planning (FR46), Historical Weather via Open-Meteo (FR15) — surfaced on Desktop first|P1 trip logistics|
|**M6**|Accounts, sync \& Web|**Prerequisite: custom domain registered and configured** (§5.3) — Web auth cannot ship on `\\\*.onrender.com`. Then: passkey auth (FR19); sharing (FR20); Flutter Web (FR18); cross-device sync (FR21) with version-check reconciliation (FR32); trip library (FR36); guest→account claim (FR37); guest tier with rate limiting (FR22); **the shared Render elevation/tile cache and packaged NC bundle, superseding FR38** (§5.2). **Exit criterion: session persistence verified in Safari and Firefox, not only Chrome**|P1 sharing/sync. Web precedes Mobile because both sync and the guest tier depend on it|
|**M7**|Mobile + offline|Android/iOS builds (FR17); offline trip download (FR16); Weather Forecast ships across Desktop, Web, and Mobile simultaneously (FR15); Mobile data pruning (FR39); in-ride live navigation with cue sheet and GPS-loss graceful degradation (FR45)|P1 mobile parity + forecast parity|
|**M8**|Content layer|POI narration (FR24), crowd-sourced feedback (FR25), GeoJSON export (FR26)|P2 features|
|**M9+**|Plugins|Plugin infrastructure, then individual plugins (FR27, FR28, FR30, FR31, FR33) as each is taken up|Unscoped — see §3.5|

\---

## 9\. Open Questions

|#|Question|Blocking|
|-|-|-|
|1|What's the concrete tile-generation tool/workflow for self-hosted tiles (`tilemaker` → MBTiles, or an alternative)? MVP narrows the near-term need — FR38 ships three fixed whole regions, not per-trip bbox generation — so the per-trip pipeline is a post-MVP question|M6 (post-MVP tile pipeline). Not M3|
|2|Does the plugin architecture need a formal interface/SDK spec before the first plugin ships, or does the first plugin define the interface by example?|M9|
|3|Which indoor ride simulators are actually in scope for output plugins (Zwift, TrainerRoad, RGT, others)?|M9|

**Note**: §3.4 states no monetization of the core app. Shipping a *paid* plugin would need that statement formally revisited — flagged, not yet resolved, and not blocking until a paid plugin is actually scoped.

\---

## Appendix: Reference

* Full feature list and persona detail: `Cycle Tour Planner.md`
* **Architecture design**: to be rebuilt. The decisions in §3.2, §4.4, §5, and §7 are the inputs to that new design pass

