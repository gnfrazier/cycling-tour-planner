# Cycle Tour Planner — Product Requirements Document

**Status**: Draft
**Author**: Greg Frazier
**Date**: 2026-07-08
**Source spec**: `Cycle Tour Planner.md`

\---

## 1\. Executive Summary

**Problem**: Existing cycle route planners (RideWithGPS, Komoot, Strava) optimize for logging and social sharing, not for planning around a *theme or constraint* — flattest route, least traffic, most art, fewest turns — or for multi-day trip logistics like lodging, water stops, and elevation budgets per day.

**Proposed Solution**: A personal, local-first route planning application that generates routes against explicit goals (traffic, surface, elevation, points of interest) and supports multi-day trip planning with offline mobile use.

**Secondary purpose**: This project is explicitly a **learning vehicle**. The technology stack (FastAPI, OSMnx, Flutter/Dart across four targets) is fixed as a project goal in itself, not chosen purely for product fit. Architecture decisions should favor hands-on exposure to these tools over the fastest path to shipping.

**Success Metrics**:

* A route can be generated end-to-end locally (OSMnx → FastAPI → Flutter client) for all five MVP theme types (flattest, most climbing, lowest traffic, fewest turns, most art/history)
* Flutter client builds and runs on at least two of the four targets (e.g. Desktop + Android)
* GPX/TCX/FIT export from a generated route opens correctly in RideWithGPS
* Personal usability: the builder (Greg) uses it to plan one real ride

\---

## 2\. Problem Definition

### 2.1 Customer Problem

* **Who**: Four personas — Professional Tour Planner, Individual Weekend Outing Cyclist, Day Tripper, and Guest Rider (no account) (detail in §4.1)
* **What**: No single tool lets a rider plan routes around a specific goal (flattest, least traffic, most art/history, fewest turns) *and* handle multi-day logistics (lodging, water, weather, per-day mileage/elevation caps) — and a rider who isn't ready to install anything or create an account should still be able to use the core of it
* **When**: Pre-trip planning, ranging from a single afternoon loop to multi-week point-to-point tours
* **Where**: Desktop for deep planning sessions, mobile for on-route navigation and offline use
* **Why**: Mainstream tools are built around segment-chasing and social feed, not goal-driven route generation or trip-level logistics
* **Impact of not solving**: Manual, spreadsheet-and-map planning; no offline-safe navigation; no thematic routing (art tours, safest roads, lowest traffic)

### 2.2 Context

This is a personal project, not a commercial product. There is no market sizing, competitive displacement strategy, or revenue goal — the "business case" is personal utility plus deliberate skill-building in geospatial routing (OSMnx), API design (FastAPI), and cross-platform app development (Flutter).

\---

## 3\. Solution Overview

### 3.1 Proposed Solution

A three-tier system:

1. A **local-first routing core** in Python using OSMnx over OpenStreetMap data, capable of generating routes scored against configurable goals (elevation, traffic, surface, points of interest, turn count).
2. A **FastAPI middle layer** exposing routing, trip, and content operations to clients over HTTP, including account-holder trip sync and a narrower, stateless compute path for unauthenticated guest sessions (see §4.4).
3. A **Flutter/Dart client** shared across Android, iOS, Desktop, and Web, capable of working fully offline on mobile once trip content is downloaded. Web supports both a full-parity signed-in mode (syncing like the other targets) and a thin, unauthenticated guest mode with no local persistence (see §4.1, §4.4).

### 3.2 In Scope (MVP)

|Feature|FR|Priority|
|-|-|-|
|Route generation optimized for the flattest theme (minimize elevation gain)|FR1|P0|
|Route generation optimized for the most-climbing theme (maximize/target elevation gain)|FR2|P0|
|Route generation optimized for the lowest-traffic theme|FR3|P0|
|Route generation optimized for the fewest-turns theme|FR4|P0|
|Route generation optimized for the most-art/history theme (POI/tag-based)|FR5|P0|
|FastAPI endpoint(s) wrapping the OSMnx routing core|FR6|P0|
|Flutter client (Desktop first) that requests a route and renders it on a map|FR7|P0|
|User-configurable map layers/tags (landmarks, POIs, parks, construction, etc.)|FR8|P0|
|GPX/TCX/FIT export of a generated route|FR9|P0|
|Waypoint/checkpoint insertion before routing|FR10|P1|
|Set min/max daily mileage for multi-day trip splitting|FR11|P1|
|Road surface tagging and surface-based filtering|FR12|P1|
|Sliding-scale weighting for elevation gain and surface preference, scoped to whole tour / single day / partial day|FR13|P1|
|Lodging/campground data along a route, sourced from OpenStreetMap tags|FR14|P1|
|Trip-dated weather: historical/seasonal norms on desktop, 10-day/hourly forecast on mobile|FR15|P1|
|Offline package: download a trip's map + content for offline use on mobile|FR16|P1|
|Android/iOS builds from the same Flutter codebase|FR17|P1|
|Flutter Web build reaching full planning parity with Desktop, not just route viewing|FR18|P1|
|Account system with biometrics-first passkey auth (Face ID/Touch ID/Windows Hello) + magic-link device registration|FR19|P1|
|Shared routes/trips between users (e.g. tour planner → client)|FR20|P1|
|Account holder's own trips sync across their signed-in devices (desktop, mobile, web)|FR21|P1|
|Unauthenticated guest access to core routing, GPX/TCX/FIT export, and weather via the web app, with no account and no server-side storage|FR22|P1|
|"Building/architectural interest" themed tours using OSM tagging|FR23|P2|
|Audio narration of points of interest during a route|FR24|P2|
|Crowd-sourced route/road/POI feedback with public/private visibility|FR25|P2|
|Full trip export as GeoJSON with attributes|FR26|P2|
|Streetview-style imagery during planning|FR27|P2|
|Desktop-only Street View hyperlapse preview via streetwarp-cli|FR28|TBD|
|Rider skill-profile-based route/segment suggestions|FR29|P3 (stretch)|
|Route/segment suggestions weighted toward frequently-cycled bike routes, greenways, and rail trails|FR30|TBD (needs definition)|
|Route popularity/heatmap-style data as a routing input|FR31|TBD (needs definition)|

