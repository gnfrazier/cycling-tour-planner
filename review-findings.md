# Cycle Tour Planner — Code, Test Coverage & UX Review

**Date:** 2026-07-24
**Scope:** Full backend (`backend/ctp_core/`, `backend/ctp_service/`), full Flutter client (`client/lib/`), both test suites, and a UX review against this project's own stated design principles (`UX.md`, PRD §6).
**Method:** Read-only review. No code changes made. Findings below are read against `ROADMAP.md`'s explicit "known gap" list and README's "Scope notes for this milestone" — deliberate, tracked M1–M4 simplifications (dev-mode tile proxy, minimal `sidecar_entrypoint.py`, hand-started backend instead of a spawned sidecar, NC-only region data, FR8/FR43/FR44 not yet built) are **not** re-listed as findings here. The highest-severity claims below were independently re-verified against the current source rather than taken on the reviewing agents' word alone (see the note at the top of each of those findings).

**Current state at time of review:** backend 54 tests passing (`uv run pytest --collect-only -q`; note the README's "38 tests" figure is stale), client 11 tests passing across 7 files (`flutter test`). `flutter analyze` clean.
**State after the fix pass (§0):** backend 111 tests passing (1 skipped — the real-raster test needing a locally-extracted GEDTM30 tile), client 23 tests passing across 13 files. `flutter analyze` clean throughout.

---

## 0. Fix pass status (2026-07-25, branch `code-review-fixes`)

All HIGH and MEDIUM findings below (backend, client, and UX) were re-verified against `main` as of commit `cd31d1f` ("Leg 3 of roadmap.") — which landed a substantial amount of new work (multi-day trips, weather, surface-preference scoring) between the original review and this fix pass — and then fixed. None turned out to be no-longer-applicable; the Leg 3 changes didn't remove any of the affected code paths, and in one case (surface scoring, U2) actually made the fix more directly achievable by adding the `_surface_class` machinery the fix now reuses the pattern of.

Each fixed finding below is marked **Status: Fixed** with a one-line note on the actual fix and its test. LOW-severity findings and the test-coverage-gap lists (§3) are unchanged from the original review — out of scope for this pass. Backend fixes are in commit `0cc41d2`; client fixes are in commit `7a1c139`, both on `code-review-fixes`.

---

## 1. Backend Code Review

### 1.1 High severity

**B1 — Unreachable routes crash with a raw 500 instead of a clean 400.**
`backend/ctp_core/routing.py` (`_shortest_path`, called from the `POINT_TO_POINT`/`OUT_AND_BACK`/`LOOP` branches) + `backend/ctp_service/app.py:154-157`.
`nx.shortest_path(..., weight="cost")` raises `networkx.exception.NetworkXNoPath` when source and target sit in different connected components of the graph — a real scenario for an ~80km bike-network bbox (river crossings, isolated cul-de-sacs, highway-only barriers). **Verified independently:** `NetworkXNoPath` is not a `ValueError` subclass (`issubclass(nx.NetworkXNoPath, ValueError) == False`), so `app.py`'s `except ValueError as exc: raise HTTPException(400, ...)` does not catch it, and the request falls through to FastAPI's default handler as an opaque 500. Affects point-to-point with an arbitrary destination, out-and-back with an explicit `end`, and loop/out-and-back turnaround-node lookups landing in a disconnected component.
*Fix shape:* catch `nx.NetworkXNoPath` (and probably `nx.NodeNotFound`) alongside `ValueError` in `app.py`'s `_solve()` handler, or normalize it to a `ValueError` at the `ctp_core` boundary so the service layer's existing exception-mapping stays a single pattern.
**Status: Fixed.** `_shortest_path` (`routing.py`) now catches `nx.NetworkXNoPath` and re-raises `ValueError` — normalized at the `ctp_core` boundary, so it covers `/routes/generate` and, since `trips.py` reuses the same `_shortest_path`, `/trips/generate`/reroute too, without touching app.py's four separate `except ValueError` blocks. New test: `test_shortest_path_raises_value_error_not_networkx_no_path_when_disconnected`.

### 1.2 Medium severity

**B2 — Request body-size cap is bypassable.** `backend/ctp_service/app.py:57-72` (`MaxBodySizeMiddleware`).
**Verified independently:** the middleware only inspects the declared `Content-Length` header before the body is read. A request using chunked transfer-encoding (no `Content-Length`), or one that simply understates the header, sails through unchecked — defeating the stated purpose. The check needs to bound actual bytes read from the ASGI `receive` stream, not just the declared length.
**Status: Fixed.** `MaxBodySizeMiddleware` now wraps `receive` and counts actual bytes as they stream in, aborting with 413 the moment the real total crosses the cap regardless of the header. New test: `test_body_size_cap_enforced_even_without_a_content_length_header`.

**B3 — `app.state.routes` is an unbounded, never-evicted in-memory dict.** `backend/ctp_service/app.py:108,159`.
Every successful `/routes/generate` call adds an entry keyed by UUID; nothing ever removes one. Fine for a short dev session, but unbounded memory growth with no TTL/LRU/cap over a long-running sidecar — and this pattern would carry straight into hosted mode (a shared, multi-tenant server) if not addressed first. Not one of the pre-approved "known simplification" items in ROADMAP/README, so it doesn't get a pass the way the tile proxy does.
**Status: Fixed** — and widened: Leg 3 added an identical `app.state.trips` dict with the same unbounded-growth shape, fixed the same way. Both now go through a shared `_store_bounded()` helper (oldest-first eviction past a cap — 200 for routes, 50 for the heavier trips). New test: `test_store_bounded_evicts_oldest_entry_past_the_cap`.

**B4 — NaN nodata sentinels silently defeat the elevation void-fallback policy.** `backend/ctp_core/elevation.py:78-80`.
**Verified independently** (read the exact code): `if ds.nodata is not None and value == ds.nodata: return 0.0`. For a GeoTIFF whose nodata sentinel is `NaN` (common for float32/64 rasters), `value == nan` is always `False` under IEEE754, so this check never fires for such rasters and a raw `NaN` elevation is returned instead of the documented 0.0 flat-earth fallback (Architecture §5.4's explicit promise). That `NaN` then flows into the elevation-gain calculation and `cost` scoring for edges near the void, with NaN-arithmetic behavior that isn't guaranteed to degrade safely.
*Fix shape:* use `math.isnan(value) or value == ds.nodata` (or `np.isnan`), not just `==`.
**Status: Fixed** exactly as suggested (`math.isnan(value) or (ds.nodata is not None and value == ds.nodata)`). New test `test_nan_nodata_sentinel_falls_back_to_zero` writes a synthetic GeoTIFF with a NaN nodata sentinel and confirms `elevation_at` returns 0.0 (fails without the fix).

**B5 — POI-lookup failures are swallowed with zero logging.** `backend/ctp_core/providers.py:25-28` (`_snap_pois_to_nodes`).
A bare `except Exception: return {}` catches every failure from `ox.features_from_bbox` (Overpass timeouts, network errors, malformed tag queries) with no log line at all — contrast with `elevation.py`, which logs once per missing/unreadable tile before falling back. A genuine Overpass outage is currently indistinguishable from "no art/history POIs in this bbox"; the most-art theme silently degrades to a no-op with no diagnostic trail.
**Status: Fixed.** Added a `logger.warning(..., exc_info=True)` matching `elevation.py`'s existing pattern. New test: `test_poi_lookup_failure_is_logged_not_silently_swallowed` (new file, `test_providers.py` — this module had no test file at all before).

**B6 — `most_art` scoring silently no-ops on missing `bbox`/`providers`.** `backend/ctp_core/scoring.py:92-96`.
Not currently triggered by the shipped API (`app.py` always passes both), but a footgun for any future direct `ctp_core` caller (tests, batch/background solving, a plugin) — a warning or explicit precondition would turn a silent wrong-answer into a visible one.
**Status: Fixed.** `score_edges` now logs a `logger.warning` distinguishing the missing-bbox vs. missing-providers case, and materializes `providers` to a list first (the original `not providers` check on a bare `Iterable` would have been silently wrong for a generator). New tests: `test_score_edges_warns_when_poi_bonus_requested_without_a_bbox`, `..._without_providers`, and a negative check (`..._does_not_warn_for_a_non_art_theme`).

### 1.3 Low severity

**B7 — `build_graph` mutates process-global `osmnx.settings` on every call.** `backend/ctp_core/graph.py:22-24`. Not a live bug today (graph build happens once, synchronously, at startup), but a latent concurrency hazard for any future concurrent multi-region/multi-bbox code path.

**B8 — `load_task.cancel()` on shutdown doesn't actually stop in-flight graph-build work.** `backend/ctp_service/app.py:104-106`. `_build_base_graph` runs via `run_in_threadpool`; `asyncio.Task.cancel()` only affects the awaiting coroutine, not the underlying thread-pool thread, which runs to completion detached from the app. Mostly benign for one long-lived process, but a source of thread buildup in any workflow that spins up/tears down `create_app()` repeatedly (e.g. certain test patterns).

**B9 — `/geocode`'s catch-all maps every failure to 404.** `backend/ctp_service/app.py:194-199`. A transient Nominatim timeout/outage is indistinguishable from "no such place" — a distinct 502/504 for upstream failures would be more honest and easier to debug client-side.

**B10 — `LOOP` shape silently ignores a caller-supplied `end` coordinate.** `backend/ctp_core/routing.py` (loop branch). Only `POINT_TO_POINT`/`OUT_AND_BACK` consult `end`; nothing rejects or warns about a stray `end` sent alongside `shape=loop`. Currently harmless since the shipped client never does this, but there's no defensive validation telling a future caller the field is meaningless there.

---

## 2. Client Code Review

### 2.1 High severity

**C1 — Reset can race an in-flight route generation and let a stale route reappear.** `client/lib/presentation/screens/route_planner_screen.dart:210-214` (`_resetControls`) vs. `client/lib/state/routing_providers.dart` (`RouteGenerationNotifier`).
**Verified independently:** the Generate button is guarded with `onPressed: routeAsync.isLoading ? null : ...` (line 205), but the Reset button (line 213, `onPressed: () => _resetControls(ref)`) has no equivalent guard. If a user clicks Reset while a `generate()` call is still awaiting the backend, `clear()` sets state to `AsyncData(null)` immediately — but the in-flight coroutine is still running, and when it later completes, `state = await AsyncValue.guard(...)` overwrites the just-reset state with a route computed from the pre-reset controls. Net effect: a route can silently reappear on the map moments after the user explicitly reset everything, with the map polyline no longer matching any visible control state.
*Fix shape:* either disable Reset while `routeAsync.isLoading`, or have `generate()` check a generation/version token before committing its result, so a reset (or a second `generate()` call) invalidates any in-flight one.
**Status: Fixed** via a generation counter (bumped by `clear()` and every `generate()` call; a resolving `generate()` only commits its result if its captured generation is still current). Fixed together with U1 below, since both are "the displayed route must never silently outlive what produced it" — see that entry for the second half. New test: `test/state/routing_providers_test.dart`'s `'a reset while generate() is in flight is not clobbered when the stale request resolves'`.

### 2.2 Medium severity

**C2 — Raw exception text reaches the user outside the one path that's handled well.** Multiple sites: `route_planner_screen.dart:36` (`'Export failed: $e'`), `route_planner_screen.dart:226` (route-generation error `Text(err.toString())`), `manage_data_screen.dart:66` (`'Could not clear cache: $e'`), `search_bar.dart:48` (`_error = e.toString()`).
`RoutingClient._errorDetail()` does the right thing for backend-returned failures (translates FastAPI's `detail` field into a clean sentence), but nothing in `routing_client.dart` catches connection-level failures (refused connection, DNS failure, timeout) — those propagate as raw `SocketException`/`ClientException` text straight into these `Text(...)` widgets. Compounds directly with backend finding B1: a disconnected-route 500 would currently render as raw exception text here too.
**Status: Fixed** together with C6 below (same commit, same `_guarded` wrapper). `RoutingClient` now wraps every HTTP call, applying a timeout and catching connection-level failures into a friendly `RoutingClientException` — which every listed call site already renders cleanly via `toString()`, so no changes were needed at those sites themselves. New tests: `'a connection-level failure is surfaced as a friendly RoutingClientException...'` and the `geocode` variant, in `routing_client_test.dart`.

**C3 — `RouteResult.fromJson`'s enum lookups throw an unhandled `StateError` on an unrecognized value.** `client/lib/domain/theme.dart:25-26,47-48` (`firstWhere` with no `orElse`). If the backend ever returns a theme/shape string the client's enum doesn't know about, this throws `StateError: Bad state: no element`, which — via `AsyncValue.guard` — becomes exactly the kind of unhelpful raw text described in C2.
**Status: Fixed.** Both `fromApiValue`s now pass an `orElse` to `firstWhere` throwing a `FormatException` naming the bad value. New test: `'an unrecognized theme/shape value throws a clear FormatException, not a bare StateError'`.

**C4 — `backendReadyProvider` has no failure ceiling, and the widget's error branch is dead code.** `client/lib/state/routing_providers.dart:17-22`, `route_planner_screen.dart` (`error:` branch).
`checkReady()` never throws (it swallows all exceptions internally and returns `false`), so the unbounded `while (!await client.checkReady())` loop can never produce an error state for the `FutureProvider` to surface — meaning the screen's `error: (err, _) => Text('Could not reach the routing engine: $err')` branch is currently unreachable. If the sidecar never starts at all (missing binary, port conflict, a Smart-App-Control-style block — a real scenario this project's own README now documents), the user is stuck on the startup-wait screen indefinitely, past the last scripted message, with no way to distinguish "still normal" from "actually stuck," and no retry/cancel action.
**Status: Partially fixed.** Added non-blocking guidance text that appears past a 5-minute threshold alongside the existing cycling-themed message, pointing at the README's troubleshooting section — this closes the practical "no way to tell slow from stuck" gap without touching the poll loop itself, deliberately: FR48's whole point is that an indefinite wait is correct behavior, and this session's history includes fixing a real false-failure bug from an earlier fixed-timeout design, so a hard failure ceiling or retry/cancel action was intentionally *not* added here to avoid reintroducing that class of bug. The dead `error:` branch on `backendReadyProvider`'s `FutureProvider` is therefore still genuinely unreachable — left as-is, since `checkReady()` swallowing all exceptions is itself correct/intentional for the polling loop, not a bug to fix. New test: `startup_wait_test.dart`.

**C5 — Theme picker carries none of the theme's own color semantics.** `client/lib/presentation/widgets/theme_picker.dart` vs. `client/lib/presentation/widgets/route_map.dart:11-17`.
The Brand Guide assigns each theme a specific color (used for the map polyline), but `ThemePicker`'s `ChoiceChip`s use plain default Material coloring — a user can't learn "teal = flattest" from the control that sets the theme; the color only appears after generation, on the map.
**Status: Fixed** together with U7 below. Moved the color map out of `route_map.dart` into a shared `presentation/theme_colors.dart` (kept out of `domain/theme.dart` so the domain enum stays free of a Flutter dependency) and used it for each chip's avatar/border/selected-color in `ThemePicker`. New test: `'each theme chip shows its Brand Guide color, matching the map polyline palette'`.

**C6 — No HTTP timeouts anywhere in `RoutingClient`.** `client/lib/data/routing_client.dart` (all methods). A stuck backend can hang `generateRoute`/`exportRoute` indefinitely with only a disabled button as feedback — no cancel affordance short of killing the app.
**Status: Fixed** (see C2 above — same `_guarded` wrapper adds a 30s timeout to every call, converting a `TimeoutException` into a friendly `RoutingClientException`).

### 2.3 Low severity

**C7 — Map-tap semantics are asymmetric between shapes with no explanation.** `client/lib/presentation/widgets/route_map.dart` (`onTap`). For Loop/Out-and-back, every tap freely re-sets `start`. For Point-to-point, once both points are set, there's no way to re-pick the start via map tap short of a full Reset or a new geocode search. Not necessarily wrong, but undocumented and untested.

**C8 — No loading/disabled state on export buttons.** `route_planner_screen.dart:16-39`. Rapid repeated clicks can fire duplicate export + file-save-dialog flows.

**C9 — Fragile slider-position derivation.** `route_planner_screen.dart` (target-distance `Slider`, `targetDistanceStepsKm.indexOf(targetKm)` clamped to 0 on a miss). Currently safe since every write goes through the same fixed list, but any future code path setting an arbitrary `double` would silently desync the slider thumb from the displayed label.

**C10 — Map markers carry no semantic/accessibility label.** `route_map.dart` (start/destination `Marker`s). Relies entirely on icon shape + color to distinguish "start" from "destination" for assistive tech.

**C11 — Duplicated zoom-bound magic numbers.** `route_map.dart:20-21` (`_minZoom`/`_maxZoom`), cross-referenced only by a comment to the Python backend's own tile bounds check — a drift between the two would silently produce broken tile requests near the edges.

---

## 3. Test Coverage Analysis

### 3.1 Backend (54 tests collected)

Prioritized gaps:

1. **Disconnected-graph / `NetworkXNoPath` — zero coverage.** Direct trigger for B1. A small synthetic-graph unit test (the file already has this pattern for `_shortest_path_avoiding_edges`) asserting the API returns 400, not 500, would both document and lock in the fix.
2. **`MaxBodySizeMiddleware` bypass via missing/chunked `Content-Length` — zero coverage.** The existing `test_oversized_request_body_is_rejected` only exercises the declared-header path, not the omitted/understated-header bypass B2 identifies.
3. **`ctp_core/providers.py` has no dedicated test file.** `OsmArtHistoryProvider`, `OsmLodgingProvider`, and `_snap_pois_to_nodes` are only exercised incidentally through the parametrized theme/shape matrix in `test_routing.py`, which never asserts POI-scoring behavior directly, never exercises the empty-POI-result path, and never instantiates `OsmLodgingProvider` at all.
4. **`/routes/generate` while `app.state.ready is False` (the 503 branch) — untested.** Every `test_api.py` test waits for `ready: true` via the fixture's polling loop first.
5. **Elevation void edge cases**: NaN-nodata (ties to B4) and "tile present but unreadable/corrupted" are both untested — only "file missing" and "coordinate outside bounds" are covered.
6. **Export edge cases**: no test for a single-point or zero-point route in any format — this is specifically the case the `_to_fit` helper's `len(route.coords) > 1` guard exists to prevent a `ZeroDivisionError` on, and that guard is currently unverified. `export_route`'s own unknown-format fallthrough is also untested at the `ctp_core` level.
7. **No concurrency test.** Nothing verifies two concurrent `/routes/generate` calls stay correctly isolated (`app.state.graph_base.copy()` under concurrent access) or that the server stays responsive during a solve.
8. **Startup-failure path untested.** No test simulates `build_graph`/`enrich_elevation` raising during lifespan startup to verify `ready` stays permanently `False` and the exception is actually logged.
9. **`/geocode` failure path untested** — only the success case (`test_geocode_resolves_marion_nc`) exists; no test for an unresolvable query (the 404 branch), which also ties to B9's over-broad exception mapping.
10. **`scoring.py`'s traffic-class and turn-count logic** are only exercised indirectly through end-to-end routing tests — unlike elevation, which has a direct `test_flattest_and_most_climbing_diverge_on_a_hilly_edge`-style assertion. A parallel direct test would close this gap.
11. Minor: a couple of existing tests are looser than ideal for what they claim to check (`test_clear_cache_removes_on_disk_graph_cache_and_app_stays_up` accepts `cleared in (True, False)` without asserting actual disk state; the real-network geocode/tile tests use loose sanity bounds rather than fixtures) — not urgent, since tightening either trades reliability for precision against a live third-party service.

### 3.2 Client (11 tests, 7 files, all passing)

Prioritized gaps:

1. **No regression test for "destination clears when shape changes away from point-to-point."** This is a real bug that was already found and fixed once (see ROADMAP's hardening history, commit `4fe2733`). The current reset test only exercises the Reset button, not the `SegmentedButton.onSelectionChanged` side effect in `route_planner_screen.dart` that this fix lives in — nothing currently protects it from regressing.
2. **`RouteGenerationNotifier.generate()`'s validation/error paths are entirely untested**: no start point, point-to-point with no destination, and a non-2xx backend response surfacing through `AsyncValue.guard`. There is no `test/state/` directory at all.
3. **The C1 reset-during-in-flight-generate race has no test** — worth adding alongside the fix.
4. **`RoutingClient` is mostly untested beyond the one wire-boundary rule.** `checkReady`, `geocode`, `exportRoute`, `clearCache`, and the `_errorDetail` fallback for a malformed error body all have zero coverage, success or failure.
5. **`_StartupWait`/`_StartupWaitState` timer/message-escalation logic is completely untested.** No test pumps fake time to verify the message actually escalates through `_startupMessages`, or checks behavior past the last scripted entry.
6. **Export flow (success and failure) is untested** — would need a fake/mockable `getSaveLocation`/`File` seam, which doesn't currently exist.
7. **`manage_data_screen.dart` has no test file at all** — the clear-cache confirm dialog, success/failure snackbar text, and the "coming soon" region stubs are all unverified.
8. **Geocode error handling is untested** — the existing fake client's `geocode` always succeeds; nothing drives the `catch` branch or verifies `errorText` renders.
9. **Map zoom controls are untested** — `_zoomBy` and its clamping, and the zoom in/out buttons, are never exercised.
10. **`_ensurePointsVisible` (the just-added auto-pan-to-fit behavior) is untested.**
11. Minor: `RouteShape.fromApiValue`/`RouteTheme.fromApiValue`'s failure path (ties to C3) is untested.

**What's solid:** `route_planner_reset_test.dart` (full-stack through a real provider container + widget tree), `search_bar_test.dart` (three genuine interaction cases), and `domain/route_result_test.dart` (thorough JSON/enum round-trip) meaningfully exercise real behavior rather than just checking a widget exists.

---

## 4. UX Review

Judged against this project's own stated principles (`UX.md`, PRD §6), not generic best practice. Mobile-only concerns (Outdoor Contrast, glove/glare tap targets) are noted as forward-looking, not current defects, since this is a Desktop-only client today.

### 4.1 High severity

**U1 — A generated route silently goes stale when its inputs change.** `routing_providers.dart` (`RouteGenerationNotifier`), `route_map.dart`.
Nothing invalidates `routeGenerationProvider` when start/destination/shape/theme change after a route already exists — only the explicit Reset clears it. A user can generate a route, then tap the map again (which unconditionally moves the start marker in Loop mode — see U-adjacent finding C7) or pick a new theme, and the map keeps showing the *previous* route's polyline, in the previous theme's color, next to markers that no longer match it. There's no "stale, regenerate" indicator. This is the inverse of the PRD's "user's work is never silently lost" principle — here stale state is silently *kept* and presented as current, which could mislead a user into exporting a route that doesn't match what's on screen.
**Status: Fixed** together with C1. `RouteGenerationNotifier.build()` now registers `ref.listen` on all five inputs (theme, shape, start, destination, target distance) and clears the route the moment any of them changes. New tests: `'changing an input after a route is generated clears the now-stale route'` and the target-distance variant, in `routing_providers_test.dart`. (C7's map-tap asymmetry itself is unchanged — still a LOW finding, out of scope for this pass.)

### 4.2 Medium severity

**U2 — "Surface type and traffic level are always visible on a route" (PRD §6) is currently unmet, despite the data existing.** `client/lib/domain/route.dart`, `route_planner_screen.dart` (`_RouteSummary`), `backend/ctp_service/schemas.py` (`RouteResponse`).
**Verified independently:** `RouteResponse` carries only `id`, `theme`, `shape`, `coords`, `distance_m`, `elevation_gain_m` — no traffic or surface field at all. FR3 (Lowest-Traffic theme) is one of the five shipped MVP themes, meaning the routing core already reasons about traffic per edge server-side, but that signal never reaches the API response, so there's currently no data for the UI to show even if `_RouteSummary` wanted to. Distinct from the already-tracked FR8/FR43/FR44 gaps — this is a stated-as-current principle for a feature whose backend half is already built.
**Status: Fixed**, and the surface half is now also backed by real data — the Leg 3 merge (after the original review) added `_surface_class`/FR12 surface scoring to `scoring.py`, which this fix's `Route.surface_breakdown_m` reuses the same edge-tag pattern for (mirroring `trips.py`'s existing per-day `surface_breakdown_m`, now extended to single-route generation too). `Route`/`RouteResponse` gained `surface_breakdown_m`/`traffic_breakdown_m` (meters per OSM `surface`/`highway` tag); the client parses and shows both in `_RouteSummary` as a top-3-tags-by-share summary, e.g. "Surface: asphalt 82%, gravel 18%". New tests: backend `test_solve_route_populates_surface_and_traffic_breakdown` (parametrized over all three shapes, asserts the breakdown sums to the route's total distance) and the API-level assertion in `test_generate_route_then_export_every_format`; client `route_result_test.dart`'s parsing case and `route_summary_test.dart`'s display case.

**U3 — Raw/unfiltered exception text reaches the user** (see C2 above — same finding, UX-relevant framing: this directly contradicts the "never a raw error" spirit of PRD §6/FR43).
**Status: Fixed** (see C2/C6).

**U4 — Destructive-action treatment is inconsistent and inverted relative to actual risk.** `manage_data_screen.dart` (`_confirmClear`) vs. `route_planner_screen.dart` (`_resetControls`).
Clearing the downloaded-region cache — low stakes, auto-re-fetched — gets a confirmation dialog. Reset — which discards theme, shape, both points, target distance, *and* any generated route in one click with no undo — gets none.
**Status: Fixed.** Reset now shows an `AlertDialog` confirmation (same Cancel/confirm pattern as `manage_data_screen.dart`'s clear-cache dialog) before running. New tests: the existing reset test updated for the extra confirm tap, plus `'Cancelling the Reset confirmation leaves every control untouched'`.

**U5 — Stale geocode error text can survive a field being cleared.** `search_bar.dart`. The `ref.listen` callback clears the text controller when the bound point becomes `null` but never clears `_error` or calls `setState`. A previously-failed address search's red error label can persist under a now-empty field after Reset or a shape change.
**Status: Fixed.** The same listener branch that clears the controller now also clears `_error` (via `setState`). New test: `'a failed-search error clears when the bound point is reset externally'`.

**U6 — No OS light/dark adaptation.** `client/lib/main.dart:15-23`. PRD §6 states the adaptive contrast system's "Indoor Contrast" default applies to Desktop *now*, not just the Mobile-only "Outdoor Contrast" mode — but `MaterialApp` declares one fixed `ColorScheme` with no `darkTheme`/`themeMode: ThemeMode.system`, so the OS setting is ignored entirely. Distinct from the legitimately-future Outdoor Contrast mode.
**Status: Fixed** for the scoped-down piece this finding actually calls out as current: added a `darkTheme` (same Deep Slate Blue seed, `Brightness.dark`) and `themeMode: ThemeMode.system`, so Desktop now tracks the OS setting — both brightnesses are still Indoor Contrast in character. The separate Outdoor Contrast mode (Absolute Obsidian, high-contrast monochrome, Mobile-default) and the account-synced manual override remain out of scope, as the original finding itself noted. New test: `'app follows the OS light/dark setting instead of a single fixed theme'`.

**U7 — Theme picker carries no color semantics** (see C5 above — same finding; UX framing: this is a concrete, current gap against the Brand Guide's own stated color-language requirement, not a nice-to-have).
**Status: Fixed** (see C5).

### 4.3 Low severity

**U8 — Validation errors aren't attached to the field they're about.** `route_planner_screen.dart`. "Pick a start point first" / "Pick a destination..." render as detached red text below the Generate/Reset buttons rather than as the `errorText` the search fields already support and use well for failed geocodes.

**U9 — Startup wait has no distinction between "still normal" and "actually stuck"** (see C4 above — same finding; UX framing: the escalating-message design is genuinely good, but tops out and repeats indefinitely with no branch for "this is now unusual," and the README documents a real failure mode — Windows Smart App Control blocking `uv.exe` — that would leave a user stuck here forever with no signal).

**U10 — "Clear cache" tells the user to do something the app has no control for** (`manage_data_screen.dart`: "Restart the backend to re-download," with no in-app restart action). Minor and expected to resolve naturally once client-side sidecar lifecycle management lands — flagged as a rough edge to watch, not a current defect.

### 4.4 Positive observations (worth preserving)

- **FR48 startup-wait messaging** is genuinely well done: on-brand, reduces perceived-wait anxiety, escalates rather than a bare spinner or a hard timeout failure.
- **`search_bar.dart`'s three-way state reconciliation** (cleared-elsewhere vs. set-by-self vs. set-externally-by-map-tap) is a thoughtfully handled bit of state sync with comments explaining *why* each branch exists.
- **Loop pre-selected as the default shape** matches PRD §6's "loops are the path of least resistance" principle exactly.
- **Target-distance slider is hidden entirely for point-to-point**, and the rule is enforced defensively at the wire boundary too (`routing_client.dart`) — the UI honestly reflects a real backend constraint rather than showing a control that would silently do nothing.
- **Fibonacci-stepped distance slider (FR47)** is a well-matched control shape: fine-grained at short distances where small differences matter, coarse at long distances where they don't.
- **Backend-sourced errors are translated well** via `RoutingClient._errorDetail()` — the gap (C2/U3) is specifically about the paths that bypass this translation, not this mechanism itself.

---

## 5. Suggested priority order — status: all done

All seven items below (and every other HIGH/MEDIUM finding in §1/§2/§4) are fixed as of the `code-review-fixes` branch — see §0 and the **Status: Fixed** notes on each individual finding above for what actually changed and which test covers it.

1. ~~**B1** — unreachable-route 500 → 400 (one-line exception-handling fix, backend)~~ Fixed.
2. ~~**C1** — Reset/generate race condition (client state-management fix)~~ Fixed.
3. ~~**B4** — NaN nodata fallback (one-line fix, but silently poisons scoring near elevation voids)~~ Fixed.
4. ~~**U1** — stale route not invalidated on input change (ties directly to C1; likely worth fixing together)~~ Fixed, together with C1 as anticipated.
5. ~~**B2** — body-size cap bypass (security-adjacent, backend)~~ Fixed.
6. ~~**C2/U3** — catch connection-level failures in `RoutingClient` and give them the same friendly treatment backend errors already get~~ Fixed, together with C6 (timeouts).
7. ~~**U2** — surface traffic/surface data that FR3 already computes but the API never returns~~ Fixed — surface data too, once Leg 3 added FR12 scoring.

Everything else (LOW-severity findings B7–B10, C7–C11, U8–U10, and the full test-coverage-gap lists in §3) is unchanged from the original review — genuinely out of scope for this pass, not silently dropped.
