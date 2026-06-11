# LookML — TSUK domain-owned semantic layer

This folder **mirrors the live Looker project (`searce-tsuk-poc`) one-to-one** — copy any
file straight into the Looker IDE. One model, explores grouped by owner, views organised
into per-dataset folders matching the BigQuery ownership split.

```
lookml/
├── manifest.lkml                          # constants — retarget in ONE place
│                                          #   @{gcp_project} @{ds_core} @{ds_finance} @{ds_supplychain}
├── models/
│   └── searce-tsuk-poc.model.lkml         # the single model: connection + all explores
│                                          #   (grouped: Governed Core · Finance · Supply Chain)
└── views/
    ├── searce_poc_core/                   # shared, governed
    │   ├── cost_per_tonne.view.lkml       #   THE governed cross-team KPI (finance|transport|landed)
    │   ├── movements.view.lkml            #   conformed logistics fact
    │   ├── production_cost.view.lkml      #   conformed finance fact
    │   ├── reconciliation.view.lkml       #   the £0 receipts
    │   └── data_catalog.view.lkml         #   ownership registry
    ├── searce_poc_finance/                # Finance-owned
    │   ├── cost_analysis.view.lkml
    │   └── management_report.view.lkml    #   working capital + P&L vs plan
    └── searce_poc_supplychain/            # Supply-Chain-owned
        ├── utilisation.view.lkml
        ├── lane_performance.view.lkml
        ├── carrier_spend.view.lkml
        └── anomalies.view.lkml            #   cost leakage Top-N
```

## Setup
1. In the Looker project, create the same folders and paste each file in
   (`manifest.lkml` at project root — it must exist before the views validate).
2. The model's `connection:` is `sureya-tsuk-logistics` (the Searce-Looker →
   infraappsandbox BigQuery connection). One connection serves all datasets — views
   use fully-qualified table names, so the connection's "Primary Dataset" is irrelevant.
3. If the GCP project or dataset names ever change, edit only `manifest.lkml`.
4. Validate LookML → explores come up against the live `searce_poc_*` data.

## Why measures live here
The governed cost-per-tonne **definitions live in the semantic layer** (rich
`description:` on each measure), so Conversational Analytics answers the ambiguous
"cost per tonne" with the governed **landed** measure and can show the Finance vs
Logistics bases side by side — all from `core.cost_per_tonne`.

Dashboards (Finance / Supply Chain personas + the governance tile) are authored in
the Looker UI on these explores — tile specs in `docs/workshop-runbook.md` §6.

**Production posture (say it, don't build it):** split into per-team models — each
team's model includes the core views + its own, with model-level access grants (and
optionally per-team connections running as team-scoped service accounts, enforced by
the `finance_members` / `supplychain_members` Terraform vars).
