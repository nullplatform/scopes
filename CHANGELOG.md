# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
- Remove unused cloudwatch annotations from deployment objects
- Fix: log queries on k8s scopes now answer the time range that was selected. Asking for a past window came back with the most recent lines whatever range was chosen, paging through the results could repeat lines already shown without ever reaching the end of the range, and an unusable bound was ignored or replaced with the current time rather than reported. The upper bound is now passed through to the log reader and reading stops at the end of the window, paging keeps each instance's position so every line is returned once, and a bound that cannot be used fails with a message naming it

## [1.15.1] - 2026-08-12
- Fix: gRPC additional ports on k8s scopes now leave the declared port free for the application, so a gRPC server can bind the port configured in the scope instead of failing to start with "address already in use". gRPC ports now work the same way HTTP ones already did
- k8s scopes now reject an additional port above 55535 at deploy time, with a message explaining the limit, instead of starting a deployment whose traffic sidecar could never come up
- k8s scopes with gRPC additional ports now require traffic-manager image `1.7.0` or newer; on older images the gRPC sidecar never starts and the deployment stays unhealthy

## [1.15.0] - 2026-08-10
- Fix: **finalize** and **rollback** on blue/green k8s scopes now wait until the load balancer sends all traffic to the surviving deployment before deleting the other one, preventing the 5xx window that happened when it was deleted mid-switch (these actions may take slightly longer as a result)
- k8s scope: the main traffic-manager sidecar's listener port is now configurable via `main_traffic_manager_port` (default `80`), for clusters that do not allow pod-to-pod traffic on port 80

## [1.14.0] - 2026-08-03
- k8s scope deployments now report launched and healthy instance counts, so the deployment page shows live "X/Y launched" and "X/Y healthy" progress
- Fix: triggering a scheduled task job on a scope that is not deployed now fails with a clear "deploy the scope first" message instead of an opaque error
- Add "Kill instance" action to scheduled task scopes to terminate an individual running job instance

## [1.13.0] - 2026-07-10
- Add support to get AWS credentials via assume role
- Add support to auto-create ALBs on scope create
- Fix race condition on IAM role creation when multiple scopes are created concurrently
- Add nodeSelector support for scheduled task scopes

## [1.12.0] - 2026-06-08
- Fix: do not inject file parameter as env vars
- Public and private scopes now register DNS records in their correct Route53 hosted zone when using `DNS_TYPE=external_dns`, preventing cross-zone record leakage
- Add configurable main HTTP port for k8s scopes (default 8080) and HTTP support for additional ports
- Improve **wait deployment active** failure logging: consolidate repeated `Unhealthy` probe events per pod into a single human-readable line, emit a progress heartbeat every 10% of timeout, and surface a targeted suggested fix based on the probe failure mode (port not open / HTTP non-2xx / probe timeout)
- Add configurable memory and CPU limits, independent from requests, for k8s scope containers
- Improve **k8s/diagnose** evidence: every check now emits structured evidence following a documented schema (`summary`, `severity`, `affected`, `details`, `suggested_actions`), failure findings embed the relevant pod log slice (current or previous depending on the failure mode), and a new **Application Logs** category surfaces the user-owned `application` container's log tail directly in the UI

## [1.11.0] - 2026-04-16
- Add unit testing support
- Add scope configuration
- Improve **k8s/backup** logging format with detailed error messages and fix suggestions
- Add unit tests for **k8s/backup** module (backup_templates and s3 operations)
- Add ALB capacity validation on scope creation. Requires additional AWS permissions: `elasticloadbalancing:DescribeLoadBalancers`, `elasticloadbalancing:DescribeListeners`, `elasticloadbalancing:DescribeRules`
- Add ALB target group capacity validation on deployment. Requires additional AWS permission: `elasticloadbalancing:DescribeTargetGroups`
- Add support for multiple ALBs
- Add configurable memory and cpu limit for traffic manager
- Add ALB metrics publishing to CloudWatch or Datadog (rule count and target group count per ALB)
- Fix blue-green switch-traffic failure when `additional_ports` (e.g., gRPC) are added to a scope after the initial deployment

## [1.10.1] - 2026-02-13
- Hotfix on wait_deployment_iteration

## [1.10.0] - 2026-01-14
- Add support to configure the traffic manager nginx through a configmap.
- Add **k8s/diagnose** documentation && new checks
- Fix **k8s/diagnose** checks, adding logs && improvements
- Add support for `NAMESPACE_OVERRIDE` configuration in k8s scope and deployment actions.
- Change delete cluster objects to maintain only one deployment_id per scope
- Do not execute actions that are not valid for current deployment status
- Upgrade libs versions in k8s/log/kube-logger-go

## [1.9.0] - 2025-12-17
- Add namespace validation and auto-creation
- Add deployment hints for failed deployments
- Add wait for ingress reconciliation
- Only wait for blue deployment when using rolling deployment strategy
- Add **k8s/diagnose**: New diagnostic workflows and checks for troubleshooting Kubernetes scopes (scope, service, and networking diagnostics)

## [1.8.0] - 2025-11-28
- Add support for multiple override layers
- Add support for IAM / IRSA on Scheduled task

## [1.7.0] - 2025-11-11
- Add support for image pull secret on scheduled task
- Add support for Azure Aro Scopes
- Allow to read custom percentile metrics
- Sanitize volume name patterns (replace _ with -)

## [1.6.0] - 2025-10-22
- Add deployment improvements to scheduled task
- Add support for file parameters

## [1.5.1] - 2025-10-10
- Fix support for public and private domains

## [1.5.0] - 2025-10-09
- Scope deletion process is idempontent (ignore not found errors when deleting resources)
- Add support to configure a Pod Disruption Budget
- Add websocket support
- Add support for public and private domains

## [1.4.0] - 2025-09-26
- Add support for external DNS in networking configuration
- Trim service names to 63 characters at most

## [1.3.0] - 2025-09-19
- Add support to expose additional gRPC ports
- Add support for custom domains

## [1.2.0] - 2025-09-15
- Add support for reading logs from Datadog

## [1.1.0] - 2025-09-04
- Improve logging pagination logic
- Increase logging paging to 20 logs per page
- Fixes on Azure Routes creatoin

## [1.0.0] - 2025-09-04
- Add base implementation for Kubernetes scopes
- Add base implementation for Scheduled Task scopes
- Created base repo structure
