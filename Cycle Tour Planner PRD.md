# Cycle Tour Planner — Product Requirements Document

**Status**: Draft
**Author**: Greg Frazier
**Date**: 2026-07-08 (revised 2026-07-10 — Web local-first scope narrowed, see §9 item 16)
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
* **Where**: Desktop and web for deep planning sessions, mobile for quick route creation, modifications to existing multi-day trips, on-route navigation and offline use
* **Why**: Mainstream tools are built around segment-chasing and social feed, not goal-driven route generation or trip-level logistics
* **Impact of not solving**: Manual, spreadsheet-and-map planning; no offline-safe navigation; no thematic routing (art tours, safest roads, lowest traffic)

### 2.2 Context

This is a personal project, not a commercial product. There is no market sizing, competitive displacement strategy, or revenue goal — the "business case" is personal utility plus deliberate skill-building in geospatial routing (OSMnx), API design (FastAPI), and cross-platform app development (Flutter).

\---

## 3\. Solution Overview

### 3.1 Proposed Solution

A three-tier system:

1. A **local-first routing core** in Python using OSMnx over OpenStreetMap data, capable of generating routes scored against configurable goals (elevation, traffic, surface, points of interest, turn count). Local first does not mean local only, Online should be considered the norm while offline usability remains for the supported features. 
2. A **FastAPI middle layer** exposing routing, trip, and content operations to clients over HTTP, including account-holder trip sync and a narrower, stateless (server-side) compute path for unauthenticated guest sessions — guest work-in-progress lives entirely in the guest's own browser, not on the server (see §4.4).
3. A **Flutter/Dart client** shared across Android, iOS, Desktop, and Web, capable of working fully offline on mobile once trip content is downloaded. Web supports both a signed-in mode that aims to come as close to the other targets' planning capability as is practical (syncing like the other targets) and an unauthenticated guest mode that persists in-progress work in the guest's own browser (IndexedDB for route/trip data, localStorage for small preferences) rather than the server — an intentional reversal of the original "thin client, no local persistence" characterization, since the zero-server-storage privacy guarantee was always about server-side storage only, not client-side (see §4.1, §4.4).

### 3.2 In Scope (MVP)

|Feature|FR|Priority|
|-|-|-|
|Route generation optimized for the flattest theme (minimize elevation gain)|FR1|P0|
|Route generation optimized for the most-climbing theme (maximize/target elevation gain)|FR2|P0|
|Route generation optimized for the lowest-traffic theme|FR3|P0|
|Route generation optimized for the fewest-turns theme (fewest navigational maneuvers, not least road curvature)|FR4|P0|
|Route generation optimized for the most-art/history theme (POI/tag-based)|FR5|P0|
|FastAPI endpoint(s) wrapping the OSMnx routing core|FR6|P0|
|Flutter client (Desktop first) that requests a route and renders it on a map|FR7|P0|
|User-configurable map layers/tags (landmarks, POIs, parks, construction, etc.), synced per account and bucketed by size class (large/fullscreen vs. compact/phone) — guests stay per-browser|FR8|P0|
|GPX/TCX/FIT export of a generated route|FR9|P0|
|Waypoint/checkpoint insertion before routing|FR10|P1|
|Set min/max daily mileage for multi-day trip splitting|FR11|P1|
|Road surface tagging and surface-based filtering|FR12|P1|
|Sliding-scale weighting for elevation gain and surface preference, scoped to whole tour / single day / partial day|FR13|P1|
|Lodging/campground data along a route, sourced from OpenStreetMap tags|FR14|P1|
|Trip-dated weather: Historical Weather (historical/seasonal norms) and Weather Forecast (10-day/hourly), both available on Desktop, Web, and Mobile|FR15|P1|
|Offline package: download a trip's map + content (selected map areas with associated geotiff elevation) for offline use on mobile|FR16|P1|
|Android/iOS builds from the same Flutter codebase|FR17|P1|
|Flutter Web build aiming to come as close to Desktop planning parity as practical for a server-backed web client, not just route viewing|FR18|P1|
|Account system with biometrics-first passkey auth (Face ID/Touch ID/Windows Hello), QR cross-device authorization (FIDO2/CTAP hybrid) as the preferred new-device path, multiple passkeys per account, and magic-link as both a device-registration fallback and an explicit account-recovery path|FR19|P1|
|Shared routes/trips between users (e.g. tour planner → client)|FR20|P1|
|Account holder's own trips sync across their signed-in devices (desktop, mobile, web)|FR21|P1|
|Unauthenticated guest access to core routing, GPX/TCX/FIT export, Historical Weather, and the Weather Forecast via the web app, with no account, no server-side storage, and in-progress work persisted in the guest's own browser|FR22|P1|
|"Building/architectural interest" themed tours using OSM tagging|FR23|P2|
|Audio narration of points of interest during a route|FR24|P2|
|Crowd-sourced route/road/POI feedback with public/private visibility|FR25|P2|
|Full trip export as GeoJSON with attributes|FR26|P2|
|Streetview-style imagery during planning — candidate plug-in based feature (proposed, undecided; see §3.6)|FR27|P2|
|Desktop-only Street View hyperlapse preview via streetwarp-cli — candidate plug-in based feature (proposed, undecided; see §3.6)|FR28|TBD|
|Rider skill-profile-based route/segment suggestions|FR29|P3 (stretch)|
|Route/segment suggestions weighted toward frequently-cycled bike routes, greenways, and rail trails|FR30|TBD (needs definition)|
|Route popularity/heatmap-style data as a routing input|FR31|TBD (needs definition)|
|Version-check-on-open and on-save: compare the local/last-loaded trip against the server-stored version both at open and immediately before a save; if the server is newer, notify the user and let them save-as (keep both) or overwrite in place|FR32|P1|
|plug-in based "trip version history" — automatically retain the last 5–10 versions of a trip for rollback|FR33|TBD (future, post-M9)|
|Set the route's start (and destination/waypoints) via location search/geocoding, map tap, or current GPS location|FR34|P0|
|Route shape selection — loop, out-and-back, or point-to-point — chosen independently of the five routing themes|FR35|P1|
|Trip library: list, search, rename, duplicate, and delete saved trips, and view/revoke active shares|FR36|P1|
|Guest → account claim: on first sign-in from a browser holding guest work-in-progress, offer to import that browser-local trip into the account|FR37|P1|

### 3.3 Out of Scope (for now)

* Server-hosted, multi-tenant deployment of the routing/trip-planning core as the default **on Desktop and Mobile** — route computation and trip data stay local-first and client-side for the common case on those two targets. Web is treated differently, by design (revised 2026-07-10 — see `ARCHITECTURE.md` §2 Principle 1/6): Web has always structurally required the hosted API for compute (no browser runs OSMnx offline), so rather than framing Web's hosted dependency as a narrow "exception" to a universal local-first rule, Web is a first-class, conventionally server-backed surface. The hosted service's Desktop/Mobile-facing responsibilities remain narrowly scoped: passkey/magic-link auth and share-token brokering (FR19/FR20), and account-holder cross-device trip sync scoped to that account's own data (FR21). Unauthenticated guest sessions (FR22) still store nothing server-side — that guarantee is a privacy commitment to anonymous users, independent of this change — see §4.4, §5.2, §7
* Social feed, following, or segment leaderboards
* Payment/monetization of any kind (see §3.6 for a proposed plug-in based concept that would conflict with this — flagged, not resolved)
* Real-time turn-by-turn voice navigation (audio POI narration is in scope; nav guidance is not, initially)
* Non-cycling activity types (running, driving)

### 3.4 MVP Definition

**Core**: Given a start location (set via geocoded search, map tap, or GPS — FR34), generate a route recommendation for each of the five MVP themes — flattest (FR1), most climbing (FR2), lowest traffic (FR3), fewest turns (FR4), and most art/history (FR5) — via OSMnx, serve them through FastAPI, render them in a Flutter Desktop client with self-hosted tiles, and export any of them as GPX, TCX, or FIT.
**Success criteria**: A real route Greg would actually ride comes out the other end for at least the flattest theme, and opens cleanly in RideWithGPS; the other four themes are generated and rendered correctly even if not all are personally ridden before MVP sign-off.
**Learning goals validated by MVP**: writing non-trivial OSMnx custom weighting functions across distance, elevation, traffic-class, turn-count, and POI-tag signals; local-first elevation sourcing (SRTM primary, open-elevation fallback); a working FastAPI service with typed request/response models; a Flutter app that calls a local API, renders self-hosted map tiles, and renders a route/layer.

