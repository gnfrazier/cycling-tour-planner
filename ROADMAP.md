# Cycle Tour Planner — Product Roadmap

**Source:** `Cycle_Tour_Planner_PRD.md` v2.1 + `ARCHITECTURE.md` v1.0
**As of:** 2026-07-24 — MVP built (M1→M4: routing core, FastAPI, Desktop client, export), with a known gap list (below) against the PRD's full M3 deliverable set. Post-MVP hardening is complete: a security review pass, initial bug fixes, the startup-wait UX (FR48), a QA pass on route-generation correctness, and the new reset-controls action (FR49). Leg 3 is next
**Sequencing:** by dependency, not calendar date (solo project, PRD §8)

A local-first route planner that generates rides around a theme — flattest, most climbing, lowest traffic, fewest turns, most art & history — not a segment feed. Desktop and Mobile run the routing core *on the device* inside a local sidecar process (`ctp-service` wrapping `ctp-core`); Web is a deliberate, stated exception that always computes server-side on Render. This is the build order.

Status legend: **Done** · **Now** · **Next** · **Later**

---

## Leg ↔ Milestone map

**Leg numbers and PRD Milestone (`M#`) numbers are two different sequences — they only happen to line up for Leg 1/Leg 2.** A Leg is this document's own dependency-ordered build package; a Milestone is the PRD's (§8) numbering. **Leg 3 is Milestone 5, not Milestone 3.** Check this table — not the Leg number alone — before pulling a milestone's deliverable list from the PRD, and read each Leg section's own **Milestone(s):** line below for the same reason.

| Leg | Milestone(s) | Status |
|-----|--------------|--------|
| Leg 1 | M1, M2 | Done |
| Leg 2 | M3, M4 | Done, with open gaps |
| *(Post-MVP hardening — not a numbered leg or milestone)* | between M4 and M5 | Done |
| **Leg 3** | **M5** | Now |
| Leg 4 | M6 | Later |
| Leg 5 | M7 | Later |
| Leg 6 | M8 | Later |
| Leg 7 | M9+ | Later |

---

## Leg 1 — Prove the routing engine (M1 → M2) — *Done*

**Milestone(s): M1, M2**

Confirm OSMnx can actually generate all five MVP themes end to end from a local OSM extract — including the local-first GEDTM30 elevation pipeline two of those themes depend on — then wrap the result behind a typed API. Also lay down two architectural seams the design deliberately front-loads here, before either is needed, because retrofitting them later is far more expensive (PRD §5.1–§5.2, Architecture D9/D10).

**Deliverables**
- FR1 — Flattest route
- FR2 — Most-climbing route
- FR3 — Lowest-traffic route
- FR4 — Fewest-turns route (maneuver/way-change based, computed at graph-simplification time — not road curvature)
- FR5 — Most-art/history route
- FR6 — FastAPI endpoint + OpenAPI docs
- **Seam 1 — `weights.at(position)` lookup**: every theme is a `WeightProfile` instance fed to one scoring function, resolved per edge rather than per solve. Return a constant profile now; FR13 at M5 becomes a one-function change, not a rewrite (Architecture §5.5)
- **Seam 2 — elevation interface**: client/core talk to elevation through one interface from day one, even though MVP resolves it via direct OpenTopography calls. M6's shared Render cache then changes a lookup step and a base URL, not the caller (PRD §5.2, Architecture §9.1)
- **`ctp-core` as a pure library** (Architecture P1): no FastAPI import, no request/user/session concepts — enforced as a lint/CI check (`ctp-core` may not import `fastapi`), not a code-review hope
- Built-in OSM lookups (FR5's art/history tags, FR14's lodging tags) implemented against the same `EdgeDataProvider`/`NodeDataProvider` protocols a future plugin would use (Architecture §10.2, D9) — proves the extension points are real before M9 needs them

**Learning goal:** One custom multi-factor OSMnx edge-weighting function per theme, driven by data (`WeightProfile`) rather than one algorithm per theme; local-first GEDTM30 elevation via `rasterio`, with a flat-earth (0.0m) void fallback and **no secondary elevation service** (GEDTM30 needs none); Pydantic typed request/response models.

