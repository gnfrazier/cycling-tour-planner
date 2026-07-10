import osmnx
import rasterio
from fastapi import FastAPI

app = FastAPI(title="Cycle Tour Planner API")


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "osmnx_version": osmnx.__version__,
        "rasterio_version": rasterio.__version__,
    }
