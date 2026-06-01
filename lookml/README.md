# LookML — TSUK Logistics PoC

Placeholder. Real LookML will be authored inside the Looker UI (`Develop → LookML Projects → New LookML Project`) and pushed to a Git remote from there, then mirrored here for review/handover.

Planned structure:

```
lookml/
├── tsuk_logistics_poc.model.lkml
├── models/
├── views/
│   ├── mart_shipments.view.lkml
│   ├── mart_lane_monthly.view.lkml
│   ├── mart_supplier_monthly.view.lkml
│   └── mart_anomalies.view.lkml
├── explores/
│   ├── shipments.explore.lkml
│   └── anomalies.explore.lkml
└── dashboards/
    ├── tsuk_finance.dashboard.lookml
    ├── tsuk_logistics.dashboard.lookml
    └── tsuk_anomaly_digest.dashboard.lookml
```

Blocked on:
- Looker user provisioning for `sureya.sathiamoorthi@tatasteel.co.uk` on `looker-instance-p-01`.
- BigQuery connection in Looker pointing at `searce_poc_mart`.
