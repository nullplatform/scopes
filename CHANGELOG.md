# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
- Add **k8s/diagnose** documentation && new checks
- Fix **k8s/diagnose** checks, adding logs && improvements
- Add support for `NAMESPACE_OVERRIDE` configuration in k8s scope and deployment actions.
- Change delete cluster objects to maintain only one deployment_id per scope
- Do not execute actions that are not valid for current deployment status

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
