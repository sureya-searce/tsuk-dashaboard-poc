"""Warm service. Primes Looker dashboard caches so the first user load is
instant after a pipeline run.

POST /warm
    body: {"dashboards": ["finance", "logistics", "anomaly"]}

For each dashboard name, the service:
  1. Logs in to Looker with API3 credentials.
  2. Looks up the dashboard ID by slug (configured in DASHBOARD_SLUGS).
  3. Calls `run_dashboard` which forces Looker to execute and cache each tile.

The dashboard slugs are placeholders until the LookML dashboards exist in
Looker. Until then the service no-ops gracefully (returns SKIPPED) so the
Workflow doesn't fail end-to-end.
"""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx
from fastapi import FastAPI
from pydantic import BaseModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("warm")

app = FastAPI(title="Searce TSUK PoC — warm")

LOOKER_INSTANCE_URL = os.environ.get("LOOKER_INSTANCE_URL", "").rstrip("/")
LOOKER_CLIENT_ID = os.environ.get("LOOKER_CLIENT_ID", "")
LOOKER_CLIENT_SECRET = os.environ.get("LOOKER_CLIENT_SECRET", "")

# Looker dashboard slugs. Populated post-LookML build.
DASHBOARD_SLUGS: dict[str, str] = {
    "finance":   "tsuk_finance",
    "logistics": "tsuk_logistics",
    "anomaly":   "tsuk_anomaly_digest",
}


class WarmRequest(BaseModel):
    dashboards: list[str]


class WarmResponse(BaseModel):
    status: str
    results: list[dict[str, Any]]


@app.get("/healthz")
def health() -> dict:
    return {"status": "ok"}


@app.post("/warm", response_model=WarmResponse)
def warm(req: WarmRequest) -> WarmResponse:
    if not (LOOKER_CLIENT_ID and LOOKER_CLIENT_SECRET and LOOKER_INSTANCE_URL):
        log.warning("Looker credentials not configured — skipping cache warm.")
        return WarmResponse(status="SKIPPED", results=[
            {"dashboard": d, "status": "SKIPPED", "reason": "Looker credentials not configured"}
            for d in req.dashboards
        ])

    with httpx.Client(base_url=f"{LOOKER_INSTANCE_URL}/api/4.0", timeout=60.0) as client:
        token = _login(client)
        client.headers["Authorization"] = f"token {token}"

        results: list[dict[str, Any]] = []
        for name in req.dashboards:
            slug = DASHBOARD_SLUGS.get(name)
            if not slug:
                results.append({"dashboard": name, "status": "UNKNOWN_DASHBOARD"})
                continue
            try:
                _run_dashboard(client, slug)
                results.append({"dashboard": name, "slug": slug, "status": "OK"})
            except Exception as e:
                log.exception("warm failed for %s", name)
                results.append({"dashboard": name, "slug": slug, "status": "FAILED", "error": str(e)})

    overall = "OK" if all(r["status"] == "OK" for r in results) else "PARTIAL"
    return WarmResponse(status=overall, results=results)


def _login(client: httpx.Client) -> str:
    r = client.post(
        "/login",
        data={"client_id": LOOKER_CLIENT_ID, "client_secret": LOOKER_CLIENT_SECRET},
    )
    r.raise_for_status()
    return r.json()["access_token"]


def _run_dashboard(client: httpx.Client, slug: str) -> None:
    # Look up dashboard by slug
    r = client.get(f"/dashboards/{slug}")
    r.raise_for_status()
    dashboard_id = r.json()["id"]

    # Trigger a render to force tile caches to populate. PDF render is the
    # cheapest "execute everything" call that exists.
    r = client.post(
        f"/render_tasks/dashboards/{dashboard_id}/pdf",
        params={"width": 1280, "height": 800},
    )
    r.raise_for_status()