### 3.3 Out of Scope (for now)

* Server-hosted, multi-tenant deployment of the routing/trip-planning core as the default — route computation and trip data stay local-first and client-side for the common case. The explicit exceptions are: a minimal hosted service for passkey/magic-link auth and share-token brokering (FR19/FR20); account-holder cross-device trip sync, scoped to that account's own data (FR21); and stateless live compute for unauthenticated guest sessions, which stores nothing server-side (FR22) — see §4.4, §5.2, §7
* Social feed, following, or segment leaderboards
* Payment/monetization of any kind
* Real-time turn-by-turn voice navigation (audio POI narration is in scope; nav guidance is not, initially)
* Non-cycling activity types (running, driving)

### 3.4 MVP Definition

**Core**: Given a start location, generate a route recommendation for each of the five MVP themes — flattest (FR1), most climbing (FR2), lowest traffic (FR3), fewest turns (FR4), and most art/history (FR5) — via OSMnx, serve them through FastAPI, render them in a Flutter Desktop client with self-hosted tiles, and export any of them as GPX, TCX, or FIT.
**Success criteria**: A real route Greg would actually ride comes out the other end for at least the flattest theme, and opens cleanly in RideWithGPS; the other four themes are generated and rendered correctly even if not all are personally ridden before MVP sign-off.
**Learning goals validated by MVP**: writing non-trivial OSMnx custom weighting functions across distance, elevation, traffic-class, turn-count, and POI-tag signals; local-first elevation sourcing (SRTM primary, open-elevation fallback); a working FastAPI service with typed request/response models; a Flutter app that calls a local API, renders self-hosted map tiles, and renders a route/layer.

### 3.5 Future Phase — Streetview Hyperlapse Preview (TBD, Desktop only)

