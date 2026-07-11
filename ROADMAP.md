# Cycle Tour Planner — Product Roadmap

**Source:** `Cycle Tour Planner PRD.md`
**As of:** 2026-07-11 — scaffolding only (FastAPI health-check stub, default Flutter counter app); no FR work started
**Sequencing:** by dependency, not calendar date (solo project, PRD §8)

A local-first route planner that generates rides around a theme — flattest, most climbing, lowest traffic, fewest turns, most art & history — not a segment feed. This is the build order.

Status legend: **Now** · **Next** · **Later**

---

## Leg 1 — Prove the routing engine (M1 → M2) — *Now*

Confirm OSMnx can actually generate all five MVP themes end to end from a local OSM extract — including the local-first elevation pipeline two of those themes depend on — then wrap the result behind a typed API.

**Deliverables**
- FR1 — Flattest route
- FR2 — Most-climbing route
- FR3 — Lowest-traffic route
- FR4 — Fewest-turns route (maneuver/way-change based, not road curvature)
- FR5 — Most-art/history route
- FR6 — FastAPI endpoint + OpenAPI docs

**Learning goal:** One custom multi-factor OSMnx edge-weighting function per theme; local SRTM-primary / open-elevation.com-fallback elevation sourcing, cached so no coordinate is looked up twice; Pydantic typed request/response models.

---

## Leg 2 — Ship the desktop MVP (M3 → M4) — *Next*

Get a route Greg would actually ride out of the system end to end — rendered in a real client over self-hosted tiles, with a real start/destination entry step, and exported in every format RideWithGPS and a bike computer expect.

**Deliverables**
- FR7 — Route rendering (Desktop)
- FR8 — Toggleable OSM layers
- FR34 — Start point / destination / waypoint entry (geocoded search, map tap, or GPS)
- FR35 — Route shape selection — loop (default) / out-and-back / point-to-point
- FR9 — GPX, TCX, and FIT export

**Learning goal:** `flutter_map` over self-hosted tiles generated from local OSM extracts, per trip bounding box — not a proprietary maps SDK or hosted tile endpoint; a geocoding service (Nominatim/Photon) as the entry point to every routing flow.

**Milestone:** MVP complete at M4 — success criterion: the flattest-theme route exports cleanly as GPX, TCX, and FIT and opens without error in RideWithGPS.

---

## Leg 3 — Multi-day trip logistics (M5) — *Later*

Turn one route into a real multi-day tour: waypoints a route must honor, daily mileage/elevation splitting, surface control, sliding-scale weighting, and the lodging and historical-weather context a tour planner needs to book stays.

**Deliverables**
- FR10 — Waypoints / checkpoints
- FR11 — Daily mileage & elevation splitting
- FR12 — Surface-type scoring
- FR13 — Tour / day / partial-day sliding-scale weighting (elevation, surface)
- FR14 — Lodging & campground data (OSM tags)
- FR15 — Historical Weather (historical/seasonal norms), Desktop first

**Learning goal:** Extend the FR1–FR5 scalar weighting functions to position-varying weights (tour default, overridden per day or partial day) — a harder version of the same exercise, not a rewrite.

---

## Leg 4 — Accounts, sync & Web (M6) — *Later*

Stand up the one part of the stack that's deliberately server-backed: passkey accounts, a Flutter Web client at close-to-Desktop planning parity, cross-device sync with no silent overwrites, and a fully unauthenticated Guest Rider path.

**Deliverables**
- FR19 — Passkey + magic-link auth (biometrics-first, QR cross-device authorization, multi-passkey binding)
- FR20 — Trip sharing (view-only link, no account required to view)
- FR18 — Flutter Web build — close to Desktop planning parity, not just route viewing
- FR21 — Account-holder cross-device sync (desktop, mobile, web)
- FR32 — Version-check on open and on save (save-as vs. overwrite, no silent last-write-wins)
- FR36 — Trip library (list/search/rename/duplicate/delete, share management)
- FR37 — Guest → account claim on first sign-in
- FR22 — Unauthenticated Guest Rider web access (stateless compute, browser-local persistence only)

**Learning goal:** One shared WebAuthn/passkey flow across mobile, desktop, and web, not per-platform bespoke logic — the hardest cross-platform-parity test in the app, and the reason the PRD's risk register flags this as its one high-impact item. Also: Web's conventional server-side session (cookie + Postgres row) is a deliberate departure from the local-first token model used elsewhere, and the guest tier's stateless-compute/browser-local-storage split is its own small pattern to get right.

---

## Leg 5 — Mobile & offline (M7) — *Later*

Take the whole thing on the road: Android/iOS builds with real offline use, and the live Weather Forecast retrofitted onto every client that shipped before it.