**Note:** the elevation source changed from an earlier SRTM-primary/open-elevation.com-fallback design to GEDTM30 via OpenTopography as the single best-available source — no fallback service exists or is needed.

---

## Leg 2 — Ship the desktop MVP (M3 → M4) — *Done, with open gaps*

**Milestone(s): M3, M4**

Get a route Greg would actually ride out of the system end to end — rendered in a real client over self-hosted tiles, with a real start/destination entry step, a populated app on first open with zero downloads, and exported in every format RideWithGPS and a bike computer expect.

**Deliverables shipped**
- FR7 — Route rendering (Desktop)
- FR34 — Start point / destination entry (geocoded search via OSMnx's own `geocoder.geocode()` wrapper over Nominatim, or map tap)
- FR35 — Route shape selection — loop (default) / out-and-back / point-to-point
- FR39 — Local data pruning, Desktop half (North Carolina only — see gap below)
- FR9 — GPX, TCX, and FIT export
- FR47 — Target distance control (Fibonacci-stepped slider, 10km–300km/180mi), added post-initial-build
- FR48 — Routing-engine startup wait: escalating cycling-themed messaging instead of a fixed-timeout hard failure, added post-initial-build
- FR49 — Reset route-planning controls: one action reverts theme, shape, start, destination, and target distance to their defaults and clears any generated route, added post-initial-build
- Packaging decision resolved: **PyInstaller**, sidecar built `--onedir` and smoke-tested in CI (`.github/workflows/desktop-build.yml`) — the gating question below is settled, not open

**Known gaps against the PRD's full M3 list** (MVP's own success criterion — flattest route exports and opens in RideWithGPS — is met; these are real, still-open deliverables, not polish)
- FR8 — Toggleable OSM layers not built. The map currently renders one fixed layer set (tiles, route line, markers), no per-category visibility control
- FR38 — First-start region download is North Carolina only; Wisconsin and Southern California show as "coming soon" placeholders (`manage_data_screen.dart`), not wired to live OpenTopography downloads
- FR43 — Unsatisfiable-constraint explanation not built
- FR44 — Turn-by-turn cue sheet not built
- **Prototype the local sidecar on Android** (Architecture §4.1, A1) — not yet started; still needed before iOS's harder constraint is faced at M7

**Learning goal:** `flutter_map` over self-hosted tiles generated from local OSM extracts — not a proprietary maps SDK or hosted tile endpoint; the routing core shipped as a standalone frozen binary (PyInstaller) launched as a loopback-bound child process, so the Flutter client's `RoutingClient` speaks one HTTP transport regardless of platform; geocoding resolved as OSMnx's built-in Nominatim wrapper, no self-hosted Nominatim/Photon instance needed.

**Milestone:** MVP complete at M4 — success criterion: the flattest-theme route exports cleanly as GPX, TCX, and FIT and opens without error in RideWithGPS.

---

## Post-MVP hardening (M1–M4 → Leg 3) — *Done*

**Milestone(s): none — sits between M4 and M5, not itself a numbered PRD milestone**

Between the initial M1–M4 build and starting Leg 3, the app went through a QA/hardening pass rather than moving straight to new PRD scope. Not itself a numbered PRD leg, but real work that gated starting Leg 3 on a stable base — now closed out.