### 3.5 Future Phase — Streetview Hyperlapse Preview (TBD, Desktop only)

A final phase, after all other milestones (see M9 in §8), to host or integrate with [streetwarp-cli](https://github.com/pelmers/streetwarp-cli) — a CLI tool that stitches Google Street View imagery along a GPX track into a hyperlapse video. This would let a planner generate a visual preview "drive/ride-through" of a planned route.

* **Scope**: Desktop only — not mobile, not web. This absence is never silent: a rider who moves from Desktop to Mobile or Web gets a quiet, passively-discoverable, inline note that hyperlapse isn't available on that surface — shown once, not repeated, no interruptive modal — consistent with the offline/quiet-clarity messaging stance (§4.4, §6), applied here to a capability boundary rather than a connectivity one
* **Status**: Intentionally not designed yet. Implementation approach (self-host the CLI vs. shell out to it vs. a from-scratch reimplementation), how a route in this app maps to streetwarp-cli's GPX input, API-key/credential handling for the Street View Static API, and the UI/interaction for triggering and viewing a hyperlapse are all **TBD**
* **Known constraint from the upstream tool**: it depends on a Google Maps API key with Street View Static API billing enabled, and on `ffmpeg` — both are dependencies this project hasn't otherwise needed, which is part of why this is scoped to the very end rather than folded into an earlier milestone
* **Plug-ins framing (proposed, undecided)**: This hyperlapse phase and FR27 (general streetview-style imagery) are candidate plug-in based features, aligned with the proposed plug-in based User concept in §3.6 — both are already login-gated, and the metered, paid Street View Static API dependency makes plug-in based-gating a natural cost control on top of that. This is a proposed direction, not a commitment — see §3.6 for the same monetization tension flagged against §3.3
* **Related**: FR27 (general streetview-style imagery during planning, not a hyperlapse) is scheduled adjacent to this phase (M9) since it likely shares this section's Street View Static API dependency, billing concern, and now plug-in framing — see §7

### 3.6 Future Phase — Plug-in Trip Version History (TBD)

A proposed plugin-in, scheduled after all other milestones including the streetview/hyperlapse phase (see M10 in §8, after M9) — later than §3.5's already-last phase, since it isn't committed at all yet.

* **Scope**: Account holders only (requires FR19/FR21); would automatically retain the last 5 or 10 versions of a trip (exact count undecided) so a user can roll back to a previous revision instead of only the single current version
* **Status**: Proposed/undecided, not committed — a future concept, not MVP. Whether this ships as a paid tier at all is unresolved
* **Known tension**: This is explicitly a monetized, paid-tier feature, which conflicts with the "no monetization of any kind" out-of-scope statement in §3.3. That tension is flagged here, not resolved — if pursued, §3.3 would need to be revisited rather than quietly contradicted
* **Related**: Builds on the version-check-on-open flow (FR32) and cross-device sync (FR21) — the same server-stored trip versions FR32 already compares against would need to be retained across revisions rather than replaced on overwrite. FR27/FR28 (streetview imagery and hyperlapse, §3.5) are also candidate plug-in based features under this same proposed, undecided direction

\---

## 4\. User Stories \& Requirements

### 4.1 Personas (from spec)

**Professional Cycling Tour Planner**

* Optimizes logistics for clients: lodging contacts along the route, restrooms/water at rest stops, Historical Weather by trip date
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
* Can run all five MVP routing themes, export GPX/TCX/FIT, and check Historical Weather and the Weather Forecast, entirely unauthenticated
* Cannot view streetview-style imagery/hyperlapse (candidate plug-in features, proposed/undecided — see §3.5, §3.6) or save a trip to an account — both sit behind a login/account boundary, and streetview specifically may sit behind a plug-in based boundary beyond that if the proposed plug-in strategy is ever adopted
* In-progress work (route/trip, layer toggles, form state) is saved automatically in the guest's own browser — same device, same browser only — so closing the tab, refreshing, or a crash doesn't lose it. Nothing is ever stored server-side: no email, no account, no personal details. That saved state is lost if the user clears browser data or uses private/incognito mode, and never syncs across devices or browsers; export (GPX/TCX/FIT) or signing in are the only ways to keep it anywhere else
* If a guest later signs in or creates an account from the same browser, the app offers to import that in-progress work into the account rather than discarding it (FR37) — the conversion path from anonymous trial to a saved, synced account trip

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
- \[ ] Returned route has the lowest count of navigational maneuvers achievable within the requested distance/theme constraints — not the straightest or least-curved path
- \[ ] A "turn" is defined as a navigational maneuver: leaving the current OSM way/named road for a different one, or negotiating an intersection that requires a decision/maneuver — not a heading-change angle threshold. Staying on the same way as it curves counts as zero turns, however much the road bends
- \[ ] A single continuous road followed for many miles scores as the happy path even if curvy; a route that weaves through many short segments to cover the same distance (e.g. a neighborhood grid, turning every block) scores as the unhappy path, even if each individual segment is straight
- \[ ] The maneuver-based turn definition is documented
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
- \[ ] For a signed-in account, layer visibility choices persist and sync per size class: large/fullscreen (Desktop, fullscreen Web) and compact/phone (phone-sized Web, installed Android/iOS) each remember their own set, and both sync across the account's devices
- \[ ] A signed-in user's fullscreen-laptop-at-home config appears on a fullscreen desktop at work and on fullscreen Web; their phone-web config aligns with the installed phone app — without forcing the same layer set across both size classes
- \[ ] Crossing size classes is not a reset: switching from a large/fullscreen surface to a compact/phone one (or back) loads that class's own remembered set, not a blank or default view
- \[ ] The first time an account enters a size class it's never used before, layers seed from a default appropriate to that class — never an empty view, and never by inheriting the other class's set wholesale (a dense large/fullscreen config must not flood a compact/phone surface on first open)
- \[ ] A windowed (non-fullscreen) large-screen client follows its actual viewport size — resizing the window below the large/fullscreen threshold moves it into the compact set, and layers adjust accordingly; this is intentional, not a bug
- \[ ] Guest Rider sessions keep layer choices per-browser only (no account, no cross-surface alignment), consistent with FR22's browser-local persistence
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
- \[ ] Historical Weather (historical/seasonal norms) for the trip's planned dates is shown on Desktop, Web, and Mobile when planning far in advance
- \[ ] Weather Forecast (10-day/hourly) for upcoming days is shown on Desktop, Web, and Mobile as the trip date nears, aligned to each day's planned location, not just the trip's start point
- \[ ] All three surfaces show Historical Weather and the Weather Forecast together, so the rider keeps the planning-time context alongside the near-term view
- \[ ] A Weather Forecast shown while offline is conspicuously stamped with its retrieval time/age (e.g. "forecast as of Tue 6pm") so a stale cached forecast is never mistaken for a current one
```

```
As a mobile user on a multi-day tour
I want previously-downloaded trip content to work with no network connection
So that I can navigate and view POI info in areas with no cell signal

Acceptance Criteria:
- \[ ] Route, map tiles, and POI content for a trip can be downloaded in advance
- \[ ] App functions with zero errors in airplane mode for a downloaded trip
- \[ ] Features that work fully offline show no offline messaging at all — they simply work
- \[ ] No feature silently fails: any limitation is always user-visible, but passively discoverable — a persistent, unobtrusive status indicator, or an inline note at the boundary of the specific feature that needs connectivity — never an interruptive popup, toast, or modal, and never repeated
```

```
As any account holder
I want to authenticate with a passkey (Face ID/Touch ID/Windows Hello)
So that I can access my trips securely without managing a password

Acceptance Criteria:
- \[ ] A new device is authorized by scanning a QR code with an already-registered, trusted device (FIDO2/CTAP hybrid "use a passkey from another device" flow) — no email or magic-link round-trip, no personal details required; this is the preferred new-device path
- \[ ] A passwordless magic link is the fallback new-device path when no already-trusted device is present, and also serves as an explicit account-recovery path if all bound passkeys are lost
- \[ ] An account can bind multiple passkeys (e.g. phone, laptop, tablet) — losing one device does not lock the account out
- \[ ] Returning sessions authenticate via biometric passkey with no password or SMS OTP prompt at any point
- \[ ] A device awaiting passkey binding is never blocked from the app: it gets full local-first/browser-local planning capability (route generation, layer toggles, GPX/TCX/FIT export) immediately; only account-scoped surfaces (synced trips, save-to-account, sharing-back) wait on the passkey
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
- \[ ] Each device keeps a local working copy and functions normally offline; non-conflicting edits sync automatically when connectivity returns, and any divergence between a device's copy and the server's version is handled via the version-check-on-open flow (FR32), not silently
- \[ ] Sync applies only to the account holder's own devices, distinct from sharing a trip with another user (FR20)
```

```
As an account holder
I want to be notified when a trip has a newer version on the server, whether I'm opening it or about to save
So that I never silently lose or overwrite my own edits made on another device

Acceptance Criteria:
- \[ ] On launch/open, the client (Desktop, Web signed-in, Android, or iOS) compares its local or last-loaded copy of a trip against the server-stored version
- \[ ] The same comparison runs again immediately before a save is committed, catching the case where two devices opened the same version and edited in parallel — the second save is not allowed to silently overwrite the first
- \[ ] If the server version is newer, a clear, unmissable notification tells the user an updated version is available before they can keep editing
- \[ ] The user can choose to save their current/old trip under a distinct name, keeping both versions, or overwrite it in place with the server version
- \[ ] No trip is silently overwritten or discarded without this explicit choice
- \[ ] This check does not apply to unauthenticated Guest Rider sessions, which have no server-stored trip to compare against
```

```
As any persona
I want to set my ride's start point by searching an address, tapping the map, or using my current location
So that I can begin planning without manually entering coordinates

Acceptance Criteria:
- \[ ] Start point can be set by geocoded location search, a map tap, or the device's current GPS position
- \[ ] An optional destination and intermediate waypoints can be set the same way (a destination is required only for the point-to-point shape, FR35)
- \[ ] On Mobile offline, search is served from the trip's bundled extract for in-bounds locations; an out-of-bounds search states plainly that it needs connectivity, inline, once (§4.4)
```

```
As a Day Tripper
I want to choose whether my ride is a loop, an out-and-back, or point-to-point
So that the route matches how I want to start and finish, independent of which theme I pick

Acceptance Criteria:
- \[ ] Route shape (loop / out-and-back / point-to-point) is selectable independently of the five themes — any theme works in any shape
- \[ ] Loop is the default and lowest-friction choice, per §6
- \[ ] Point-to-point requires a destination (FR34); loop and out-and-back need only a start point
```

```
As a Professional Tour Planner
I want a library of my saved trips I can search, rename, duplicate, and delete, and where I can manage who I've shared with
So that many client trips — and the extra copies created when I keep both versions of a conflict — don't become an unmanageable pile

Acceptance Criteria:
- \[ ] Saved trips are listed in a browsable, searchable library that syncs across the account's signed-in devices
- \[ ] A trip can be renamed, duplicated, and deleted from the library
- \[ ] Active shares (FR20) are visible per trip and can be revoked from here
- \[ ] The distinct-name copies produced by the version-check flow (FR32) appear here as ordinary trips
```

```
As a Guest Rider who decides to sign up
I want the route I've been building as a guest to come with me into my new account
So that signing in doesn't throw away the work that convinced me to sign in

Acceptance Criteria:
- \[ ] On the first sign-in or account creation from a browser holding guest work-in-progress, the app offers to import that browser-local trip into the account
- \[ ] The import is an explicit choice; the guest work is never silently discarded, nor silently uploaded without consent
- \[ ] After a successful import, the trip behaves as a normal synced account trip (FR21) and appears in the trip library (FR36)
```

```
As a Guest Rider with no account
I want to generate and export a route without installing anything or signing up
So that I can try the product, or use a route someone planned for me, with zero setup friction

Acceptance Criteria:
- \[ ] All five MVP routing themes (FR1-FR5) are usable without an account
- \[ ] GPX/TCX/FIT export (FR9), Historical Weather, and the Weather Forecast (FR15) work without an account
- \[ ] Streetview imagery/hyperlapse and saving a trip to an account prompt for plug-in setup rather than silently failing or being hidden
- \[ ] In-progress work is persisted in the guest's own browser (IndexedDB for route/trip data, localStorage for small preferences), so closing the tab, refreshing, or a crash does not lose it on that same browser
- \[ ] The UI clearly communicates the limits, never silently: same browser and device only; lost if browser data is cleared or private/incognito mode is used; no cross-device, sync, or share-back
- \[ ] Messaging reflects this — "saved on this browser — export or sign in to keep it anywhere else" — not "export or you lose it on close"
- \[ ] No server-side record is ever kept of a guest session — no email, no account, no personal details
```

### 4.3 Functional Requirements

|ID|Requirement|Priority|Notes|
|-|-|-|-|
|FR1|System generates a route from a start point optimized for the flattest theme (minimize elevation gain)|P0|Requires the local-first elevation pipeline (SRTM primary, open-elevation fallback), validated at M1|
|FR2|System generates a route from a start point optimized for the most-climbing theme (maximize/target elevation gain)|P0|Shares the elevation pipeline used for FR1; validated at M1|
|FR3|System generates a route from a start point optimized for the lowest-traffic theme|P0|Traffic-class threshold is a global user default with a per-route override; detour budget is likewise configurable in both miles and minutes, globally and per-route|
|FR4|System generates a route from a start point optimized for the fewest-turns theme — minimizing navigational maneuvers (way/road changes, intersection decisions), not road curvature|P0|"Turn" defined as leaving the current OSM way/named road for a different one, or negotiating an intersection requiring a decision/maneuver — not a heading-change angle threshold. Staying on the same way as it curves counts as zero turns, however much it bends; documented alongside the scoring function (§5.1)|
|FR5|System generates a route from a start point optimized for the most-art/history theme (OSM `tourism=\*`/`historic=\*` tags)|P0|Distinct from FR23 (P2), which layers richer curated content on top of this base theme|
|FR6|System exposes route generation via a FastAPI endpoint with typed request/response schemas|P0||
|FR7|Client renders a generated route on a map|P0|Desktop first|
|FR8|User can toggle visibility of OSM tag categories as map layers (landmarks, POIs, parks, construction, etc.), configurable per-user to keep the UI to only what's relevant to them. For signed-in accounts, layer choices sync at the account level, bucketed by size class — large/fullscreen (Desktop, fullscreen Web) and compact/phone (phone-sized Web, installed Android/iOS) — so a user's choices for a given size class travel with them across every surface in that class, without forcing one global set across both classes. A windowed, non-fullscreen large-screen client follows its actual viewport and moves between classes as it's resized. First entry into a size class seeds from a class-appropriate default (never the other class's set wholesale), never empty. Guest Rider sessions remain per-browser only (FR22), with no cross-surface alignment|P0|First-iteration requirement, not deferred; size-class bucketing shares its two-bucket model with the contrast-mode system (§6, §9 item 19) so the app reads as one adaptive-to-surface idea, not two separate systems|
|FR9|System exports a route as a valid GPX, TCX, or FIT file, user's choice of format|P0||
|FR10|User can insert waypoints/checkpoints that the route must pass through|P1||
|FR11|System supports multi-day trip splitting by min/max daily mileage|P1||
|FR12|Routes can be constrained/scored by surface type (paved/gravel/off-road/single-track)|P1||
|FR13|User can set sliding-scale weights for elevation-gain and surface-type preference, independently scoped to the whole tour, a single day, or a partial day, with day/segment weights overriding the tour default for that scope only|P1|Depends on FR11 (multi-day splitting) for day/partial-day scoping|
|FR14|System surfaces lodging and campground locations along a route/trip, sourced from OpenStreetMap tags (e.g. `tourism=hotel`, `tourism=camp\_site`, `tourism=guest\_house`)|P1|Depends on FR11 for per-day overnight-point alignment; OSM-only for v1 — see Open Questions re: a dedicated lodging/campsite service|
|FR15|System displays trip-dated weather: Historical Weather (historical/seasonal averages, for long-range planning) and a Weather Forecast (10-day/hourly, as the trip date nears) — both available on Desktop, Web, and Mobile alike, with no platform-based restriction between the two data types; both align to each day's planned location and date, not just the trip's start point or the current date. Every surface shows both together, so the rider keeps the Historical Weather context they planned against alongside the more time-relevant Weather Forecast — this also covers unauthenticated Guest Rider access (FR22), since Guest Rider is Web-only|P1|Depends on FR11 for per-day date alignment; the only remaining split is timing, not platform: Historical Weather targets M5 as shared weather work (surfaced on Desktop first, then inherited by Web at M6 and Mobile at M7 as each client ships); Weather Forecast targets M7, once the live-forecast data service is integrated, surfacing simultaneously on Desktop, Web, and the new Mobile client rather than being Mobile-exclusive; requires a new external weather data service — see Open Questions|
|FR16|User can download a trip's map, route, and selected map content (map data, and elevation raster tiles) for offline use|P1|Non-Web targets|
|FR17|Android and iOS builds run from the shared Flutter codebase with feature parity for offline trips|P1||
|FR18|Web build from the shared Flutter codebase aims to come as close to Desktop planning parity as is practical for a server-backed web client — waypoints, multi-day logistics, sliding-scale weighting, lodging, and both Historical Weather and the Weather Forecast are the target feature set — not just route viewing. Gaps against Desktop are acceptable trade-offs where a server-backed, online-only surface makes full equivalence impractical, not an out-of-spec failure|P1|Extends FR7 (Desktop) and FR17 (Android/iOS) with a fourth, close-to-parity target; sequenced at M6 rather than bundled with mobile, since guest access (FR22) and cross-device sync (FR21) both depend on it existing. This is planning-*feature* parity as a direction of travel, not offline-capability parity — Web is conventionally server-backed and online-only (§4.4), a real, stated difference from the local-first installed apps, not a gap to paper over; whether Web needs any offline story at all remains open, see §9 item 18|
|FR19|App authenticates users across mobile, desktop, and web via a unified, biometrics-first passkey flow (Face ID, Touch ID, Windows Hello). A new device is preferentially authorized via QR-code cross-device authorization (FIDO2/CTAP hybrid "use a passkey from another device"), with no email/magic-link round-trip and no personal details required; a passwordless magic link is the fallback when no already-trusted device is present, and also serves as an explicit account-recovery path. Accounts can bind multiple passkeys (e.g. phone, laptop, tablet) so losing one device isn't lockout. A device awaiting passkey binding is never blocked: it gets the same local-first/browser-local planning capability as the guest tier (route generation, layer toggles, GPX/TCX/FIT export) immediately; only account-scoped surfaces (synced trips, save-to-account, sharing-back) wait on the passkey. No password-only or SMS OTP flows at any point|P1|Enables route sharing (FR20) and cross-device sync (FR21); pending-registration capability mirrors FR22's guest browser-local persistence (§4.4) — satisfies §6's rule that login prompts appear only at a real capability boundary, never preemptively|
|FR20|Account holder can share a trip/route with another user (e.g. tour planner → client), with the recipient able to view it without recreating it|P1|Requires FR19 accounts; the recipient does not need an account (see §9, resolved)|
|FR21|An account holder's own trips sync across their signed-in devices (desktop, mobile, web) via a canonical per-account copy in the FastAPI/Postgres layer, reconciled with each device's local working copy when online. The same account-level sync also carries non-trip preferences — layer/view visibility bucketed by size class (FR8) and the contrast-mode override (§6, §9 item 19) — distinct from trip data but synced the same way|P1|Depends on FR19 (accounts); distinct from FR20 — same account holder's own devices, not a share to a different person; a new, explicit exception to the local-first principle (§4.4)|
|FR22|Unauthenticated ("Guest Rider") web sessions can run all five MVP routing themes (FR1–FR5), export GPX/TCX/FIT (FR9), and view both Historical Weather and the Weather Forecast (FR15) without an account. In-progress route/trip state, layer toggles, and form inputs persist in the guest's own browser (IndexedDB for route/trip data, localStorage for small preferences) so closing the tab, refreshing, or a crash doesn't lose the work on that browser — but nothing is stored server-side: no email, no account, no personal details, and no cross-device, sync, or share-back capability. That browser-local state is lost if the user clears browser data, switches browsers/devices, or uses private/incognito mode; export (GPX/TCX/FIT) remains the durable, portable path. Streetview imagery/hyperlapse (FR27/FR28) and saving a trip to an account require logging in|P1|New persona — see §4.1; gating streetview behind login also functions as cost control for the metered Street View Static API (§7); depends on FR18 (Web client) existing. Browser-local persistence does not change the stateless-compute/anti-abuse posture — see §7|
|FR23|System supports "building/architectural interest" themed tours using OSM tagging (e.g. historic=*, tourism=*)|P2|Builds on the OSM-tag scoring introduced by FR5|
|FR24|System plays audio narration for POIs selected during planning|P2||
|FR25|Users can upload images/feedback on routes, roads, intersections, and POIs, with public/private visibility|P2|Requires FR19 accounts, for authorship and public/private visibility control|
|FR26|Full trip (route + content + user contributions) can be exported as GeoJSON with attributes|P2||
|FR27|User can view streetview-style or other point-of-view imagery during planning|P2|Candidate plug-in based feature (proposed, undecided — see §3.5, §3.6); may share the paid Street View Static API dependency with FR28 (§3.5) — see risk in §7|
|FR28|System can generate (or hand off to) a desktop-only Street View hyperlapse preview of a route via streetwarp-cli integration|TBD|Candidate plug-in based feature (proposed, undecided — see §3.5, §3.6); desktop-only, absent on mobile/web — that absence is explained in-product at the handoff, not left to silently vanish (§4.4/§6 quiet-clarity stance); see §3.5 — implementation and interaction intentionally undecided|
|FR29|System suggests routes/segments based on a group's rider skill profiles|P3|Stretch|
|FR30|System suggests routes/segments weighted toward frequently-cycled bike routes, greenways, and rail trails|TBD|Needs definition — data source (OSM cycle-infrastructure tags vs. a heatmap-style service) and scoring approach undecided; see Open Questions|
|FR31|System incorporates route/segment popularity data (Strava-heatmap-style signal) into route suggestions|TBD|Needs definition — no OSM-native equivalent; would require a new third-party data source, in tension with the open-data/local-first bias (§4.4); see Open Questions|
|FR32|Each signed-in client (Desktop, Web signed-in, Android, iOS) compares its local (or last-loaded) copy of a trip/route against the server-stored version at two points: on launch/open, and again immediately before committing a save. If the server version is newer at either point, the client shows a clear notification that an updated version is available, and the user chooses to either (a) save their current/old trip under a distinct name, keeping both, or (b) overwrite in place with the server version. The save-time check specifically catches the case where two devices both opened the same version, edited independently, and would otherwise silently overwrite each other at save|P1|Applies to all signed-in surfaces; does not apply to unauthenticated Guest Rider sessions (FR22), which have no server-stored trip to compare against. Replaces bare last-write-wins as the primary reconciliation UX for FR21's cross-device sync — divergence is always surfaced to the user, never silently resolved, at open and at save (see §4.4, §7, §9 item 14; UX.md §2)|
|FR34|User sets the route's start point — and optional destination and intermediate waypoints — via location search (geocoding), a tap on the map, or the device's current GPS location. This is the entry step before any theme routing runs|P0|Requires a geocoding service (e.g. Nominatim/Photon over OSM data), a new external dependency subject to the responsible-use caching discipline (§4.4); offline behavior on Mobile relies on the trip's bundled extract for in-bounds search — see Open Questions #20–21|
|FR35|User selects the route shape — loop (start == end), out-and-back, or point-to-point — as an input orthogonal to the five routing themes, so any theme can be generated in any shape. Loop is the default, reflecting the persona preference in §6|P1|The MVP's "generate a route from a start location" (§3.4) implicitly defaults to a loop; explicit out-and-back / point-to-point selection is the P1 addition. Point-to-point requires a destination from FR34|
|FR36|A trip library lets a signed-in user list, search, rename, duplicate, and delete their saved trips, and view and revoke active shares (FR20). This is where the distinct-name copies produced by the version-check flow (FR32) and a Professional Tour Planner's many client trips are managed|P1|Depends on FR19 accounts and FR21 sync; the trip list itself syncs per account. Guests have at most their single browser-local WIP (FR22) and no library|
|FR37|On the first sign-in (or account creation) from a browser that holds unsynced guest work-in-progress (FR22), the app offers to import that browser-local trip into the account rather than discarding it or leaving it orphaned in the guest store|P1|Closes the guest→account conversion path; the import is an explicit user choice, consistent with never silently moving or losing a user's work. Depends on FR19 (accounts) and FR22 (guest browser-local persistence)|

### 4.4 Non-Functional Requirements

* **Local-first (Desktop and Mobile)**: Core routing must run without a network connection to any remote service on Desktop and Mobile; OSMnx works against locally-cached OSM extracts, and elevation enrichment reads from local SRTM tiles bundled with each trip's bounding box rather than depending on a live network call for the common case. Two explicit exceptions exist on these targets, each scoped as narrowly as possible: (1) trip-dated weather (FR15) — Historical Weather (historical/seasonal norms) can be bundled/cached like elevation data, but the Weather Forecast (10-day/hourly) inherently requires network access when available, degrading gracefully to its own last-cached Weather Forecast data offline rather than falling back to Historical Weather (see Offline mobile, below); (2) account-holder cross-device sync (FR21) — each signed-in device keeps a local working copy and functions normally offline; when back online, divergence between that copy and the canonical per-account copy in FastAPI/Postgres is surfaced to the user via the version-check-on-open flow (FR32) rather than reconciled silently. The same sync also carries non-trip account preferences — layer/view visibility bucketed by size class (FR8) and the contrast-mode override (§6, §9 item 19) — alongside trip data
* **Web is conventionally server-backed, not local-first** (revised 2026-07-10 — see `ARCHITECTURE.md` §2 Principle 1/6): no browser runs the OSMnx routing core offline without a WASM port that isn't in scope, so Web depends on the hosted FastAPI/Postgres service for all compute, both signed-in and guest. Signed-in Web sessions use a conventional server-side session (cookie + revocable Postgres row), not a local working copy. Unauthenticated guest sessions (FR22) still call FastAPI statelessly for compute and store nothing server-side — no email, no account, no personal details — but do persist in-progress work (route/trip state, layer toggles, form inputs) in the guest's own browser via IndexedDB/localStorage, so a refresh or closed tab doesn't lose it. This is an intentional reversal of the original "thin client, no local persistence" characterization: that was a design assumption, not part of the privacy guarantee, which was always specifically about server-side storage. Browser-local data is same-browser/same-device only, is lost if the user clears browser data or uses private/incognito mode, and never syncs, shares back, or crosses devices — those remain account-gated (FR19/FR21). Whether Web should ever offer offline capability for signed-in users (e.g. service-worker/PWA caching of their own trips) remains a separate open question — see §9 item 18
* **Offline mobile**: Offline is the app's normal, expected state, not an error condition — downloaded trip content must be fully usable with zero errors with no connectivity, and features that work fully offline show no offline messaging at all. A persistent, unobtrusive status indicator communicates connectivity passively; when a specific feature needs connectivity (e.g. the live Weather Forecast, sync, sign-in), that's surfaced inline at that feature's boundary, once — never as a repeating, interruptive, or modal alert. No feature silently fails: any limitation is always passively discoverable, never actively interrupted for. A Weather Forecast displayed while offline is always shown with its retrieval time/age, so a stale cached forecast (older than its short online TTL, per the responsible-use NFR below) reads as visibly old rather than being presented as current — the one case where the app must show data it knows may be stale, made honest by stamping its age
* **Power efficiency**: Mobile client should minimize GPS/CPU/network wake-ups during long rides — this is an explicit design constraint, not an afterthought
* **Security**: Biometrics-first passkey auth (Face ID/Touch ID/Windows Hello) unified across mobile and desktop. New-device authorization prefers the standard FIDO2/CTAP hybrid QR flow ("use a passkey from another device") over an already-registered, trusted device — no email/magic-link round-trip, no personal details required. A passwordless magic link is the fallback for new-device registration when no trusted device is present, and is also promoted to an explicit account-recovery path, not registration-only. Accounts can bind multiple passkeys (e.g. phone, laptop, tablet), so losing one device is not lockout. On platforms where the passkey plugin proves too immature (see §7), the client falls back to a magic-link-authenticated session rather than blocking the user. No password-as-sole-factor or SMS OTP is to be implemented at any point, under any of these paths
* **Portability**: One Flutter codebase targets Android, iOS, Desktop, and Web — avoid platform-specific forks except where unavoidable
* **Open data / open source bias**: Prefer high-social-worth open source libraries and open datasets (OSM) over proprietary services where a viable option exists
* **Responsible use of shared/external open resources**: Any data fetched from a shared or external open resource — self-hosted/generated map tiles (§5.2, §5.3), the open-elevation.com elevation fallback (§5.1), the weather service (FR15), and the geocoding service (FR34) — is cached (server-side and/or client-side, as applicable) with a reasonable expiry/TTL, a bounded cache size with eviction, and no bulk-hammering or repeat requests for data already held. This formalizes a principle the app already half-follows — the elevation fallback's "never re-request a coordinate" rule (§5.1) — and extends the open-data good-citizen bias above to every external dependency, not just elevation. Cache TTLs must fit each data type's actual volatility, not a single blanket duration: the Weather Forecast (10-day/hourly) changes frequently and must use a short TTL, never cached for a long period — a stale forecast is worse than none; tiles and elevation data change slowly and can use long TTLs; Historical Weather norms are effectively static and can be cached long or bundled outright, like elevation. If tiles are ever sourced as *rendered* images from a public third-party endpoint rather than generated from raw OSM data, this caching discipline becomes mandatory to respect that endpoint's usage policy, not merely a politeness norm

\---

## 5\. Technology Requirements (Learning Objectives)

This section is first-class, not an implementation appendix, because the technology stack is a project goal, not just a means to an end.

### 5.1 Routing Core — Python + OSMnx

* **Learning goal**: Understand OSMnx graph construction (`graph\_from\_place`/`graph\_from\_bbox`), custom edge weighting functions, and shortest-path variants (Dijkstra/A\*) applied to real-world constraints (elevation, surface, traffic-class tags)
* **Requirement**: Local caching uses OSMnx's own graph caching (`graph\_from\_place`/`graph\_from\_bbox` with `ox.settings.use\_cache` + `save\_graphml`/`load\_graphml`), not a separately managed `.osm.pbf` extract pipeline — keeps the routing core to one tool for both fetch and cache
* **Requirement**: At least one custom multi-factor scoring function per theme (FR1–FR5) must be implemented and documented — this is the core "why OSMnx" exercise
* **Requirement**: The fewest-turns theme's (FR4) turn-count signal scores by navigational maneuvers, not road curvature — a transition between distinct OSM ways/named roads, or an intersection requiring a decision/maneuver, counts as a turn; staying on the same way as it curves, however much the road bends, counts as zero. This is deliberately distinct from a heading-change-angle metric, which would score a single curvy road as many turns and miss that a neighborhood-grid route with a turn every block is the actually complex one, even where each individual block segment is straight
* **Requirement**: Elevation-aware routing is in scope for v1 using a **local-first, dual-source** strategy: local SRTM tiles (`.hgt` or GeoTIFF) bundled with each trip's bounding-box extraction are the primary elevation source during graph compilation, read via a Python raster parsing library (`rasterio` or `srtm.py`). open-elevation.com is used strictly as a **secondary fallback** — only when local tile data for a given coordinate is missing, imprecise, or a data void — with a local cache layer so any coordinate that falls back to the network is never requested twice. This pipeline is required starting at M1, since two of the five P0 MVP themes (FR1, flattest; FR2, most climbing) depend on it directly
* **Requirement**: Elevation-gain and surface weighting functions (FR13) must accept weights that vary by position along the route (tour-wide default, overridden per day or per partial-day segment), not just a single global scalar — this is a meaningfully harder version of the FR1–FR5 custom-weighting exercise

### 5.2 Middle Layer — FastAPI

* **Learning goal**: Typed request/response models with Pydantic, dependency injection, async endpoint design, and OpenAPI schema generation as a byproduct of the code (not hand-written docs)
* **Requirement**: Route generation, trip CRUD, and export endpoints are all exposed through FastAPI with auto-generated OpenAPI docs
* **Requirement**: Long-running route computations (large multi-day trips) should demonstrate FastAPI's async/background-task patterns rather than blocking request handling
* **Requirement**: Auth/account endpoints (passkey registration \& verification per WebAuthn — including binding multiple passkeys per account — QR-code cross-device authorization per the FIDO2/CTAP hybrid transport, magic-link issuance/consumption for both new-device registration and account recovery, share-link/token issuance for FR20) live in FastAPI, alongside two related but distinct server-side responsibilities: account-holder cross-device trip sync (FR21) and stateless live compute for unauthenticated guest sessions (FR22) — together these are the parts of the system that are not local-only; see §4.4 for how each stays scoped as narrowly as possible
* **Requirement**: The FastAPI service, its Postgres database, and the Flutter Web static build are hosted on Render (a Starter web service, a Starter Postgres instance, and a free static site) — chosen for always-on behavior, since OSMnx keeps compiled graphs cached in memory and a cold start would hit a guest's first request hardest, and for fixed, predictable cost under anonymous guest traffic rather than usage-based billing
* **Requirement**: For Web, FastAPI runs the same tile-generation pipeline server-side for a requested trip's bounding box (§5.1/§5.3), caches the rendered tile set, and serves it to the browser — an on-demand, bbox-scoped, cached service, not a third-party rendered-tile endpoint and not a standing global tile server (§7's "no standing tile server" scope rules out the latter, not this). This adds a deliberate, in-character server-side responsibility to the already-server-backed Web surface — a mild, acknowledged tension with keeping the hosted service narrowly scoped (§7), justified because Web has no local generation path of its own. The same cache can serve as the origin for Desktop/Mobile's per-trip offline tile bundle, so there's one tile-generation pipeline, not two
* **Requirement**: Location search is backed by a geocoding service over OSM data (e.g. a self-hosted Nominatim/Photon instance, or the public endpoints at low volume) exposed through FastAPI, with results cached under the responsible-use discipline (§4.4). This is the fourth external/shared dependency (alongside tiles, elevation, and weather) and the entry point to every routing flow (FR34)
* **Stretch learning goal**: WebSocket or SSE endpoint for streaming route-generation progress to the client

### 5.3 Client — Flutter/Dart (Android, iOS, Desktop, Web)

* **Learning goal**: A single Dart codebase producing four build targets, with a real understanding of where platform-specific code is unavoidable (e.g. background location, offline storage, map rendering backend differences)
* **Requirement**: Map rendering via `flutter\_map` over self-hosted tiles (generated from raw OSM extracts via the same tile-generation pipeline everywhere, not pulled from a third-party rendered-tile endpoint) rather than a proprietary maps SDK, consistent with the open-source bias in §4.4 and the offline-bundling need in FR16. Desktop and Mobile generate tiles locally, per-trip bounding box. Web has no local generation path — no browser runs the tile-generation pipeline — so it fetches tiles from the Render-hosted FastAPI backend, which runs the same generation pipeline server-side for the requested trip bounding box, caches the result, and serves it to the browser (§5.2): an on-demand, bbox-scoped, cached service, not a third-party endpoint and not a standing global tile server. This same server-side cache can also act as the origin Desktop/Mobile fetch their per-trip tile bundle from before going offline, unifying the pipeline across all four targets rather than running two independent tile-generation code paths. The tile-generation step is required starting at M3 (Desktop client) — see §8
* **Requirement**: Local persistence layer (e.g. `sqlite`/`drift` or similar) for offline trip storage — this is core to FR16/FR17, not optional polish
* **Requirement**: Biometric passkey integration (platform authenticator via WebAuthn/`passkeys` plugin) on both mobile (Face ID/Touch ID) and desktop (Windows Hello) targets, with a shared auth flow rather than per-platform bespoke logic — this is the hardest cross-platform-parity test in the app (FR19). Includes the FIDO2/CTAP hybrid ("use a passkey from another device") QR flow for cross-device authorization, and support for binding/managing multiple passkeys per account. A device pending passkey binding must not block the client shell — it drops into the same local-first/browser-local planning capability the guest tier uses (FR22) until the passkey completes or the account-recovery magic link is used
* **Requirement**: Desktop and Web targets are explicitly part of the learning scope, not just "if we get to it." Web goes beyond original route-viewing parity: it's a full planning client for signed-in account holders, including cross-device sync (FR21), and it also supports a distinct unauthenticated guest mode (FR22) that calls FastAPI directly for stateless compute (no server-side storage) while persisting in-progress work in browser-local storage (IndexedDB/localStorage) rather than the `drift`/SQLite store the other, signed-in targets use — a reversal of the original "no local persistence" guest-mode characterization, since the privacy guarantee was always about server-side storage, not the browser. Web is sequenced at M6, ahead of the Android/iOS build at M7, since sync and the guest tier both depend on it — see §8
* **Requirement**: Map layer visibility (FR8) is implemented as user-toggleable `flutter\_map` layers keyed to OSM tag categories (not a fixed, hardcoded layer set). For signed-in accounts, choices sync at the account level via FastAPI/Postgres (alongside FR21 trip sync and the contrast-mode override, §6/§9 item 19), bucketed into two size classes shared with the contrast-mode system — large/fullscreen (Desktop, fullscreen Web) and compact/phone (phone-sized Web, installed Android/iOS) — so a user's per-class choices travel across every surface in that class, without forcing identical config across both classes. A windowed, non-fullscreen large-screen client tracks its actual viewport and moves between classes as it's resized — intentional, not a reset: each class independently remembers its own set. First entry into a size class an account hasn't used before seeds from a class-appropriate default — never the other class's set inherited wholesale, so a dense large/fullscreen configuration does not flood a compact/phone surface on first open — never an empty view. Guest Rider sessions keep this per-browser only (FR22), with no account-level sync or cross-surface alignment

### 5.4 Explicit Non-Goals for the Learning Scope

* No native iOS/Android modules beyond what Flutter plugins already provide, unless a specific capability (e.g. background GPS) forces it
* No infrastructure/DevOps learning track (no Kubernetes, no cloud deploy) — local-first keeps the ops surface intentionally small

\---

## 6\. Design \& UX Principles

* Goal-driven planning is the primary interaction, not a filter bolted onto a generic map — theme selection (flattest, most art, lowest traffic, etc.) should be a first-run decision, not buried in settings
* Loops > point-to-point > out-and-back, reflecting the Weekend Cyclist persona's stated preference — the UI should make loop creation the path of least resistance. Route shape is chosen independently of the routing theme (FR35): any theme can be a loop, out-and-back, or point-to-point, with loop pre-selected
* Setting the ride's start (and, for point-to-point, destination) is the first action in every flow (FR34) and should be frictionless — search, map tap, or current location — not a coordinate-entry chore
* A user's work is never silently lost or discarded at a boundary — signing in offers to bring guest work into the account (FR37), a version conflict lets the user keep both copies (FR32), and saved trips live in one manageable library (FR36) rather than accumulating invisibly
* Surface type and traffic level are always visible on a route, not hidden behind a details screen
* Offline is the expected, first-class state, not degraded UX — a persistent, unobtrusive status indicator (e.g. a quiet, glanceable badge) keeps connectivity passively clear at all times, so a user is never unsure whether a screen will work without signal, without resorting to prompts, toasts, or modals. Features that work fully offline carry no offline messaging at all; a feature that actually needs connectivity (live Weather Forecast, sync, sign-in) surfaces that need inline, at that feature, once — never as a recurring or interruptive alert
* Map content (OSM tags/layers) is opt-in and user-configurable — the default view should not force every rider through menus for POI categories (e.g. construction) that are irrelevant to them
* Guest/unauthenticated use is first-class for what it supports, not a crippled trial — login prompts appear only at an actual capability boundary (saving a trip, viewing streetview imagery — the latter a candidate plug-in based boundary too, if that proposed tier is ever adopted), never preemptively before that point
* Guest work-in-progress is saved automatically in the guest's own browser, not discarded on tab close — messaging reflects this ("saved on this browser — export or sign in to keep it anywhere else"), not the old "export or you lose it" framing. Login prompts still appear only at a real capability boundary (saving to an account, cross-device access, streetview), never preemptively
* Cross-platform "parity" (Desktop, Web, Android, iOS) is a direction of travel, not a pass/fail bar — each surface aims to come as close to the others' feature set as is practical, and gaps are deliberate, acceptable trade-offs where a surface's constraints make full equivalence impractical, not spec failures. Where a real behavioral difference exists (e.g. Web is online-only and server-backed while the installed apps work offline), that difference is stated plainly rather than papered over with a parity claim
* Indoor and Outdoor contrast are one adaptive system, not a manual toggle — the app senses context (device type, viewport, and where practical, ambient light or the OS's light/dark setting) and defaults intelligently: Mobile always defaults to Outdoor Contrast, Desktop/Web default to Indoor Contrast. A manual switch exists only as an override for when that automatic read is wrong (e.g. planning from a laptop at a sun-exposed trailhead), not as the primary interaction — the same visual identity, dressed for the conditions, not an unexplained jump between two apps. An explicit override is a synced, account-level preference that travels with the signed-in user across devices; the automatic default still evaluates fresh per surface, independent of any saved override

\---

## 7\. Risks \& Mitigations

|Risk|Probability|Impact|Mitigation|
|-|-|-|-|
|OSMnx multi-factor weighting across all five MVP themes is harder than expected (elevation/POI/surface data sparse or inconsistent in OSM)|High|Medium|Build and validate the local-first elevation pipeline (SRTM + open-elevation fallback) and POI-tag scoring for the most-art theme within M1, before the API/client layers depend on them; surface-type weighting (FR12) remains a separate P1 item beyond the five M1 themes|
|Chasing full four-target parity (Desktop, Web, Android, iOS) balloons scope, when parity was only ever meant as "as close as practical" guidance, not a contractual requirement|High|Medium|Treat parity as a direction of travel, not a pass/fail bar — trade off gaps deliberately where a target's constraints make full equivalence impractical (e.g. Web's online-only, server-backed nature vs. the installed apps' offline capability) rather than chasing 1:1 feature-for-feature matching; sequence targets — Desktop first (fastest iteration), then Web (concurrent with M6's accounts/sync work, since cross-device sync and the guest tier both depend on it), then Android/iOS|
|Local OSM extract size/performance on mobile devices|Medium|Medium|Scope offline downloads to a bounding box per trip, not full regional extracts|
|Solo project with no deadline pressure risks stalling|Medium|Medium|Anchor scope to the MVP in §3.4, which is deliberately small and demo-able|
|Biometric passkey support (Face ID/Touch ID/Windows Hello) via Flutter has uneven plugin maturity across Desktop vs. mobile|Medium|High|Spike passkey auth early (before M5) rather than at the end; on any platform where passkey support proves too immature, fall back to a magic-link-authenticated session rather than blocking the user — the same magic-link path that already serves as the new-device fallback and explicit account-recovery lane. Multi-passkey binding and QR cross-device authorization (FIDO2/CTAP hybrid) also reduce how often any single platform's passkey immaturity is even on the critical path, without blocking sharing|
|open-elevation.com (public, rate-limited) becomes a bottleneck or goes down|Low/Medium|Medium|Now a fallback only — primary elevation comes from local SRTM tiles, so the routing core degrades gracefully rather than depending on the network for the common case; fallback lookups are cached locally so a coordinate is never re-requested|
|Coordinate-to-tile file management and local data voids/missing SRTM tiles within the Python routing core|Medium|Medium|Fall back to open-elevation.com when local data is missing/imprecise; if that also fails, fall back to a flat-earth assumption (0.0m elevation change) for that coordinate so the routing engine never stalls or crashes the UI|
|Self-hosted tile pipeline (generating/serving offline map tiles from local extracts) adds real tooling overhead beyond app code, and Web has no local generation path at all|Medium|Medium|Scope to per-trip bounding-box tile generation, not a standing tile server: Desktop/Mobile generate locally; Web fetches from a Render-hosted, on-demand, bbox-scoped server-side cache running the same pipeline (§5.2, §5.3) — a bounded per-area cache, not the global always-on world tile service the "no standing tile server" scope actually rules out. Acknowledge the mild tension this adds to keeping the hosted service narrowly scoped (§4.4) — a deliberate, in-character exception, not scope creep left unexamined|
|Desktop/Mobile's hosted-service touchpoints (auth/share-brokering, cross-device sync — FR19–FR21) could drift into a general multi-tenant backend if not kept narrow. (Web's use of the hosted service is deliberately *not* scoped this way as of 2026-07-10 — see below and `ARCHITECTURE.md` §2 Principle 1/6 — this row now applies only to what Desktop/Mobile touch)|Medium|Medium|Scope each Desktop/Mobile-facing exception explicitly and separately rather than merging them into one general-purpose service: auth + share-token brokering only for FR20; per-account sync of that account's own trips only for FR21; stateless compute with no storage for FR22 (guest tier, all platforms) — see §4.4|
|Web's signed-in session now uses a conventional server-side session (cookie + Postgres row) rather than avoiding server storage — since the Flutter Web static build and the hosted API are separate Render origins, this requires a correct cross-origin/cookie configuration (same-site reverse proxy vs. `SameSite=None`+CORS), and a misconfiguration here (e.g. overly permissive CORS to make cookies "just work") is a real vulnerability class this design didn't previously have to think about|Medium|High|Decide the origin strategy (proxy/custom-domain vs. cross-site cookies) before M6's Web auth work starts, not during it — see §9 item 17 and `ARCHITECTURE.md` §11.T|
|Segment-varying elevation/surface weighting (FR13) turns route scoring into a per-position function instead of a single scalar, adding real algorithmic complexity|Medium|Medium|Build the single-scalar versions (FR1–FR5) first; treat day/partial-day overrides as an explicit follow-on iteration on the same scoring functions, not a rewrite|
|Unauthenticated guest-tier compute (FR22) is reachable by anonymous traffic, creating a cost/abuse surface the routing core and weather proxy didn't have before|Medium|Medium|Rate-limit guest-tier endpoints (e.g. per-IP throttling) before launch; keep guest sessions fully stateless server-side so abuse can't accumulate persistent server-side cost beyond the compute itself. Guest work-in-progress persisted client-side in the guest's own browser (see FR22, §4.4) doesn't change this posture — it's local to the guest's device and never touches the server, so it adds no new storage/abuse surface|
|Cross-device sync (FR21) introduces conflict resolution the app never needed while trips were purely local-first (e.g. the same trip edited offline on two devices before either reconnects)|Medium|Medium|Resolve via the explicit version-check flow (FR32), run both on open and immediately before save: compare the local/last-loaded copy against the server version and, if newer, let the user save-as (keep both) or overwrite — no silent whole-trip last-write-wins. The on-save check closes the gap where two devices open the same version and edit in parallel (an open-only check would miss this and silently lose the second save); revisit per-field merge only if the whole-trip choice proves inadequate, avoiding a general merge/CRDT system speculatively|
|streetwarp-cli phase (§3.5, FR28) depends on external, possibly-paid Google Street View Static API and `ffmpeg`, dependencies unlike anything else in the stack|Low (it's last)|Low|Left fully TBD by design; revisit feasibility/cost only once it's actually next in line|
|FR27 (streetview-style imagery during planning) may depend on the same paid Google Street View Static API as FR28|Medium|Medium|Confirm whether FR27 needs live Street View imagery or can use a cheaper/open alternative (e.g. Mapillary) before scoping; if it does need the Street View Static API, treat cost/key management as one shared risk with FR28 rather than solving it twice|

\---

## 8\. Milestones (Sequenced, not Dated)

Given this is a solo learning project, milestones are ordered by dependency rather than calendar-dated.

|Milestone|Deliverable|Validates|
|-|-|-|
|M1 — Routing spike|OSMnx generates routes for all five MVP themes (FR1–FR5: flattest, most climbing, lowest traffic, fewest turns — maneuver/way-change based, not curvature, see FR4 — most art/history) between two points from a local OSM extract, including the local-first elevation pipeline (local SRTM primary, open-elevation.com fallback) needed for the flattest/most-climbing themes|Core routing feasibility across all five P0 themes, plus elevation sourcing|
|M2 — API wrap|FastAPI endpoint(s) return M1's five theme routes as JSON with OpenAPI docs (FR6)|FastAPI learning goal|
|M3 — Desktop client + tiles|Flutter Desktop app calls the API and renders routes using self-hosted tiles generated from local OSM extracts, with toggleable OSM tag layers (FR7, FR8), start-point/destination selection via geocoded search / map tap (FR34), and route-shape selection — loop / out-and-back / point-to-point (FR35)|Flutter + client-server integration, plus tile-pipeline feasibility and the route entry step|
|M4 — GPX export|All five MVP theme routes exportable as GPX, TCX, and FIT, verified in RideWithGPS (FR9)|MVP completion (§3.4)|
|M5 — Multi-day trips|Daily mileage/elevation splitting (FR11; elevation pipeline already validated in M1) + waypoints (FR10) + surface-type scoring (FR12) + sliding-scale elevation/surface weighting (FR13, tour/day/partial-day) + lodging/campground data (FR14) + Historical Weather (FR15), the shared weather-data foundation, surfaced on Desktop first|P1 trip logistics|
|M6 — Accounts, sync \& Web|Biometrics-first passkey auth (mobile + desktop) with magic-link registration (FR19); share-link flow (FR20); Flutter Web build reaches as close to full planning parity as practical (FR18); account-holder cross-device sync (FR21) with version-check-on-open-and-save reconciliation (FR32); trip library with share management (FR36); guest→account claim on sign-in (FR37); unauthenticated guest-tier web access (FR22)|P1 sharing/sync (FR19–FR22, FR32, FR36, FR37) plus the Web milestone, pulled forward from its earlier implicit "last" position since both sync and guest access depend on it|
|M7 — Mobile + offline|Android/iOS builds (FR17), offline trip download (FR16), Weather Forecast (10-day/hourly) ships once the live-forecast data service is integrated — surfacing simultaneously on the new Mobile client and retrofitted onto the already-existing Desktop and Web clients (including Guest Rider, FR22) — alongside the already-available Historical Weather (FR15)|P1 mobile parity, plus Desktop/Web weather-forecast parity|
|M8 — Content layer|POI narration (FR24), crowd-sourced feedback (FR25), GeoJSON export (FR26)|P2 features|
|M9 — Streetview imagery \& hyperlapse|Streetview-style imagery during planning (FR27) plus desktop-only streetwarp-cli hyperlapse integration (FR28, TBD) — both candidate plug-in based features (proposed, undecided; §3.5, §3.6)|FR27 grouped here since it likely shares FR28's Street View Static API dependency (§7) and now its plug-in based framing; hyperlapse implementation deliberately undetermined until this phase starts (§3.5)|
|M10 — plug-in based trip version history (TBD, not committed)|Proposed plug-in based tier automatically retaining the last 5–10 versions of a trip for rollback (FR33)|Nothing yet — proposed future scope only, scheduled after every other milestone (§3.6); conflicts with the no-monetization stance in §3.3, flagged not resolved|

\---

## 9\. Open Questions

### Resolved

1. **OSM extract/caching**: OSMnx's own graph caching (not a separate `.osm.pbf` extract pipeline). See §5.1.
2. **Elevation data source \& fallback behavior**: Local-first, dual-source strategy — local SRTM tiles (`.hgt`/GeoTIFF) bundled with each trip's bounding-box extraction are the primary source, read via `rasterio`/`srtm.py`. open-elevation.com is a secondary fallback used only for missing/imprecise local data or data voids, with results cached locally so a coordinate is never re-requested. If both sources fail for a coordinate, the routing core falls back to a flat-earth assumption (0.0m elevation change) rather than stalling or erroring. Required starting at M1 (FR1, FR2) — see §5.1, §7, §8.
3. **Multi-user/accounts**: Required, not deferred — shared routes are a must-have for the Professional Tour Planner persona. See FR19/FR20, §3.2.
4. **Map tile source**: Self-hosted tiles generated from raw OSM extracts via one shared pipeline, not pulled from a third-party rendered-tile endpoint — Desktop/Mobile generate locally per trip bounding box; Web (no local generation path) fetches from a Render-hosted, on-demand, bbox-scoped server-side cache running the same pipeline, which Desktop/Mobile can also use as their offline-bundle origin. Not a standing global tile server. See §5.2, §5.3, §7.
5. **Flutter map package**: `flutter\_map`. See §5.3.
6. **Share vs. sync**: A share (FR20) stays the simple one-way, no-account-needed view case, as originally assumed. An account holder's own cross-device sync is a distinct, separate capability (FR21) rather than something a share implies. Resolved by splitting these into two FRs instead of overloading one — see §4.3.
7. **Account/sync/sharing backend infrastructure**: Render hosts the FastAPI layer, its Postgres database, and the Flutter Web static build (Starter web service + Starter Postgres + a free static site) — see §5.2. Chosen over self-hosting on Greg's own infrastructure for ease of implementation, and because Render's fixed per-instance pricing bounds cost predictably under the anonymous traffic the guest tier (FR22) introduces.
14. **Cross-device sync conflict resolution**: Whole-trip reconciliation is a user-facing choice, not silent last-write-wins — the version-check flow (FR32), run both on open and immediately before save, notifies the user when the server has a newer version and lets them save-as (keep both) or overwrite. The on-save check specifically catches parallel edits where two devices opened the same version, which an open-only check would miss. Any modified trip attribute, not just a whole-trip edit, is reconciled the same way; the system does not attempt to detect or merge which specific segment/field changed — by design, to keep the reconciliation UX simple rather than adding per-field diffing complexity. See §4.3 FR32, §4.4, §7.
16. **Local-first scope, revisited (2026-07-10)**: Local-first is a hard guarantee for Desktop and Mobile only. Web was always structurally dependent on the hosted API for compute (no offline OSMnx in a browser); treating that as a narrow "exception" bought nothing once Render/Postgres were already committed for accounts and sync, so Web is now explicitly a conventional, server-backed surface with a normal signed-in session model (cookie + revocable Postgres session row) rather than the storage-avoidance token scheme used elsewhere. Guest sessions (FR22) are unaffected — their statelessness is a privacy guarantee, not a cost-avoidance one. See `ARCHITECTURE.md` §2 (Principles 1 and 6) and §8.1 for the full model.
19. **Contrast-mode preference scope**: An explicit contrast-mode override (Indoor vs. Outdoor) is a synced, account-level preference carried via cross-device sync (FR21), not a per-device local setting — it travels with the signed-in user. The *automatic* contrast default is separate from this synced state and is evaluated fresh per surface/context every time (device type, viewport, and where practical, ambient light or the OS's light/dark setting). See §6, UX.md §4, and the Brand Guide's "Interface Adaptability & Contrast Modes."

### Follow-up (raised by the above decisions)

8. What's the concrete tile-generation tool/workflow for self-hosted, per-trip offline tiles (e.g. `tilemaker` → MBTiles, vs. another pipeline)? Needed starting at M3 — see §8. *(Resolved in shape — Web's tile path is now defined: Desktop/Mobile generate locally per-trip bbox; Web fetches from a Render-hosted FastAPI endpoint that runs the same pipeline server-side, on-demand, and caches the result — bounded, bbox-scoped, not a standing global tile server — which Desktop/Mobile can also use as their offline-bundle origin, unifying the pipeline. The concrete generation tool itself (tilemaker vs. an alternative) remains undecided.)*
9. What service(s), if any, provide lodging/campground data beyond raw OSM tags (FR14)? Is OSM coverage sufficient, or does the Professional Tour Planner persona need a dedicated lodging/campsite data source to hit a "client-ready" bar?
10. What weather data service will back FR15 (Historical Weather averages + Weather Forecast) (e.g. `open-meteo` vs openweathermap)? This is the first non-OSM, non-local external dependency in the core planning flow — how should it interact with the local-first principle (§4.4) and offline behavior? Whichever service is chosen must support the short-TTL, no-bulk-hammering caching discipline for the Weather Forecast set out in the "Responsible use of shared/external open resources" NFR (§4.4) — Historical Weather can be cached long or bundled, but the Forecast cannot.
11. Should cafe/restaurant rest-stops be sourced from OSM tags alone (`amenity=cafe`/`amenity=restaurant`), or does the Professional Tour Planner persona need a richer/curated source (verified hours, reviews) beyond what OSM provides?
12. How is "power efficiency" (§4.4 NFR) actually validated — is there a target metric (battery %/hour, GPS poll interval) and a milestone/test for it, or is this currently just a stated intention with no acceptance criteria?
13. FR30/FR31 (frequently-cycled/greenway/rail-trail preference; popularity/heatmap-style data) are explicitly left for future definition — what data source and scoring approach would even be feasible, and does either require breaking the open-data/local-first bias (§4.4)?
15. What rate-limiting or anti-abuse approach protects the unauthenticated guest-tier compute endpoint (FR22) — per-IP throttling, a proof-of-work/CAPTCHA-style gate, or something else — and at what threshold does it kick in? *(Resolved in shape as of 2026-07-10 — UAT-calibrated mean+2σ threshold with progressive cool-off; see `ARCHITECTURE.md` §8.2. Exact numbers still pending real UAT data.)*
17. Given item 16's Web session now runs as a cookie against the hosted API, and the Flutter Web static build and the hosted API are separate Render origins/services — should they sit behind one apparent origin (reverse proxy / custom domain + rewrite, enabling a same-site cookie), or should the session cookie be cross-site (`SameSite=None; Secure` + full CORS credentialed-request config)? This needs deciding before M6's Web auth work starts, not during it.
18. Now that Web is explicitly not local-first (item 16), does FR18's "as close to Desktop planning parity as practical" still imply any Web offline capability (e.g. service-worker/PWA caching of a signed-in user's own trips), or is Web intentionally online-only, simplifying FR18's scope going into M6?
20. What geocoding service backs location search (FR34) — a self-hosted Nominatim/Photon over the same OSM data, or the public endpoints at low volume — and how does it fit the local-first principle and the responsible-use caching discipline (§4.4)? This is a fourth external dependency alongside tiles, elevation, and weather, and the entry point to every flow.
21. How does start-point/destination search behave offline on Mobile (FR34)? In-bounds search can be served from the trip's bundled extract, but out-of-bounds search inherently needs connectivity — is bundled-extract search sufficient for the offline field case, and must a point-to-point destination (FR35) be resolved before going offline?

\---

## Appendix: Reference

* Full feature list and persona detail: `Cycle Tour Planner.md`
* Architecture summary: `CLAUDE.md`