A final phase, after all other milestones (see M9 in §8), to host or integrate with [streetwarp-cli](https://github.com/pelmers/streetwarp-cli) — a CLI tool that stitches Google Street View imagery along a GPX track into a hyperlapse video. This would let a planner generate a visual preview "drive/ride-through" of a planned route.

* **Scope**: Desktop only — not mobile, not web
* **Status**: Intentionally not designed yet. Implementation approach (self-host the CLI vs. shell out to it vs. a from-scratch reimplementation), how a route in this app maps to streetwarp-cli's GPX input, API-key/credential handling for the Street View Static API, and the UI/interaction for triggering and viewing a hyperlapse are all **TBD**
* **Known constraint from the upstream tool**: it depends on a Google Maps API key with Street View Static API billing enabled, and on `ffmpeg` — both are dependencies this project hasn't otherwise needed, which is part of why this is scoped to the very end rather than folded into an earlier milestone
* **Related**: FR27 (general streetview-style imagery during planning, not a hyperlapse) is scheduled adjacent to this phase (M9) since it likely shares this section's Street View Static API dependency and billing concern — see §7

\---

## 4\. User Stories \& Requirements

### 4.1 Personas (from spec)

**Professional Cycling Tour Planner**

* Optimizes logistics for clients: lodging contacts along the route, restrooms/water at rest stops, historical/seasonal weather by trip date
* Sets distance/day, min/max elevation gain, wind influence, surface parameters (paved/gravel/off-road/single-track)
* Plans multi-day point-to-point, loop, or stem-and-loop trips
* Starts/ends near major cities for airport access
* Wants frequently-cycled routes, bike routes, greenways, rail trails; wishes for Strava heatmap-style data
* Wants routes rich with local history, art, murals, side trips, restaurants, and local events
* Wants group skill-profile-aware route/segment suggestions

**Individual Weekend Outing Cyclist**

* Plans single-destination or small-overnight trips for a long weekend
* Prefers low-cost state/national park campsites
* Prefers convenience stores/coffee shops/cafes as rest stops
* Avoids cities; favors rural routes and small towns even at the cost of extra miles
* Strongly prefers loops; out-and-back is least preferred; point-to-point is interesting but logistically harder
* Cares about surface type, may restrict to one extreme; seeks adventure, overlooks, waterfalls, vistas

**Day Tripper**

* Round-trip only (same start/end point)
* No route-type preference
* Primarily mileage- and climb-driven, but wants a destination to anchor the ride

**Guest Rider (no account)**

* Uses the web app without creating an account — either a Professional Tour Planner's client who doesn't want to install anything, or a first-time visitor trying the product before committing to an install
* Can run all five MVP routing themes, export GPX/TCX/FIT, and check weather, entirely unauthenticated
* Cannot view streetview-style imagery/hyperlapse or save/persist a trip — both require logging in
* Sessions are fully ephemeral: nothing is stored server-side; closing the tab without exporting loses the work

### 4.2 Representative User Stories

```
As a Day Tripper
I want a "flattest route" option that minimizes total elevation gain from my start point
So that I can pick a ride that matches an easy-effort day

Acceptance Criteria:
- \[ ] Returned route's total elevation gain is at or near the minimum achievable within the requested distance range
- \[ ] Route uses local SRTM elevation data as the primary source, falling back to open-elevation.com only for missing/imprecise tiles
- \[ ] Route remains a valid, rideable path (no off-road/unrideable segments) even when elevation is heavily weighted
```

```
As a Weekend Outing Cyclist
I want a "most climbing" option that maximizes elevation gain within my distance budget
So that I can use the ride as a hill-training day

Acceptance Criteria:
- \[ ] Returned route's total elevation gain is at or above a configurable minimum-climbing target where a routing alternative exists
- \[ ] The route still respects the rider's surface and distance constraints, not climbing alone
```

```
As a Weekend Outing Cyclist
I want to generate a loop route that avoids cities and prioritizes low traffic
So that I can ride rural roads without manually stitching together a route

Acceptance Criteria:
- \[ ] Route returned is a loop (start == end)
- \[ ] Route avoids road segments above a traffic-class threshold — set as a global user default and optionally overridden per route
- \[ ] Route stays outside city boundaries where a rural alternative exists within a detour budget — set as a global default (in both miles and minutes) and optionally overridden per route (also in both miles and minutes)
```

```
As any persona
I want a "fewest turns" option
So that I can ride a simpler route with less need to check directions

Acceptance Criteria:
- \[ ] Returned route has the lowest turn count achievable within the requested distance/theme constraints
- \[ ] A "turn" is defined consistently (e.g. a heading change above a configurable angle threshold) and documented
```

```
As a Professional Tour Planner
I want a "most art/history" option that favors roads passing OSM-tagged artwork, murals, and historic sites
So that I can build a themed cultural tour for clients

Acceptance Criteria:
- \[ ] Returned route is scored/ranked by count or density of relevant OSM tags (e.g. tourism=artwork, historic=\*) encountered along the way, not just distance
- \[ ] Route remains within a configurable maximum-detour budget relative to the shortest path
```

```
As a Weekend Outing Cyclist
I want to turn off map layers I don't care about (e.g. construction) and turn on ones I do (e.g. parks)
So that the map isn't cluttered with tags irrelevant to how I ride

Acceptance Criteria:
- \[ ] Available OSM tag categories (landmarks, POIs, parks, construction, etc.) are shown as toggleable layers, not buried in a settings submenu
- \[ ] Layer visibility choices persist across sessions
- \[ ] Turning a layer off removes it from the map without requiring a reload/re-route
```

```
As any persona
I want to export a planned route as a GPX, TCX, or FIT file
So that I can load it into RideWithGPS or my bike computer

Acceptance Criteria:
- \[ ] Exported GPX validates against the GPX 1.1 schema
- \[ ] Exported TCX validates against the Garmin TrainingCenterDatabase schema
- \[ ] Exported FIT validates against the Garmin FIT SDK's course/route message format
- \[ ] Track points, elevation, and waypoints are present in all three formats
- \[ ] Files open without error in RideWithGPS
```

```
As a Professional Tour Planner
I want to insert waypoints/checkpoints that a generated route must pass through
So that I can guarantee a route hits client-requested stops (e.g. a specific lunch spot or overlook)

Acceptance Criteria:
- \[ ] Route generation honors all inserted waypoints in the order specified
- \[ ] Route still optimizes for the selected theme between waypoints, not just nearest-path stitching
- \[ ] Waypoints can be added, reordered, or removed before a route is (re)generated
```

```
As a Professional Tour Planner
I want to set min/max daily mileage and elevation caps for a multi-day trip
So that the system splits a long route into rider-appropriate daily segments

Acceptance Criteria:
- \[ ] Trip is split into days respecting min/max mileage constraints
- \[ ] Each day's elevation gain stays under the configured cap where a routing alternative exists
- \[ ] Overnight points align with lodging/campsite data where available
```

```
As a Weekend Outing Cyclist
I want to restrict or bias routing toward a specific road surface (e.g. gravel-only, paved-only)
So that I can match the ride to my bike and skill level

Acceptance Criteria:
- \[ ] User can set a surface preference from "avoid" to "prefer" on a sliding scale, or a hard restriction to a single surface type
- \[ ] Route generation respects the restriction where a valid path exists, and clearly reports when it cannot be honored without a large detour
```

```
As a Professional Tour Planner
I want to weight elevation gain and surface preference on a sliding scale, for the whole tour, a single day, or part of a day
So that I can front-load climbing on day 1 while riders are fresh, and favor gravel through day 3 where the scenic unpaved terrain is worth the detour

Acceptance Criteria:
- \[ ] Elevation-gain and surface-type preference can each be set on a sliding scale (e.g. avoid ↔ prefer)
- \[ ] A weighting can be scoped to the whole tour, one full day, or a partial-day segment
- \[ ] Day- or segment-level weights override the tour-level default only for that scope, without requiring the whole trip to be re-planned from scratch
```

```
As a Professional Tour Planner
I want to see lodging and campground options along a multi-day route, and expected weather for each day's date
So that I can book overnight stays and set client expectations for conditions

Acceptance Criteria:
- \[ ] Lodging/campground POIs sourced from OSM tags are shown near each day's endpoint
- \[ ] Desktop view shows historical/seasonal weather norms for the trip's planned dates when planning far in advance
- \[ ] Mobile view shows a 10-day/hourly forecast for upcoming days as the trip date nears, aligned to each day's planned location, not just the trip's start point
```

```
As a mobile user on a multi-day tour
I want previously-downloaded trip content to work with no network connection
So that I can navigate and view POI info in areas with no cell signal

Acceptance Criteria:
- \[ ] Route, map tiles, and POI content for a trip can be downloaded in advance
- \[ ] App functions with zero errors in airplane mode for a downloaded trip
- \[ ] No feature silently fails without user-visible offline messaging
```

```
As any account holder
I want to authenticate with a passkey (Face ID/Touch ID/Windows Hello)
So that I can access my trips securely without managing a password

Acceptance Criteria:
- \[ ] New devices register via a passwordless magic link, then bind a platform passkey
- \[ ] Returning sessions authenticate via biometric passkey with no password or SMS OTP prompt at any point
- \[ ] The auth flow behaves identically in shape (not necessarily UI) across mobile and desktop
```

```
As a Professional Tour Planner
I want to share a planned trip with a client
So that they can view the route and its details without needing to recreate it

Acceptance Criteria:
- \[ ] A share action produces a link/token the recipient can open to view the trip read-only
- \[ ] The recipient does not need to already have an account to view a shared trip (per Open Question #6; revisit if resolved otherwise)
- \[ ] Revoking a share invalidates the link/token for future access
```

```
As an account holder
I want my trips to stay in sync across my desktop, mobile, and web sessions
So that I can start planning on one device and pick it up on another without re-entering anything

Acceptance Criteria:
- \[ ] A trip edited on one signed-in device appears with the same edits on another signed-in device once both are online
- \[ ] Each device keeps a local working copy and functions normally offline; sync reconciles automatically when connectivity returns
- \[ ] Sync applies only to the account holder's own devices, distinct from sharing a trip with another user (FR20)
```

```
As a Guest Rider with no account
I want to generate and export a route without installing anything or signing up
So that I can try the product, or use a route someone planned for me, with zero setup friction

Acceptance Criteria:
- \[ ] All five MVP routing themes (FR1-FR5) are usable without an account
- \[ ] GPX/TCX/FIT export (FR9) and weather (FR15) work without an account
- \[ ] Streetview imagery/hyperlapse and saving a trip prompt a login rather than silently failing or being hidden
- \[ ] Closing the session without exporting discards the work with no server-side record kept
```

### 4.3 Functional Requirements

|ID|Requirement|Priority|Notes|
|-|-|-|-|
|FR1|System generates a route from a start point optimized for the flattest theme (minimize elevation gain)|P0|Requires the local-first elevation pipeline (SRTM primary, open-elevation fallback), validated at M1|
|FR2|System generates a route from a start point optimized for the most-climbing theme (maximize/target elevation gain)|P0|Shares the elevation pipeline used for FR1; validated at M1|
|FR3|System generates a route from a start point optimized for the lowest-traffic theme|P0|Traffic-class threshold is a global user default with a per-route override; detour budget is likewise configurable in both miles and minutes, globally and per-route|
|FR4|System generates a route from a start point optimized for the fewest-turns theme|P0|"Turn" defined via a configurable heading-change threshold|
|FR5|System generates a route from a start point optimized for the most-art/history theme (OSM `tourism=\*`/`historic=\*` tags)|P0|Distinct from FR23 (P2), which layers richer curated content on top of this base theme|
|FR6|System exposes route generation via a FastAPI endpoint with typed request/response schemas|P0||
|FR7|Client renders a generated route on a map|P0|Desktop first|
|FR8|User can toggle visibility of OSM tag categories as map layers (landmarks, POIs, parks, construction, etc.), configurable per-user to keep the UI to only what's relevant to them|P0|First-iteration requirement, not deferred|
|FR9|System exports a route as a valid GPX, TCX, or FIT file, user's choice of format|P0||
|FR10|User can insert waypoints/checkpoints that the route must pass through|P1||
|FR11|System supports multi-day trip splitting by min/max daily mileage|P1||
|FR12|Routes can be constrained/scored by surface type (paved/gravel/off-road/single-track)|P1||
|FR13|User can set sliding-scale weights for elevation-gain and surface-type preference, independently scoped to the whole tour, a single day, or a partial day, with day/segment weights overriding the tour default for that scope only|P1|Depends on FR11 (multi-day splitting) for day/partial-day scoping|
|FR14|System surfaces lodging and campground locations along a route/trip, sourced from OpenStreetMap tags (e.g. `tourism=hotel`, `tourism=camp\_site`, `tourism=guest\_house`)|P1|Depends on FR11 for per-day overnight-point alignment; OSM-only for v1 — see Open Questions re: a dedicated lodging/campsite service|
|FR15|System displays trip-dated weather: historical/seasonal averages on desktop for long-range planning, and a 10-day/hourly forecast on mobile as the trip date nears — both aligned to each day's planned location and date, not just the trip's start point or the current date|P1|Depends on FR11 for per-day date alignment; desktop historical view targeted for M5, mobile forecast view ships alongside the mobile client at M7; requires a new external weather data service — see Open Questions|
|FR16|User can download a trip's map, route, and content for offline use|P1|Mobile targets|
|FR17|Android and iOS builds run from the shared Flutter codebase with feature parity for offline trips|P1||
|FR18|Web build from the shared Flutter codebase reaches full planning parity with Desktop — waypoints, multi-day logistics, sliding-scale weighting, lodging, and weather — not just route viewing|P1|Extends FR7 (Desktop) and FR17 (Android/iOS) to a fourth full-parity target; sequenced at M6 rather than bundled with mobile, since guest access (FR22) and cross-device sync (FR21) both depend on it existing|
|FR19|App authenticates users across mobile, desktop, and web via a unified, biometrics-first passkey flow (Face ID, Touch ID, Windows Hello); initial device registration falls back to a cryptographically secure, passwordless magic link — no password-only or SMS OTP flows at any point|P1|Enables route sharing (FR20) and cross-device sync (FR21)|
|FR20|Account holder can share a trip/route with another user (e.g. tour planner → client), with the recipient able to view it without recreating it|P1|Requires FR19 accounts; the recipient does not need an account (see §9, resolved)|
|FR21|An account holder's own trips sync across their signed-in devices (desktop, mobile, web) via a canonical per-account copy in the FastAPI/Postgres layer, reconciled with each device's local working copy when online|P1|Depends on FR19 (accounts); distinct from FR20 — same account holder's own devices, not a share to a different person; a new, explicit exception to the local-first principle (§4.4)|
|FR22|Unauthenticated ("Guest Rider") web sessions can run all five MVP routing themes (FR1–FR5), export GPX/TCX/FIT (FR9), and view weather (FR15) without an account; sessions are fully ephemeral with no server-side storage. Streetview imagery/hyperlapse (FR27/FR28) and saving a trip require logging in|P1|New persona — see §4.1; gating streetview behind login also functions as cost control for the metered Street View Static API (§7); depends on FR18 (Web client) existing|
|FR23|System supports "building/architectural interest" themed tours using OSM tagging (e.g. historic=*, tourism=*)|P2|Builds on the OSM-tag scoring introduced by FR5|
|FR24|System plays audio narration for POIs selected during planning|P2||
|FR25|Users can upload images/feedback on routes, roads, intersections, and POIs, with public/private visibility|P2|Requires FR19 accounts, for authorship and public/private visibility control|
|FR26|Full trip (route + content + user contributions) can be exported as GeoJSON with attributes|P2||
|FR27|User can view streetview-style or other point-of-view imagery during planning|P2|May share the paid Street View Static API dependency with FR28 (§3.5) — see risk in §7|
|FR28|System can generate (or hand off to) a desktop-only Street View hyperlapse preview of a route via streetwarp-cli integration|TBD|See §3.5 — implementation and interaction intentionally undecided|
|FR29|System suggests routes/segments based on a group's rider skill profiles|P3|Stretch|
|FR30|System suggests routes/segments weighted toward frequently-cycled bike routes, greenways, and rail trails|TBD|Needs definition — data source (OSM cycle-infrastructure tags vs. a heatmap-style service) and scoring approach undecided; see Open Questions|
|FR31|System incorporates route/segment popularity data (Strava-heatmap-style signal) into route suggestions|TBD|Needs definition — no OSM-native equivalent; would require a new third-party data source, in tension with the open-data/local-first bias (§4.4); see Open Questions|

### 4.4 Non-Functional Requirements

* **Local-first**: Core routing must run without a network connection to any remote service; OSMnx works against locally-cached OSM extracts, and elevation enrichment reads from local SRTM tiles bundled with each trip's bounding box rather than depending on a live network call for the common case. Three explicit exceptions exist, each scoped as narrowly as possible: (1) trip-dated weather (FR15) — historical/seasonal norms can be bundled/cached like elevation data, but live 10-day/hourly forecasts inherently require network access when available, degrading gracefully to cached/historical data offline (see Offline mobile, below); (2) account-holder cross-device sync (FR21) — each signed-in device keeps a local working copy and functions normally offline, with a canonical per-account copy in FastAPI/Postgres reconciled only when online; (3) unauthenticated guest sessions (FR22) — a thin web client with no local store at all, since there's no installed device to be local-first about
* **Offline mobile**: Downloaded trip content must be fully usable with zero errors with no connectivity
* **Power efficiency**: Mobile client should minimize GPS/CPU/network wake-ups during long rides — this is an explicit design constraint, not an afterthought
* **Security**: Biometrics-first passkey auth (Face ID/Touch ID/Windows Hello) unified across mobile and desktop; passwordless magic link is the only fallback, used solely for initial device registration. No password-as-sole-factor or SMS OTP is to be implemented at any point
* **Portability**: One Flutter codebase targets Android, iOS, Desktop, and Web — avoid platform-specific forks except where unavoidable
* **Open data / open source bias**: Prefer high-social-worth open source libraries and open datasets (OSM) over proprietary services where a viable option exists

\---

## 5\. Technology Requirements (Learning Objectives)

This section is first-class, not an implementation appendix, because the technology stack is a project goal, not just a means to an end.

### 5.1 Routing Core — Python + OSMnx

* **Learning goal**: Understand OSMnx graph construction (`graph\_from\_place`/`graph\_from\_bbox`), custom edge weighting functions, and shortest-path variants (Dijkstra/A\*) applied to real-world constraints (elevation, surface, traffic-class tags)
* **Requirement**: Local caching uses OSMnx's own graph caching (`graph\_from\_place`/`graph\_from\_bbox` with `ox.settings.use\_cache` + `save\_graphml`/`load\_graphml`), not a separately managed `.osm.pbf` extract pipeline — keeps the routing core to one tool for both fetch and cache
* **Requirement**: At least one custom multi-factor scoring function per theme (FR1–FR5) must be implemented and documented — this is the core "why OSMnx" exercise
* **Requirement**: Elevation-aware routing is in scope for v1 using a **local-first, dual-source** strategy: local SRTM tiles (`.hgt` or GeoTIFF) bundled with each trip's bounding-box extraction are the primary elevation source during graph compilation, read via a Python raster parsing library (`rasterio` or `srtm.py`). open-elevation.com is used strictly as a **secondary fallback** — only when local tile data for a given coordinate is missing, imprecise, or a data void — with a local cache layer so any coordinate that falls back to the network is never requested twice. This pipeline is required starting at M1, since two of the five P0 MVP themes (FR1, flattest; FR2, most climbing) depend on it directly
* **Requirement**: Elevation-gain and surface weighting functions (FR13) must accept weights that vary by position along the route (tour-wide default, overridden per day or per partial-day segment), not just a single global scalar — this is a meaningfully harder version of the FR1–FR5 custom-weighting exercise

### 5.2 Middle Layer — FastAPI

* **Learning goal**: Typed request/response models with Pydantic, dependency injection, async endpoint design, and OpenAPI schema generation as a byproduct of the code (not hand-written docs)
* **Requirement**: Route generation, trip CRUD, and export endpoints are all exposed through FastAPI with auto-generated OpenAPI docs
* **Requirement**: Long-running route computations (large multi-day trips) should demonstrate FastAPI's async/background-task patterns rather than blocking request handling
* **Requirement**: Auth/account endpoints (passkey registration \& verification per WebAuthn, magic-link issuance/consumption, share-link/token issuance for FR20) live in FastAPI, alongside two related but distinct server-side responsibilities: account-holder cross-device trip sync (FR21) and stateless live compute for unauthenticated guest sessions (FR22) — together these are the parts of the system that are not local-only; see §4.4 for how each stays scoped as narrowly as possible
* **Requirement**: The FastAPI service, its Postgres database, and the Flutter Web static build are hosted on Render (a Starter web service, a Starter Postgres instance, and a free static site) — chosen for always-on behavior, since OSMnx keeps compiled graphs cached in memory and a cold start would hit a guest's first request hardest, and for fixed, predictable cost under anonymous guest traffic rather than usage-based billing
* **Stretch learning goal**: WebSocket or SSE endpoint for streaming route-generation progress to the client

### 5.3 Client — Flutter/Dart (Android, iOS, Desktop, Web)

* **Learning goal**: A single Dart codebase producing four build targets, with a real understanding of where platform-specific code is unavoidable (e.g. background location, offline storage, map rendering backend differences)
* **Requirement**: Map rendering via `flutter\_map` over self-hosted tiles (generated from local OSM extracts, not a third-party hosted tile endpoint) rather than a proprietary maps SDK, consistent with the open-source bias in §4.4 and the offline-bundling need in FR16. The tile-generation step is required starting at M3 (Desktop client) — see §8
* **Requirement**: Local persistence layer (e.g. `sqlite`/`drift` or similar) for offline trip storage — this is core to FR16/FR17, not optional polish
* **Requirement**: Biometric passkey integration (platform authenticator via WebAuthn/`passkeys` plugin) on both mobile (Face ID/Touch ID) and desktop (Windows Hello) targets, with a shared auth flow rather than per-platform bespoke logic — this is the hardest cross-platform-parity test in the app (FR19)
* **Requirement**: Desktop and Web targets are explicitly part of the learning scope, not just "if we get to it." Web goes beyond original route-viewing parity: it's a full planning client for signed-in account holders, including cross-device sync (FR21), and it also supports a distinct unauthenticated guest mode (FR22) — a thin client with no local persistence, calling FastAPI directly for compute rather than using the `drift`/SQLite store the other targets use. Web is sequenced at M6, ahead of the Android/iOS build at M7, since sync and the guest tier both depend on it — see §8
* **Requirement**: Map layer visibility (FR8) is implemented as user-toggleable `flutter\_map` layers keyed to OSM tag categories, with the user's on/off choices persisted locally per-device (not a fixed, hardcoded layer set)

### 5.4 Explicit Non-Goals for the Learning Scope

* No native iOS/Android modules beyond what Flutter plugins already provide, unless a specific capability (e.g. background GPS) forces it
* No infrastructure/DevOps learning track (no Kubernetes, no cloud deploy) — local-first keeps the ops surface intentionally small

\---

## 6\. Design \& UX Principles

* Goal-driven planning is the primary interaction, not a filter bolted onto a generic map — theme selection (flattest, most art, lowest traffic, etc.) should be a first-run decision, not buried in settings
* Loops > point-to-point > out-and-back, reflecting the Weekend Cyclist persona's stated preference — the UI should make loop creation the path of least resistance
* Surface type and traffic level are always visible on a route, not hidden behind a details screen
* Offline state must be visually unambiguous — a user should never be unsure whether a screen will work without signal
* Map content (OSM tags/layers) is opt-in and user-configurable — the default view should not force every rider through menus for POI categories (e.g. construction) that are irrelevant to them
* Guest/unauthenticated use is first-class for what it supports, not a crippled trial — login prompts appear only at an actual capability boundary (saving a trip, viewing streetview imagery), never preemptively before that point

\---

## 7\. Risks \& Mitigations

|Risk|Probability|Impact|Mitigation|
|-|-|-|-|
|OSMnx multi-factor weighting across all five MVP themes is harder than expected (elevation/POI/surface data sparse or inconsistent in OSM)|High|Medium|Build and validate the local-first elevation pipeline (SRTM + open-elevation fallback) and POI-tag scoring for the most-art theme within M1, before the API/client layers depend on them; surface-type weighting (FR12) remains a separate P1 item beyond the five M1 themes|
|Flutter four-target parity balloons scope|High|Medium|Sequence targets — Desktop first (fastest iteration), then Web (concurrent with M6's accounts/sync work, since cross-device sync and the guest tier both depend on it), then Android/iOS|
|Local OSM extract size/performance on mobile devices|Medium|Medium|Scope offline downloads to a bounding box per trip, not full regional extracts|
|Solo project with no deadline pressure risks stalling|Medium|Medium|Anchor scope to the MVP in §3.4, which is deliberately small and demo-able|
|Biometric passkey support (Face ID/Touch ID/Windows Hello) via Flutter has uneven plugin maturity across Desktop vs. mobile|Medium|High|Spike passkey auth early (before M5) rather than at the end; fall back to magic-link-only on any platform where passkey support proves too immature, without blocking sharing|
|open-elevation.com (public, rate-limited) becomes a bottleneck or goes down|Low/Medium|Medium|Now a fallback only — primary elevation comes from local SRTM tiles, so the routing core degrades gracefully rather than depending on the network for the common case; fallback lookups are cached locally so a coordinate is never re-requested|
|Coordinate-to-tile file management and local data voids/missing SRTM tiles within the Python routing core|Medium|Medium|Fall back to open-elevation.com when local data is missing/imprecise; if that also fails, fall back to a flat-earth assumption (0.0m elevation change) for that coordinate so the routing engine never stalls or crashes the UI|
|Self-hosted tile pipeline (generating/serving offline map tiles from local extracts) adds real tooling overhead beyond app code|Medium|Medium|Scope to per-trip bounding-box tile generation (e.g. via a local tool run once per trip), not a standing tile server|
|Server-side exceptions to local-first (auth/share-brokering, cross-device sync, guest compute — FR19–FR22) could drift into a general multi-tenant backend if not kept narrow|Medium|Medium|Scope each exception explicitly and separately rather than merging them into one general-purpose service: auth + share-token brokering only for FR20; per-account sync of that account's own trips only for FR21; stateless compute with no storage for FR22 — see §4.4|
|Segment-varying elevation/surface weighting (FR13) turns route scoring into a per-position function instead of a single scalar, adding real algorithmic complexity|Medium|Medium|Build the single-scalar versions (FR1–FR5) first; treat day/partial-day overrides as an explicit follow-on iteration on the same scoring functions, not a rewrite|
|Unauthenticated guest-tier compute (FR22) is reachable by anonymous traffic, creating a cost/abuse surface the routing core and weather proxy didn't have before|Medium|Medium|Rate-limit guest-tier endpoints (e.g. per-IP throttling) before launch; keep guest sessions fully stateless so abuse can't accumulate persistent server-side cost beyond the compute itself|
|Cross-device sync (FR21) introduces conflict resolution the app never needed while trips were purely local-first (e.g. the same trip edited offline on two devices before either reconnects)|Medium|Medium|Start with a simple, explicit conflict rule (e.g. last-write-wins per trip, surfaced to the user rather than silently resolved); revisit only if that proves inadequate in practice — avoid building a general merge/CRDT system speculatively|
|streetwarp-cli phase (§3.5, FR28) depends on external, possibly-paid Google Street View Static API and `ffmpeg`, dependencies unlike anything else in the stack|Low (it's last)|Low|Left fully TBD by design; revisit feasibility/cost only once it's actually next in line|
|FR27 (streetview-style imagery during planning) may depend on the same paid Google Street View Static API as FR28|Medium|Medium|Confirm whether FR27 needs live Street View imagery or can use a cheaper/open alternative (e.g. Mapillary) before scoping; if it does need the Street View Static API, treat cost/key management as one shared risk with FR28 rather than solving it twice|

\---

## 8\. Milestones (Sequenced, not Dated)

Given this is a solo learning project, milestones are ordered by dependency rather than calendar-dated.

|Milestone|Deliverable|Validates|
|-|-|-|
|M1 — Routing spike|OSMnx generates routes for all five MVP themes (FR1–FR5: flattest, most climbing, lowest traffic, fewest turns, most art/history) between two points from a local OSM extract, including the local-first elevation pipeline (local SRTM primary, open-elevation.com fallback) needed for the flattest/most-climbing themes|Core routing feasibility across all five P0 themes, plus elevation sourcing|
|M2 — API wrap|FastAPI endpoint(s) return M1's five theme routes as JSON with OpenAPI docs (FR6)|FastAPI learning goal|
|M3 — Desktop client + tiles|Flutter Desktop app calls the API and renders routes using self-hosted tiles generated from local OSM extracts, with toggleable OSM tag layers (FR7, FR8)|Flutter + client-server integration, plus tile-pipeline feasibility|
|M4 — GPX export|All five MVP theme routes exportable as GPX, TCX, and FIT, verified in RideWithGPS (FR9)|MVP completion (§3.4)|
|M5 — Multi-day trips|Daily mileage/elevation splitting (FR11; elevation pipeline already validated in M1) + waypoints (FR10) + surface-type scoring (FR12) + sliding-scale elevation/surface weighting (FR13, tour/day/partial-day) + lodging/campground data (FR14) + trip-dated historical weather on desktop (FR15)|P1 trip logistics|
|M6 — Accounts, sync \& Web|Biometrics-first passkey auth (mobile + desktop) with magic-link registration (FR19); share-link flow (FR20); Flutter Web build reaches full planning parity (FR18); account-holder cross-device sync (FR21); unauthenticated guest-tier web access (FR22)|P1 sharing/sync (FR19–FR22) plus the Web milestone, pulled forward from its earlier implicit "last" position since both sync and guest access depend on it|
|M7 — Mobile + offline|Android/iOS builds (FR17), offline trip download (FR16), mobile 10-day/hourly weather forecast (FR15)|P1 mobile parity|
|M8 — Content layer|POI narration (FR24), crowd-sourced feedback (FR25), GeoJSON export (FR26)|P2 features|
|M9 — Streetview imagery \& hyperlapse|Streetview-style imagery during planning (FR27) plus desktop-only streetwarp-cli hyperlapse integration (FR28, TBD)|FR27 grouped here since it likely shares FR28's Street View Static API dependency (§7); hyperlapse implementation deliberately undetermined until this phase starts (§3.5)|

\---

## 9\. Open Questions

### Resolved

1. **OSM extract/caching**: OSMnx's own graph caching (not a separate `.osm.pbf` extract pipeline). See §5.1.
2. **Elevation data source \& fallback behavior**: Local-first, dual-source strategy — local SRTM tiles (`.hgt`/GeoTIFF) bundled with each trip's bounding-box extraction are the primary source, read via `rasterio`/`srtm.py`. open-elevation.com is a secondary fallback used only for missing/imprecise local data or data voids, with results cached locally so a coordinate is never re-requested. If both sources fail for a coordinate, the routing core falls back to a flat-earth assumption (0.0m elevation change) rather than stalling or erroring. Required starting at M1 (FR1, FR2) — see §5.1, §7, §8.
3. **Multi-user/accounts**: Required, not deferred — shared routes are a must-have for the Professional Tour Planner persona. See FR19/FR20, §3.2.
4. **Map tile source**: Self-hosted tiles, generated from local extracts per trip bounding box. See §5.3, §7.
5. **Flutter map package**: `flutter\_map`. See §5.3.
6. **Share vs. sync**: A share (FR20) stays the simple one-way, no-account-needed view case, as originally assumed. An account holder's own cross-device sync is a distinct, separate capability (FR21) rather than something a share implies. Resolved by splitting these into two FRs instead of overloading one — see §4.3.
7. **Account/sync/sharing backend infrastructure**: Render hosts the FastAPI layer, its Postgres database, and the Flutter Web static build (Starter web service + Starter Postgres + a free static site) — see §5.2. Chosen over self-hosting on Greg's own infrastructure for ease of implementation, and because Render's fixed per-instance pricing bounds cost predictably under the anonymous traffic the guest tier (FR22) introduces.

### Follow-up (raised by the above decisions)

8. What's the concrete tile-generation tool/workflow for self-hosted, per-trip offline tiles (e.g. `tilemaker` → MBTiles, vs. another pipeline)? Needed starting at M3 — see §8.
9. What service(s), if any, provide lodging/campground data beyond raw OSM tags (FR14)? Is OSM coverage sufficient, or does the Professional Tour Planner persona need a dedicated lodging/campsite data source to hit a "client-ready" bar?
10. What weather data service will back FR15 (historical averages + live forecast) (e.g. `open-meteo` vs openweathermap)? This is the first non-OSM, non-local external dependency in the core planning flow — how should it interact with the local-first principle (§4.4) and offline behavior?
11. Should cafe/restaurant rest-stops be sourced from OSM tags alone (`amenity=cafe`/`amenity=restaurant`), or does the Professional Tour Planner persona need a richer/curated source (verified hours, reviews) beyond what OSM provides?
12. How is "power efficiency" (§4.4 NFR) actually validated — is there a target metric (battery %/hour, GPS poll interval) and a milestone/test for it, or is this currently just a stated intention with no acceptance criteria?
13. FR30/FR31 (frequently-cycled/greenway/rail-trail preference; popularity/heatmap-style data) are explicitly left for future definition — what data source and scoring approach would even be feasible, and does either require breaking the open-data/local-first bias (§4.4)?
14. What conflict-resolution rule should cross-device sync (FR21) use beyond an initial last-write-wins default — is field-level merge ever needed, or is trip data coarse-grained enough that whole-trip last-write-wins is sufficient indefinitely?
15. What rate-limiting or anti-abuse approach protects the unauthenticated guest-tier compute endpoint (FR22) — per-IP throttling, a proof-of-work/CAPTCHA-style gate, or something else — and at what threshold does it kick in?

\---

## Appendix: Reference

* Full feature list and persona detail: `Cycle Tour Planner.md`
* Architecture summary: `CLAUDE.md`
