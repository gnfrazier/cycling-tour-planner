# Android sidecar feasibility spike

**Scope:** Roadmap Leg 2, "Prototype the local sidecar on Android" (Architecture
§4.1, risk A1). Answers whether Option C — freeze `ctp-service` with
PyInstaller, spawn it as a child process, talk to it over
`http://127.0.0.1:{port}` — works on Android the same way it already works on
Desktop (`.github/workflows/desktop-build.yml`).

**Verdict: no. Option C as specified does not run on Android, for two
independent, non-negotiable reasons — not a tuning problem, a packaging
problem.** No proof-of-concept is included because the direct approach has no
working form to demonstrate; per the spike's own brief, this report and a
recommended alternative are the deliverable.

This also means a load-bearing assumption in `ARCHITECTURE.md` §4.1 is wrong:
*"iOS is the open risk … Android permits child processes and will validate
the model."* Android permits child processes in general, but not of a binary
matching what PyInstaller produces. See "Impact on the architecture" below.

---

## 1. Why the frozen binary can't be spawned

Two separate blockers, either one of which is fatal on its own.

### 1.1 Android 10+ W^X policy blocks "write then exec" outright

Since Android 10 (API 29), apps targeting API 29+ are subject to a strict
W^X (write XOR execute) policy: a file cannot be both writable by the app and
executable. Concretely, `execve()` (and anything that resolves to it, which
is what every subprocess-spawn API in Dart/Flutter and Python eventually
calls) is blocked against files living in the app's own writable storage —
`getFilesDir()`, `getCacheDir()`, external app-specific storage, anywhere a
downloaded-or-unpacked binary would land at runtime.

