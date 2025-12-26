# Adding Alerts to Applications

This guide explains how to add Prometheus alerting rules for your applications in this cluster.

## Overview

The monitoring stack uses:

- **Prometheus** - Metrics collection and alerting evaluation
- **AlertManager** - Alert routing and notifications (Pushover)
- **PrometheusRule CRD** - Kubernetes-native alert definitions

## Quick Start: Adding an Alert

### Option 1: Add to Existing Rules File

Edit `apps/production/monitoring/prometheus/alerting-rules.yaml` and add your alert to an existing group or create a new group:

```yaml
spec:
  groups:
    - name: my-app-alerts
      rules:
        - alert: MyAppDown
          expr: up{job="my-app"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "MyApp is down"
            description: "MyApp has been unreachable for 5 minutes."
```

### Option 2: Create App-Specific Alert File

For application-specific alerts, create a PrometheusRule in the application's directory:

```yaml
# apps/production/apps/my-app/alerting-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-app-alerts
  namespace: my-app
  labels:
    prometheus: kube-prometheus
    release: kube-prometheus-stack
spec:
  groups:
    - name: my-app
      rules:
        - alert: MyAppHighLatency
          expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job="my-app"}[5m])) > 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High latency in {{ $labels.job }}"
            description: "P99 latency is above 1 second."
```

Then add it to your app's kustomization.yaml:

```yaml
resources:
  - alerting-rules.yaml
  - deployment.yaml
  # ... other resources
```

## Alert Structure

```yaml
- alert: AlertName # Unique name for the alert
  expr: <promql_expression> # PromQL query that triggers alert when true
  for: 5m # How long condition must be true before firing
  labels:
    severity: critical|warning # Routes to different Pushover priorities
    team: platform # Optional: for routing to specific teams
  annotations:
    summary: "Short description"
    description: "Detailed description with {{ $labels.instance }}"
    runbook_url: "https://..." # Optional: link to runbook
```

## Severity Levels

| Severity   | Pushover Priority | Use Case                                                   |
| ---------- | ----------------- | ---------------------------------------------------------- |
| `critical` | High (1)          | Service down, data loss risk, immediate action needed      |
| `warning`  | Normal (0)        | Degraded performance, approaching limits, investigate soon |

## Common Alert Patterns

### Service Availability

```yaml
# Service is down
- alert: ServiceDown
  expr: up{job="my-service"} == 0
  for: 5m
  labels:
    severity: critical

# Too few replicas
- alert: InsufficientReplicas
  expr: kube_deployment_status_replicas_available{deployment="my-app"} < 2
  for: 5m
  labels:
    severity: warning
```

### Error Rates

```yaml
# High error rate (> 5%)
- alert: HighErrorRate
  expr: |
    sum(rate(http_requests_total{job="my-app",status=~"5.."}[5m]))
    /
    sum(rate(http_requests_total{job="my-app"}[5m])) > 0.05
  for: 5m
  labels:
    severity: warning

# Any 5xx errors
- alert: ServerErrors
  expr: increase(http_requests_total{job="my-app",status=~"5.."}[5m]) > 0
  for: 1m
  labels:
    severity: warning
```

### Latency

```yaml
# P99 latency > 1s
- alert: HighLatency
  expr: |
    histogram_quantile(0.99,
      rate(http_request_duration_seconds_bucket{job="my-app"}[5m])
    ) > 1
  for: 5m
  labels:
    severity: warning

# P50 latency > 500ms
- alert: ElevatedLatency
  expr: |
    histogram_quantile(0.50,
      rate(http_request_duration_seconds_bucket{job="my-app"}[5m])
    ) > 0.5
  for: 10m
  labels:
    severity: warning
```

### Resource Usage

```yaml
# Container memory > 80%
- alert: ContainerHighMemory
  expr: |
    container_memory_usage_bytes{container="my-app"}
    /
    container_spec_memory_limit_bytes{container="my-app"} > 0.8
  for: 5m
  labels:
    severity: warning

# Container CPU throttling
- alert: ContainerCPUThrottling
  expr: |
    rate(container_cpu_cfs_throttled_periods_total{container="my-app"}[5m])
    /
    rate(container_cpu_cfs_periods_total{container="my-app"}[5m]) > 0.5
  for: 5m
  labels:
    severity: warning
```

### Queue/Job Processing

```yaml
# Queue depth growing
- alert: QueueBacklog
  expr: my_app_queue_depth > 1000
  for: 10m
  labels:
    severity: warning

# Job failure rate
- alert: JobFailures
  expr: |
    increase(my_app_job_failures_total[1h])
    /
    increase(my_app_job_total[1h]) > 0.1
  for: 5m
  labels:
    severity: warning
```

## Exposing Metrics from Your Application

For Prometheus to scrape your app, either:

### Option A: ServiceMonitor (Recommended)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-app
  labels:
    prometheus: kube-prometheus
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### Option B: Pod Annotations

Add annotations to your deployment:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

## Testing Alerts

### 1. Check if Prometheus Sees Your Rules

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090

# Visit http://localhost:9090/alerts
```

### 2. Check Alert Status in AlertManager

```bash
# Port-forward to AlertManager
kubectl port-forward -n monitoring svc/prometheus-alertmanager 9093:9093

# Visit http://localhost:9093
```

### 3. Test Fire an Alert

```bash
# Manually create a test alert
kubectl exec -n monitoring deploy/alertmanager-prometheus-alertmanager -- \
  amtool alert add test severity=warning alertname=TestAlert

# Check it appears in AlertManager UI and Pushover
```

### 4. Validate PromQL Expression

In Prometheus UI (<http://localhost:9090/graph>), test your expression:

- Enter your `expr` value
- Click "Execute"
- If it returns data, condition is true (alert would fire)

## Label Requirements

**Required labels:**

- `prometheus: kube-prometheus` - Ensures Prometheus discovers the rule
- `release: kube-prometheus-stack` - Alternative label for discovery

**Required in alert:**

- `severity: critical|warning` - Routes to appropriate Pushover channel

## Useful Resources

- [Awesome Prometheus Alerts](https://samber.github.io/awesome-prometheus-alerts/rules.html) - Pre-built alert rules
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Prometheus Alerting Best Practices](https://prometheus.io/docs/practices/alerting/)

## Cluster Alert Rules Reference

Current alerts defined in `alerting-rules.yaml`:

| Alert                      | Severity | Condition                        |
| -------------------------- | -------- | -------------------------------- |
| NodeDown                   | critical | Node exporter unreachable for 5m |
| NodeHighCPU                | warning  | CPU > 80% for 10m                |
| NodeHighMemory             | warning  | Memory > 85% for 10m             |
| NodeDiskAlmostFull         | warning  | Disk > 85% for 10m               |
| PodCrashLooping            | warning  | > 3 restarts in 1h               |
| PodNotReady                | warning  | Not ready for 15m                |
| DeploymentReplicasMismatch | warning  | Replicas mismatch for 15m        |
| PVCAlmostFull              | warning  | PVC < 15% free for 5m            |
| PVCCriticallyFull          | critical | PVC < 5% free for 2m             |
| CertificateExpiringSoon    | warning  | Cert expires in < 7 days         |
| CertificateExpiryCritical  | critical | Cert expires in < 24 hours       |
| FluxReconciliationFailure  | warning  | Flux resource failing for 15m    |
| CephHealthWarning          | warning  | Ceph HEALTH_WARN for 5m          |
| CephHealthCritical         | critical | Ceph HEALTH_ERR for 2m           |