**Shipped**
- Security review pass: sidecar-only route gating enforced at registration (not just guarded), tile proxy given a timeout/bounds check, route-generation inputs bounded (lat/lon/target-distance), request body size cap
- Initial bug fixes: default bounding box was too small, map had no zoom controls, destination point wasn't clearing on shape re-selection
- FR48 startup-wait UX (see Leg 2)
- QA pass on route-generation correctness (tracked against a hand-testing pass over real Marion→Blowing Rock, NC terrain):
  - loop routes degenerating into a visual out-and-back (return leg now avoids retracing the outbound leg when a genuine alternative road exists, `ctp_core/routing.py`)
  - theme had no effect on loop/out-and-back route selection (the turnaround-node search was theme-blind; it now picks the theme-cheapest node within a distance band instead of always the same node)
  - route polylines and exports were straightened between intersections, understating curvy-road distance (`_path_geometry` now follows each edge's real OSM geometry instead of just its endpoints)
  - a start/destination outside the served bounding box silently snapped to the nearest in-bounds node instead of erroring
- FR49 reset-controls action (see Leg 2), plus a client wire-boundary fix so point-to-point requests can never pick up a stray target-distance value

---

## Leg 3 — Multi-day trip logistics (M5) — *Now*

**Milestone(s): M5**

Turn one route into a real multi-day tour: waypoints a route must honor, daily mileage/elevation splitting, surface control, sliding-scale weighting, route alternatives, group-size awareness, and the lodging and historical-weather context a tour planner needs to book stays.

**Deliverables** (matches the PRD's own M5 row, §8 — previously this list silently dropped FR42/FR46, which the PRD's milestone table includes; restored here, ordered by build dependency rather than the PRD's listing order)
- FR10 — Waypoints / checkpoints
- FR11 — Daily mileage & elevation splitting
- FR12 — Surface-type scoring
- FR13 — Tour / day / partial-day sliding-scale weighting (elevation, surface)
- FR42 — Route alternatives & variants (a scoped re-route proposed via FR13, shown ghost-vs-bold alongside the current route; depends on FR13 existing first)
- FR14 — Lodging & campground data (OSM tags — resolved, no dedicated data source needed)
- FR46 — Group-size-aware planning (rider-band informs lodging/campground sizing from FR14, road-width/regroup cautions, and seeds day mileage/climb defaults that FR13 can still override)
- FR15 — **Historical Weather** only at this leg (seasonal norms via Open-Meteo), Desktop first. Weather Forecast (10-day/hourly) ships later, at M7, across all clients simultaneously

**Learning goal:** Exercise Leg 1's `weights.at(position)` seam for real — resolve tour-default vs. day-override vs. segment-override profiles per edge. Because that lookup was built at M1 returning a constant, this is a change to one function, not a new solver (Architecture §5.5). Weather provider is resolved as Open-Meteo (no longer an open question).

---

## Leg 4 — Accounts, sync & Web (M6) — *Later*

**Milestone(s): M6**

Stand up the one part of the stack that's deliberately server-backed: passkey accounts, a Flutter Web client at close-to-Desktop planning parity, cross-device sync with no silent overwrites, a fully unauthenticated Guest Rider path, and the shared elevation/tile cache that retires the MVP's disposable per-device OpenTopography calls.

**Deliverables**
- FR19 — Passkey + magic-link auth (biometrics-first, QR cross-device authorization, multi-passkey binding)
- FR20 — Trip sharing (view-only link, no account required to view)
- FR18 — Flutter Web build — close to Desktop planning parity, not just route viewing. Server-computed via hosted `ctp-service`, since Web has no local sidecar (PRD §3.2)
- FR21 — Account-holder cross-device sync (desktop, mobile, web) via a canonical Postgres copy; also carries layer-preference (FR8) and contrast-mode sync
- FR32 — Version-check on open and on save, implemented as a conditional write (`PUT` + expected version, `409 Conflict` on mismatch) so the check and the write can't race (Architecture §8.4, D7)
- FR36 — Trip library (list/search/rename/duplicate/delete, share management)
- FR37 — Guest → account claim on first sign-in
- FR22 — Unauthenticated Guest Rider web access (stateless compute, browser-local persistence only, zero server-side trace — Architecture P4)
- **Shared Render elevation/tile cache**, superseding FR38: any tile fetched by any user is cached server-side and served to everyone after. Enables the packaged North Carolina bundle with Marion, NC as the default start

**Learning goal:** One shared WebAuthn/passkey flow across mobile, desktop, and web — the hardest cross-platform-parity test in the app. Also: Web's conventional cookie (`SameSite=None; Secure`) + Postgres session row is a deliberate departure from the local-first token model used elsewhere, requiring a strict CORS origin allowlist (never a wildcard) since the static build and API are separate Render origins; the guest tier's stateless-compute/browser-local-storage split; and an in-memory per-IP rate limiter (`slowapi`) that is correct only on a single Render instance — a deployment invariant, not a tuning knob.

---

## Leg 5 — Mobile & offline (M7) — *Later*

**Milestone(s): M7**

Take the whole thing on the road: Android/iOS builds with real offline use, in-ride live navigation, and the live Weather Forecast retrofitted onto every client that shipped before it. This leg is gated by the single largest open technical risk in the project.

**Deliverables** (matches the PRD's own M7 row, §8 — previously this list silently dropped FR45, which the PRD's milestone table includes; restored here)
- FR17 — Android / iOS builds (feature parity for offline trips)
- FR16 — Offline trip download (map + route + content)
- FR15 — Weather Forecast (10-day/hourly) — ships on Mobile, Desktop, and Web (including Guest Rider) simultaneously
- FR39 — Local data pruning, Mobile half (Desktop half shipped at M3)
- FR45 — In-ride live navigation: next-maneuver/upcoming-waypoint/climb readout, cue sheet usable by mileage alone, and graceful GPS-loss degradation (map freezes at last-known position, states the loss once, passively)
- **Resolve the iOS sidecar strategy** (Architecture §4.1, A1 — HIGH severity): iOS forbids the child-process model Android validated at M3. Pick one of three named options before this leg starts: an iOS-only embedded interpreter, iOS-online-only (like Web, breaking the offline guarantee on that one platform), or precompute-and-download (route generated elsewhere, offline use covers *viewing/following*, not on-device generation)

**Learning goal:** Power-efficient background GPS/CPU/network use on mobile, with a stated (if still coarse) acceptance bar — runs without errors or crashes while the device's OS-level power-saving mode is active; the offline-first UX pattern (persistent, unobtrusive connectivity indicator, no feature silently failing, stale-forecast age stamping) rather than treating offline as a degraded error state.

---

## Leg 6 — Content layer (M8) — *Later*

**Milestone(s): M8**

Round out the riding experience once the core planning and trip-management flows are solid.

**Deliverables**
- FR24 — POI audio narration
- FR25 — Crowd-sourced route/road/POI feedback (public/private visibility, requires an account)
- FR26 — Full trip export as GeoJSON with attributes
- FR23 — "Building/architectural interest" themed tours (extends FR5's OSM-tag scoring) — *not explicitly placed in the PRD's milestone table; grouped here provisionally as a P2 content feature. Confirm placement before this leg starts.*
- FR29 — Group rider-skill-profile-aware route suggestions (P3, stretch) — *also unplaced in the milestone table; provisional here.*
- FR40 / FR41 — Rider profile data + per-field sharing grants — *core, not a plugin (PRD §3.5), but likewise absent from the milestone table. Natural home is here or alongside M6's account work, since FR41 reuses FR20's share-token pattern; confirm before scoping.*

---

## Leg 7 — Plugins (M9+) — *Later*

**Milestone(s): M9+**

Stand up the plugin architecture, then take up individual plugins as each becomes worth building. Two runtimes, not one: output/integration plugins run Flutter-side holding their own OAuth tokens; data-provider plugins run Python-side against `ctp-core`'s provider interfaces built at M1 (Architecture §10).

**Deliverables**
- Plugin infrastructure: `PluginRegistry` (Dart) discovering `OutputIntegration` implementations; provider-interface conformance for anything Python-side
- FR27 — Streetview-style/point-of-view imagery during planning
- FR28 — Desktop-only `streetwarp-cli` hyperlapse preview — depends on a paid Google Street View Static API key and `ffmpeg`, the only paid non-open dependency anywhere in the stack
- FR30 — Route/segment suggestions weighted toward frequently-cycled routes, greenways, rail trails
- FR31 — Route/segment popularity (heatmap-style) data as a routing input — no OSM-native equivalent
- FR33 — Trip version history: retain a trip's last 5–10 versions for rollback, building on FR32's server-stored versions

**Flag:** FR33 is explicitly monetized, which conflicts with PRD §3.4's "no monetization of the core application" stance — the plugin model (§3.5) is the proposed resolution (plugins sit outside the core's data-licensing obligations), but whether a *paid* plugin is actually pursued remains unresolved, not decided. FR27/FR28 share a paid Street View Static API dependency; confirm whether a cheaper/open alternative (e.g. Mapillary) covers FR27 before scoping it separately from FR28.

---

## Before You Get There — open questions gating each leg

Pulled from the PRD's risk register (§7) and open questions (§9), and the Architecture doc's risks (§11) and open questions (§13) — unresolved items that should be settled before, not during, the leg they gate.

- **Gates Leg 1 (M1, M2):** Resolved — the elevation and POI-tag pipelines proved out within M1, and the `ctp-core`/FastAPI boundary held through the security-review pass.
- **Gates Leg 2 (M3, M4):** The packaging decision is resolved (PyInstaller, `--onedir`, CI-smoke-tested); whether the sidecar ships inside the installer vs. downloads on first run (Architecture §13 Q3) is still open. The concrete per-trip tile-generation tool (`tilemaker` → MBTiles vs. an alternative) is **not** needed yet — FR38 ships fixed whole regions, not per-trip bbox generation, so that question is still deferred to Leg 4/M6. The post-MVP hardening pass is closed out, but FR8/FR43/FR44 — real M3 deliverables, not stretch goals — remain unbuilt; still worth an explicit, tracked decision (build before Leg 3, or formally defer) rather than leaving them implicitly open.
- **Gates Leg 3 (M5):** Largely de-risked already: weather (Open-Meteo) and lodging (OSM tags) are resolved, not open questions, and FR13's position-varying weighting rides the seam built at M1. FR42 (route alternatives) has an in-leg dependency, not an external gate — it needs FR13 built first, so sequence it after. No major external gating item remains here.
- **Gates Leg 4 (M6):** Flutter passkey-plugin maturity is uneven between desktop and mobile — the PRD's mitigation is to spike passkey auth early, before M5, not to discover the gap at M6. Also unresolved before M6's Web work starts: verify the cross-site cookie CORS allowlist is strict (never a wildcard) before shipping, and treat "one Render instance" as a hard deployment invariant for the rate limiter — the redesign trigger is a second instance existing, not abuse being observed (Architecture A4).
- **Gates Leg 5 (M7):** **The single largest open technical risk in the project** — iOS cannot spawn the sidecar the way Android does (Architecture §4.1, A1, HIGH severity). Three named options exist; none is chosen. Do not let iOS's constraint get discovered late — the Android prototype at M3 is meant to surface everything *except* this platform-specific gap early, leaving iOS as the one deliberately deferred decision. FR45 (in-ride live navigation) additionally depends on FR44's cue sheet, already shipped at M3.
- **Gates Leg 6 (M8):** FR23, FR29, FR40, and FR41 all lack an explicit milestone assignment in the PRD's own milestone table (§8) despite being scoped functional requirements — confirm intended placement (this leg vs. folded into M6's account work for FR40/FR41) before treating the provisional grouping above as final.
- **Gates Leg 7 (M9+):** Whether a paid plugin (FR33) is pursued at all sits in tension with §3.4's no-monetization-of-the-core stance — the plugin model is the proposed-but-unconfirmed resolution. FR27/FR28's shared paid Street View Static API dependency needs an open-alternative check (Mapillary) before scoping. Also open and unblocking until M9: whether the plugin model needs a formal interface/SDK spec or the first plugin defines it by example; which indoor ride simulators (Zwift, TrainerRoad, RGT, others) are actually in scope; and plugin distribution mechanics (pub.dev + PyPI vs. a bundled registry — Architecture §13 Q5).

---

*Cycle Tour Planner — personal, local-first, solo learning project. Generated from `Cycle_Tour_Planner_PRD.md` v2.1 §3–§9 and `ARCHITECTURE.md` v1.0 §2–§13.*