The only executable code Android will run is native code shipped **inside
the APK** as `lib/<abi>/lib*.so`, extracted (or `mmap`-executed directly from
the APK's zip, on newer Play Store deliveries) by the OS at install time and
loaded via `dlopen()`/`System.loadLibrary()` — not `subprocess.spawn()`.

This kills the current Desktop model at the root: `ctp-service` is shipped
as a `--onedir` PyInstaller build (a directory of files: the main
executable, bundled `.so`s, a Python zip, data files) that gets unpacked
somewhere writable and exec'd as a child process with `--port=N`. There is
no writable-and-executable place on Android 10+ to put it, and no supported
API to exec it if there were. Renaming it to `lib*.so` and dropping it in
`lib/<abi>/` doesn't help either — Android's loader expects an actual shared
object it can `dlopen`, not an ELF *executable* with its own `main()`,
argv-based CLI, and a dynamic linker interpreter (`PT_INTERP`) baked in.

Sources: [Android 10 behavior changes for apps targeting API 29+](https://developer.android.com/about/versions/10/behavior-changes-10), [Termux and Android 10 (termux-packages wiki)](https://github.com/termux/termux-packages/wiki/Termux-and-Android-10/5d899145ab70caa6e484609baf6c354651150230), [W^X (Wikipedia)](https://en.wikipedia.org/wiki/W%5EX)

### 1.2 Even without W^X, the binary is linked against the wrong libc

PyInstaller's Linux output does not bundle libc — it dynamically links
against whatever glibc is on the build host (CI runs on `ubuntu-latest`,
so `libc.so.6`, `ld-linux-x86-64.so.2`, etc.), and expects to find a
compatible one at run time. Android does not ship glibc. It ships
**Bionic**, a from-scratch libc with a different ABI, a different (and much
smaller) syscall/NSS surface, and no `ld-linux.so` — Bionic's own dynamic
linker (`linker64`/`linker`) does not understand glibc's loader conventions.

This is a second, independent failure mode from §1.1: even in a
hypothetical world where W^X didn't exist and the binary could be exec'd
from a writable directory, it would fail to load — the dynamic linker
would be unable to resolve glibc symbols Bionic doesn't provide. Fixing
this requires rebuilding the entire frozen artifact from source against
Android's NDK toolchain (Bionic + the Android-flavored Clang cross
compiler), not repackaging the existing Linux build. This is effectively a
from-scratch Android-targeted freeze, and is exactly the kind of project
the alternatives in §3 exist to manage.

Sources: [Bionic (software) — Wikipedia](https://en.wikipedia.org/wiki/Bionic_(software)), [PyInstaller: "Linux bundle not portable: numpy → glibc" discussion](https://github.com/orgs/pyinstaller/discussions/7148), [PyInstaller usage docs — dynamic linking on GNU/Linux](https://pyinstaller.org/en/stable/usage.html)

### 1.3 ABI/arch matching (secondary, but worth naming)

Even if §1.1 and §1.2 didn't exist, CI freezes `ctp-service` on
`ubuntu-latest`, producing an `x86_64` ELF built against glibc's `x86_64`
ABI. A real Android device is overwhelmingly `arm64-v8a` (the Play Store
default target today); the standard emulator image is also usually
`arm64-v8a` on Apple Silicon hosts or `x86_64` on Intel hosts. A single
frozen artifact from a single CI runner would need to become at least two
(`arm64-v8a` + `x86_64`) even in the best case, on top of the Bionic rebuild
in §1.2 — this is a multiplier on the work, not a blocker by itself.

### On Termux/proot-style shims specifically

The spike brief asked whether a Termux-style compatibility shim rescues the
direct-exec model. It does not, for a scope reason as much as a technical
one: Termux works by shipping its **own** complete Bionic-linked userland
(its own Python, its own glibc-free rebuilds of every native dependency) as
a *separate, standalone app* with its own storage/exec permissions and its
own package repository (`termux-packages`) — it is not a library another
app can embed, and it is subject to the exact same §1.1 W^X restriction
itself on modern Android (see the linked Termux/Android-10 wiki page above —
Termux had to substantially redesign its own package execution model for
this reason). Adopting it would mean depending on a second, independently
sandboxed application rather than solving the packaging problem — out of
scope for what "spawn a child process from our own APK" means.

---

## 2. Conclusion on Option C as specified

**The current Option C model — freeze with PyInstaller, ship the frozen
directory, spawn it as a subprocess, talk HTTP to `127.0.0.1` — does not
work on Android, full stop, independent of effort spent tuning it.** Both
blockers (§1.1, §1.2) are platform policy and ABI facts, not bugs in how
`ctp-service` is currently frozen.

This is a materially different situation from what `ARCHITECTURE.md` §4.1
currently assumes. The document treats iOS as the one open platform risk
and Android as the platform that "permits child processes and will validate
the model." Android does permit child processes *of code shipped in the
APK* — it does not permit executing an unpacked-at-runtime, glibc-linked
binary, which is the specific shape "the model" takes today. **Android and
iOS turn out to need the same category of decision, at the same §4.1
options table, not a validated-vs-unvalidated split.** See "Impact on the
architecture" below.

---

## 3. Alternatives — and the actual hard part

The three alternatives named in the spike brief are all *Python-embedding*
strategies (an interpreter linked into the app process, not a spawned
sidecar), so they sidestep §1.1 and §1.2 entirely — no exec, no subprocess,
no PT_INTERP mismatch, because there is no second process. That part of the
problem is well-trodden. The real question, as the brief anticipated, is
whether any of them carries OSMnx's actual dependency weight: **GDAL, GEOS,
PROJ, and everything layered on top of that (`rasterio`, `shapely`,
`geopandas`, `fiona`, transitively pulled in by `osmnx`)** — plus
`scikit-learn`/`scipy`/`numpy` for the routing/weighting math, and pure-Python
`gpxpy`/`fit-tool` for export.

| Framework | Embeds CPython on Android? | Prebuilt `numpy`/`scipy`/`scikit-learn`? | Prebuilt GDAL/GEOS/PROJ/rasterio/shapely/geopandas/fiona? |
|---|---|---|---|
| **Chaquopy** | Yes — mature, actively maintained, this is its whole purpose | Yes — confirmed in [Chaquopy's native package repo](https://chaquo.com/pypi-13.1/): `numpy`, `scipy`, `scikit-learn`, `pyproj` all present | **No.** `gdal`, `rasterio`, `shapely`, `geopandas`, `fiona` are absent from the repo |
| **python-for-android** (Kivy) | Yes — this is p4a's purpose | Partial — `numpy` has a recipe; broader scientific stack is thinner | **Mostly no.** Only a `libgeos` recipe exists in [the current recipes tree](https://github.com/kivy/python-for-android/tree/master/pythonforandroid/recipes) — no `gdal`, `shapely`, `rasterio`, `geopandas`, `fiona`, or `osmnx` recipe |
| **BeeWare/Briefcase** | Yes, but its Android backend itself now builds on Chaquopy under the hood | Inherits Chaquopy's repo — same as above | Inherits Chaquopy's repo — same gap |

`osmnx`, `networkx`, `gpxpy`, and `fit-tool` are pure Python and would
install without incident under any of the three (all support installing
plain PyPI packages, not just their curated native-package repos) — that
part is genuinely not the hard part, matching the brief's framing.

**The gap is identical across all three frameworks**: none of them ships a
working Android cross-compile of the GDAL/GEOS/PROJ C/C++ stack today.
Closing it means writing and maintaining Android NDK cross-compile recipes
for that native chain — the same category of work as §1.2's "from-scratch
Android-targeted freeze," just relocated into whichever framework's recipe
system is chosen (Chaquopy's build-recipe mechanism or p4a's `recipes/`
directory) instead of PyInstaller's spec file. This is a genuine,
multi-week-plus build-engineering project on its own, largely independent
of which of the three frameworks wins — choosing a framework does not avoid
this cost, it only decides which toolchain absorbs it.

Given that, **Chaquopy is the better starting point of the three** if this
path is pursued: it already has the numeric half of the stack
(`numpy`/`scipy`/`scikit-learn`/`pyproj`) prebuilt and is the most actively
maintained of the three today, which narrows the remaining gap to
GDAL/GEOS/rasterio/shapely/geopandas/fiona specifically rather than the
whole scientific-Python stack. It is a narrower gap, not a closed one.

---

## 4. Impact on the architecture (flagging, not resolving)

This spike changes a premise `ARCHITECTURE.md` §4.1 and `ROADMAP.md`'s Leg 5
section currently rely on — surfacing it here rather than editing either
file, since that's a product/architecture call, not something a feasibility
spike should quietly decide:

- §4.1's framing — "prototype the frozen-binary sidecar on Android … Android
  permits child processes and will validate the model" — assumed Android
  would either work as-is or need minor packaging tweaks, leaving iOS as
  *the* open decision. That assumption doesn't hold: **Android needs the
  same three-way decision iOS does** (embedded interpreter / online-only /
  precompute-and-download), for essentially the same underlying reason
  (no arbitrary child-process exec of unsigned, unpacked-at-runtime code).
- ROADMAP.md's Leg 5 (M7) section currently frames Android as "already
  validated" going into that leg, with iOS as "the one deliberately
  deferred decision." That framing needs revisiting — Android's own sidecar
  strategy is now an open decision too, and per this spike's findings, it's
  gated on the same GDAL/GEOS native-recipe work regardless of which
  embedding framework is chosen.
- None of the three named alternatives is a drop-in replacement for Option
  C; each requires committing to an upfront native-cross-compile effort
  before Android can run OSMnx on-device at all. That's a scope and
  timeline input worth having explicitly, not a decision this spike is
  making on the project's behalf.

No PRD or roadmap edits are made here, per the isolation instructions for
this spike (`ROADMAP.md` and `review-findings.md` are out of scope for this
branch) — this section exists so the finding isn't lost, and the actual
decision can be made deliberately with this evidence in hand.
