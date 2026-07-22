"""PyInstaller entrypoint for the frozen ctp-service sidecar binary.

Minimal on purpose: enough for the build pipeline to freeze a runnable
server and prove it serves /health. The full sidecar lifecycle protocol
(PID file, orphan sweep, readiness-vs-liveness handling, --mode/--cache-dir
wiring — Architecture §6.3) is separate, not-yet-built client-integration
work.
"""

from __future__ import annotations

import argparse

import uvicorn

from ctp_service.app import create_app


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the ctp-service sidecar")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    uvicorn.run(create_app(), host=args.host, port=args.port)


if __name__ == "__main__":
    main()
