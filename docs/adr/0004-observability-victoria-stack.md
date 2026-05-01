# 4. Observability stack: VictoriaMetrics + VictoriaLogs + Grafana

Date: 2026-05-02

## Status

Accepted

## Context

Observability is a core platform component — we need metrics, logs, and dashboards before we trust any application running in this cluster. The two reasonable stacks for a kubernetes lab are:

1. **Prometheus + Loki + Grafana** (the kube-prometheus-stack default).
   - Pros: industry standard, vast ecosystem of alert rules and dashboards, what most jobs expect.
   - Cons: Prometheus's TSDB is RAM-hungry; on a small cluster a default `kube-prometheus-stack` install routinely sits at 1.5–2.5 GiB RSS for the Prometheus pod alone before Loki is even installed. Loki adds another 500–800 MiB across its components.
2. **VictoriaMetrics + VictoriaLogs + Grafana**.
   - Pros: VM single-node mode runs comfortably in 200–400 MiB for a small cluster. VictoriaLogs is a similar story vs. Loki. Both are Prometheus and Loki API-compatible — Grafana dashboards built for Prom/Loki work as-is. Operator (`victoria-metrics-operator`) handles the CRDs cleanly.
   - Cons: smaller ecosystem of out-of-the-box recording rules; some Prom-specific operator features (e.g., agent topology) need translation; less mainstream — not what a typical job interview will ask about.

On a 16 GB Mac mini hosting cluster + Ollama + Docker Desktop + IDE, the ~1–2 GiB difference between these stacks is the difference between "I can run my AI stack alongside observability" and "I can't."

## Decision

Use the **Victoria stack** as the default observability platform:

- **VictoriaMetrics** (single-node mode, `vmsingle`) for metrics. Scraping configured via `VMServiceScrape` / `VMPodScrape` CRDs from the operator.
- **VictoriaLogs** for logs. `vlogs-single` for storage; either Vector or VictoriaLogs' own collector for ingestion.
- **Grafana** for dashboards and ad-hoc query, configured with both VM and VL as data sources.
- Installed via the `victoria-metrics-operator` chart and `victoria-logs-single` chart through ArgoCD Applications under `platform/observability/`.
- Default retention: 7 days metrics, 14 days logs. Ample for a lab; tunable per learning need.

Prometheus exposition format and Loki query language compatibility means dashboards from the Grafana marketplace built against Prom/Loki work without porting.

## Consequences

- Observability stack baseline RSS target: <800 MiB total. Validated after install in `docs/learning-notes/`.
- We give up some Prometheus ecosystem familiarity (alert rule packs, exact behavior of certain operator features). When a public dashboard or rule set assumes a specific Prom feature, we either translate or accept the lesser feature.
- If a future learning goal is specifically "operate Prometheus at scale," we add Prometheus as a separate `sandbox/` exercise rather than swap the platform stack. The platform stack remains Victoria.
- Grafana provisioning (data sources, dashboards) is committed to the repo as ConfigMaps so the stack is reproducible end-to-end via ArgoCD.
- VictoriaMetrics' query language (MetricsQL) is a superset of PromQL — minor variations exist. Documented as a footnote when relevant.