**Deliverables**
- FR17 — Android / iOS builds (feature parity for offline trips)
- FR16 — Offline trip download (map + route + content)
- FR15 — Weather Forecast (10-day/hourly) — ships on Mobile, Desktop, and Web (including Guest Rider) simultaneously

**Learning goal:** Power-efficient background GPS/CPU/network use on mobile; the offline-first UX pattern (persistent, unobtrusive connectivity indicator, no feature silently failing, stale-forecast age stamping) rather than treating offline as a degraded error state.

---

## Leg 6 — Content layer (M8) — *Later*

Round out the riding experience once the core planning and trip-management flows are solid.

**Deliverables**
- FR23 — "Building/architectural interest" themed tours (extends FR5's OSM-tag scoring)
- FR24 — POI audio narration
- FR25 — Crowd-sourced route/road/POI feedback (public/private visibility, requires an account)
- FR26 — Full trip export as GeoJSON with attributes

---

## Leg 7 — Streetview imagery & hyperlapse (M9) — *Later*

The one phase left deliberately undesigned: point-of-view imagery during planning, and a Street View hyperlapse preview of a planned route.

**Deliverables**
- FR27 — Streetview-style imagery during planning
- FR28 — Desktop-only streetwarp-cli hyperlapse preview (TBD)

**Flag:** Both are candidate premium-tier features under the proposed (undecided) premium concept in PRD §3.6. FR28 depends on a paid Google Street View Static API key and `ffmpeg` — the only paid, non-open dependency anywhere in the stack — and FR27 may share that same dependency; confirm before scoping FR27 whether a cheaper/open alternative (e.g. Mapillary) covers it instead. Implementation for FR28 is left undesigned by choice until this phase actually starts.

---

## Leg 8 — Premium trip version history (M10, TBD — not committed) — *Later*

A proposed premium tier, scheduled after every other milestone since it isn't committed at all yet.

**Deliverable**
- FR33 — Automatically retain a trip's last 5–10 versions for rollback (account holders only)

**Flag:** Explicitly monetized, which conflicts with PRD §3.3's "no monetization of any kind" out-of-scope statement — flagged there and here, not resolved. Whether this ships at all, and as what, is unresolved.

---

## Before You Get There — open questions gating each leg

Pulled from the PRD's risk register (§7) and open questions (§9) — unresolved items that should be settled before, not during, the leg they gate.

- **Gates Leg 1:** OSM elevation, POI, and surface tags may be too sparse or inconsistent for reliable multi-factor weighting. Validate the elevation pipeline and art/history tag scoring before the API and client layers are built on top of them.
- **Gates Leg 2:** The concrete tile-generation tool for self-hosted, per-trip offline tiles is still undecided (`tilemaker` → MBTiles vs. another pipeline — §9 item 8; the Desktop/Mobile-vs-Web pipeline *shape* is resolved). Also needed by M3: which geocoding service backs FR34's location search — a self-hosted Nominatim/Photon instance vs. the public endpoints at low volume (§9 item 20) — and how Mobile offline search behaves for out-of-bounds queries (§9 item 21).
- **Gates Leg 3:** Weather provider for FR15 is still undecided (`open-meteo` vs. OpenWeatherMap — §9 item 10). Also open: whether OSM lodging/campsite tags alone clear a "client-ready" bar for FR14, or a dedicated data source is needed (§9 item 9); and whether cafe/restaurant rest-stops need a richer/curated source beyond OSM tags (§9 item 11).
- **Gates Leg 4:** Flutter passkey-plugin maturity is uneven between desktop and mobile — the PRD's mitigation is to spike passkey auth early, before M5, rather than discover the gap at M6. Also unresolved before M6's Web auth work starts: the cross-origin/cookie strategy for Web's signed-in session — same-site reverse proxy vs. cross-site `SameSite=None` cookies (§9 item 17) — and whether Web needs any offline capability at all now that it's explicitly not local-first (§9 item 18).
- **Gates Leg 5:** Power efficiency is currently a stated intention with no target metric or acceptance criteria (battery %/hour, GPS poll interval) — define one before validating M7 (§9 item 12).
- **Gates Leg 7:** FR27 (streetview-style imagery) may share FR28's paid Street View Static API dependency. Confirm whether FR27 can use a cheaper/open alternative (e.g. Mapillary) before scoping it separately.
- **Gates Leg 8:** Whether a paid premium tier is pursued at all conflicts with the no-monetization stance in §3.3 — resolve that tension before committing FR33 to a real milestone.

---

*Cycle Tour Planner — personal, local-first, solo learning project. Generated from `Cycle Tour Planner PRD.md` §3–§9.*
