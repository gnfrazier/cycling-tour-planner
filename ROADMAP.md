# Cycle Tour Planner — Product Roadmap

**Source:** `Cycle Tour Planner PRD.md`
**As of:** 2026-07-04 — no code written yet
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
- FR4 — Fewest-turns route
- FR5 — Most-art/history route
- FR6 — FastAPI endpoint + OpenAPI docs

**Learning goal:** One custom multi-factor OSMnx edge-weighting function per theme; local SRTM-primary / open-elevation.com-fallback elevation sourcing, cached so no coordinate is looked up twice; Pydantic typed request/response models.

---

## Leg 2 — Ship the desktop MVP (M3 → M4) — *Next*

Get a route Greg would actually ride out of the system end to end — rendered in a real client over self-hosted tiles, exported as a GPX file that opens cleanly in RideWithGPS.

**Deliverables**
- FR7 — Route rendering (Desktop)
- FR8 — Toggleable OSM layers
- FR9 — GPX export

**Learning goal:** `flutter_map` over self-hosted tiles generated from local OSM extracts, per trip bounding box — not a proprietary maps SDK or hosted tile endpoint.

**Milestone:** MVP complete at M4 — success criterion: the flattest-theme route opens without error in RideWithGPS.

---

## Leg 3 — Multi-day trip logistics (M5) — *Later*

Turn one route into a real multi-day tour: waypoints a route must honor, daily mileage/elevation splitting, surface control, and the lodging and weather context a tour planner needs to book stays.

**Deliverables**
- FR10 — Waypoints / checkpoints
- FR11 — Daily mileage & elevation splitting
- FR12 — Surface-type scoring
- FR13 — Tour / day / partial-day weighting
- FR14 — Lodging & campground data
- FR15 — Desktop historical weather

**Learning goal:** Extend the FR1–FR5 scalar weighting functions to position-varying weights (tour default, overridden per day or partial day) — a harder version of the same exercise, not a rewrite.

---

## Leg 4 — Accounts, sharing & mobile (M6 → M7) — *Later*

Let a tour planner share a trip with a client, and take the whole thing on the road: passkey auth across every target, then Android/iOS builds with real offline use.

**Deliverables**
- FR18 — Passkey + magic-link auth
- FR19 — Trip sharing
- FR16 — Offline trip download
- FR17 — Android / iOS builds
- FR15 — Mobile 10-day/hourly forecast

**Learning goal:** One shared WebAuthn/passkey flow across mobile and desktop, not per-platform bespoke logic — the hardest cross-platform-parity test in the app, and the reason the PRD's risk register flags this as its one high-impact item.

---

## Leg 5 — Content layer & the unknown road ahead (M8 → M9) — *Later*

Round out the riding experience, then take on the one phase left deliberately undesigned: a Street View hyperlapse preview of a planned route.

**Deliverables**
- FR21 — POI audio narration
- FR22 — Crowd-sourced feedback
- FR23 — GeoJSON export
- FR24 — Streetview-style imagery
- FR25 — Streetwarp-cli hyperlapse (desktop only, TBD)

**Flag:** M9 depends on a paid Google Street View Static API key and `ffmpeg` — the only paid, non-open dependency anywhere in the stack. Left undesigned by choice until this phase actually starts.

---

## Before You Get There — open questions gating each leg

Pulled from the PRD's risk register (§7) and open questions (§9) — unresolved items that should be settled before, not during, the leg they gate.

- **Gates Leg 1:** OSM elevation, POI, and surface tags may be too sparse or inconsistent for reliable multi-factor weighting. Validate the elevation pipeline and art/history tag scoring before the API and client layers are built on top of them.
- **Gates Leg 2:** No tile-generation tool is chosen yet for self-hosted, per-trip offline tiles (e.g. `tilemaker` → MBTiles vs. another pipeline) — needed starting at M3.
- **Gates Leg 3:** Weather provider for FR15 is still undecided (`open-meteo` vs. OpenWeatherMap) — the first non-OSM, non-local external dependency in the core planning flow. Also open: whether OSM lodging/campsite tags alone clear a "client-ready" bar for FR14, or a dedicated data source is needed.
- **Gates Leg 4:** Flutter passkey-plugin maturity is uneven between desktop and mobile — the PRD's mitigation is to spike passkey auth early, before M5, rather than discover the gap at M6. Also unresolved: whether a share is a one-way view link (assumed) or implies two-way account sync — confirm before M6.
- **Gates Leg 5:** FR24 (streetview-style imagery) may share FR25's paid Street View Static API dependency. Confirm whether FR24 can use a cheaper/open alternative (e.g. Mapillary) before scoping it separately.

---

*Cycle Tour Planner — personal, local-first, solo learning project. Generated from `Cycle Tour Planner PRD.md` §3–§9.*
