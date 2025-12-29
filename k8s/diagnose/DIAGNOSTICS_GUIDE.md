# Kubernetes diagnostics guide

This guide documents all diagnostic checks available in the `k8s/diagnose` workflow, including what errors they detect,
possible solutions, and example outputs.

## How diagnostics work

The diagnostic workflow follows a two-phase approach:

### Phase 1: build context (`build_context`)

Before running any checks, the `build_context` script collects a **snapshot of the Kubernetes cluster state**. This
snapshot includes:

- **Pods**: All pods matching the scope labels
- **Services**: Services associated with the deployment
- **Endpoints**: Service endpoint information
- **Ingresses**: Ingress resources for the scope
- **Secrets**: Secret metadata (no actual secret data)
- **IngressClasses**: Available ingress classes in the cluster
- **Events**: Recent Kubernetes events for troubleshooting
- **ALB Controller Data**: AWS Load Balancer controller pods and logs (if applicable)

All this data is stored in JSON files within the `data/` subdirectory of the output folder. Storing the data this way
enables a few key benefits:

- **Better performance:**: Each check reads from pre-collected files instead of making repeated API calls
- **Consistent results**: All checks analyze the same point-in-time snapshot
- **Lower API load**: Fewer requests to the Kubernetes API server
- **More reliable runs**: Prevents issues like “*argument list too long*” when processing many resources

### Phase 2: diagnostic checks

After the context is built, individual diagnostic checks run in parallel, reading from the pre-collected data files.
Each check:

1. Validates that required resources exist (using helper functions like
   `require_pods`, `require_services`, `require_ingresses`)
2. Analyzes the data for specific issues
3. Reports findings with status: `success`, `failed`, or provides warnings
4. Generates actionable evidence and recommendations

---

## Diagnostic checks reference

Below is the complete list of diagnostic checks executed during a run. Checks are grouped by category and run in
parallel to identify common networking, scope, and service-level issues in the cluster.

### Networking checks (`k8s/diagnose/networking/`)
1. [ingress_existence](#1-ingress_existence) - `networking/ingress_existence`
2. [ingress_class_validation](#2-ingress_class_validation) - `networking/ingress_class_validation`
3. [ingress_controller_sync](#3-ingress_controller_sync) - `networking/ingress_controller_sync`
4. [ingress_host_rules](#4-ingress_host_rules) - `networking/ingress_host_rules`
5. [ingress_backend_service](#5-ingress_backend_service) - `networking/ingress_backend_service`
6. [ingress_tls_configuration](#6-ingress_tls_configuration) - `networking/ingress_tls_configuration`
7. [alb_capacity_check](#7-alb_capacity_check) - `networking/alb_capacity_check`

### Scope checks (`k8s/diagnose/scope/`)
1. [pod_existence](#1-pod_existence) - `scope/pod_existence`
2. [container_crash_detection](#2-container_crash_detection) - `scope/container_crash_detection`
3. [image_pull_status](#3-image_pull_status) - `scope/image_pull_status`
4. [memory_limits_check](#4-memory_limits_check) - `scope/memory_limits_check`
5. [pod_readiness](#5-pod_readiness) - `scope/pod_readiness`
6. [resource_availability](#6-resource_availability) - `scope/resource_availability`
7. [storage_mounting](#7-storage_mounting) - `scope/storage_mounting`
8. [container_port_health](#8-container_port_health) - `scope/container_port_health`
9. [health_probe_endpoints](#9-health_probe_endpoints) - `scope/health_probe_endpoints`

### Service checks (`k8s/diagnose/service/`)
1. [service_existence](#1-service_existence) - `service/service_existence`
2. [service_selector_match](#2-service_selector_match) - `service/service_selector_match`
3. [service_endpoints](#3-service_endpoints) - `service/service_endpoints`
4. [service_port_configuration](#4-service_port_configuration) - `service/service_port_configuration`
5. [service_type_validation](#5-service_type_validation) - `service/service_type_validation`


---

## Networking checks

### 1. ingress_existence

| **Aspect**                   | **Details**                                                                                                                                                               |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **What it detects**          | Missing ingress resources                                                                                                                                                 |
| **Common causes**            | - Ingress not created<br>- Ingress in wrong namespace<br>- Label selector mismatch<br>- Ingress deleted accidentally                                                      |
| **Possible solutions**       | - Create ingress resource<br>- Verify ingress is in correct namespace<br>- Check ingress labels match scope selectors<br>- Review ingress creation in deployment pipeline |
| **Example output (failure)** | `✗ No ingresses found with labels scope_id=123456 in namespace production`<br>`ℹ  Action: Create ingress resource to expose services externally`                          |
| **Example output (success)** | `✓ Found 1 ingress(es): web-app-ingress`<br>`ℹ  web-app-ingress hosts: example.com, www.example.com`                                                                      |

### 2. ingress_class_validation

| **Aspect**                   | **Details**                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **What it detects**          | Invalid or missing ingress class configuration                                                                                                                                                                                                                                                                                                                                 |
| **Common causes**            | - IngressClass does not exist<br>- Using deprecated annotation instead of ingressClassName<br>- No default IngressClass defined<br>- Ingress controller not installed                                                                                                                                                                                                          |
| **Possible solutions**       | - Install ingress controller (nginx, ALB, traefik, etc.)<br>- Create IngressClass resource<br>- Set default IngressClass:<br>  ```yaml<br>  metadata:<br>    annotations:<br>      ingressclass.kubernetes.io/is-default-class: "true"<br>  ```<br>- Update ingress to use `spec.ingressClassName` instead of annotation<br>- Verify IngressClass matches installed controller |
| **Example output (failure)** | `✗ Ingress web-app-ingress: IngressClass 'nginx-internal' not found`<br>`⚠  Available classes: nginx, alb`<br>`ℹ  Action: Use an available IngressClass or install the required controller`                                                                                                                                                                                    |
| **Example output (success)** | `✓ Ingress web-app-ingress: IngressClass 'alb' is valid`                                                                                                                                                                                                                                                                                                                       |

### 3. ingress_controller_sync

| **Aspect**                   | **Details**                                                                                                                                                                                                                                                                                               |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **What it detects**          | Ingress controller failing to reconcile/sync ingress resources                                                                                                                                                                                                                                            |
| **Common causes**            | - Ingress controller pods not running<br>- Backend service errors<br>- Certificate validation failures<br>- Subnet IP exhaustion (for ALB)<br>- Security group misconfiguration<br>- Ingress syntax errors                                                                                                |
| **Possible solutions**       | - Check ingress controller logs<br>- Verify backend services exist and have endpoints<br>- For ALB: check AWS ALB controller logs<br>- Verify certificates are valid<br>- Check subnet capacity<br>- Review ingress configuration for errors<br>- Ensure required AWS IAM permissions                     |
| **Example output (failure)** | `✗ Ingress web-app-ingress: Sync errors detected`<br>`  Found error/warning events:`<br>`    2024-01-15 10:30:45 Warning SyncError Failed to reconcile`<br>`✗  ALB address not assigned yet (sync may be in progress or failing)`<br>`ℹ  Action: Check ingress controller logs and verify backend services are healthy` |
| **Example output (success)** | `✓ All 2 ingress(es) synchronized successfully with controller`                                                                                                                                                                                                                                           |

### 4. ingress_host_rules

| **Aspect**                   | **Details**                                                                                                                                                                                                                                                        |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **What it detects**          | Invalid or problematic host and path rules                                                                                                                                                                                                                         |
| **Common causes**            | - No rules and no default backend defined<br>- Invalid pathType (must be Exact, Prefix, or ImplementationSpecific)<br>- Path ending with `/` for Prefix type (can cause routing issues)<br>- Duplicate host rules<br>- Wildcard hosts without proper configuration |
| **Possible solutions**       | - Define at least one rule or a default backend<br>- Use valid pathType values<br>- Remove trailing slashes from Prefix paths<br>- Consolidate duplicate host rules<br>- Specify explicit hostnames instead of wildcards when possible                             |
| **Example output (failure)** | `✗ Ingress web-app-ingress: No rules and no default backend configured`<br>`ℹ  Action: Add at least one rule or configure default backend`                                                                                                                         |
| **Example output (success)** | `✓ Host and path rules valid for all 2 ingress(es)`                                                                                                                                                                                                                |

### 5. ingress_backend_service

| **Aspect**                   | **Details**                                                                                                                                                                                                                                               |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **What it detects**          | Backend services that don't exist or have no endpoints                                                                                                                                                                                                    |
| **Common causes**            | - Backend service doesn't exist<br>- Service has no healthy endpoints<br>- Service port mismatch<br>- Service in different namespace (not supported)                                                                                                      |
| **Possible solutions**       | - Create missing backend services<br>- Fix service endpoint issues (see service_endpoints check)<br>- Verify service port matches ingress backend port<br>- Ensure all backends are in same namespace as ingress<br>- Check service selector matches pods |
| **Example output (failure)** | `✗ Ingress web-app-ingress: Backend api-service:8080 (no endpoints)`<br>`ℹ  Action: Verify pods are running and service selector matches`                                                                                                                 |
| **Example output (success)** | `✓ All backend services healthy for 2 ingress(es)`                                                                                                                                                                                                        |

### 6. ingress_tls_configuration

| **Aspect**                   | **Details**                                                                                                                                                                                                                     |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **What it detects**          | TLS/SSL certificate configuration issues                                                                                                                                                                                        |
| **Common causes**            | - TLS secret does not exist<br>- Secret is wrong type (not kubernetes.io/tls)<br>- Secret missing required keys (tls.crt, tls.key)<br>- Certificate expired or expiring soon<br>- Certificate doesn't cover requested hostnames |
| **Possible solutions**       | - Create TLS secret with certificate and key<br>- Verify secret type and keys<br>- Renew expired certificates<br>- Ensure certificate covers all ingress hosts<br>- For cert-manager, check certificate resource status         |
| **Example output (failure)** | `✗ Ingress web-app-ingress: TLS Secret 'app-tls-cert' not found in namespace`<br>`ℹ  Action: Create TLS secret or update ingress configuration`                                                                                 |
| **Example output (success)** | `✓ TLS configuration valid for all 2 ingress(es)`                                                                                                                                                                               |

### 7. alb_capacity_check

| **Aspect**                   | **Details**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **What it detects**          | AWS ALB-specific capacity and configuration issues                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **Common causes**            | - Subnet IP exhaustion<br>- Invalid or missing certificate ARN<br>- Security group misconfigurations<br>- Target group registration failures<br>- Missing or invalid subnet annotations<br>- Scheme not specified (internal vs internet-facing)                                                                                                                                                                                                                                                        |
| **Possible solutions**       | - For IP exhaustion: expand subnet CIDR or use different subnets<br>- Verify ACM certificate ARN exists and is in correct region<br>- Check security groups allow ALB traffic<br>- Review ALB controller logs for detailed errors<br>- Explicitly specify subnets:<br>  ```yaml<br>  annotations:<br>    alb.ingress.kubernetes.io/subnets: subnet-abc123,subnet-def456<br>  ```<br>- Specify scheme:<br>  ```yaml<br>  annotations:<br>    alb.ingress.kubernetes.io/scheme: internet-facing<br>  ``` |
| **Example output (failure)** | `✗ ALB capacity check failed`<br>`  ALB subnet IP exhaustion detected, Recent logs:`<br>`    Error allocating address: InsufficientFreeAddressesInSubnet`<br>`ℹ  Action: Check subnet CIDR ranges and consider expanding or using different subnets`<br>`ℹ  Annotation: alb.ingress.kubernetes.io/subnets=<subnet-ids>`                                                                                                                                                                                |
| **Example output (success)** | `✓ No critical ALB capacity or configuration issues detected`<br>`  No IP exhaustion issues detected`<br>`  SSL/TLS configured`<br>`    Certificate ARN: arn:aws:acm:us-east-1:123456789:certificate/abc123`<br>`  Scheme: internet-facing`                                                                                                                                                                                                                                                            |


## Scope checks

### 1. pod_existence

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Missing pod resources for the deployment |
| **Common causes** | - Pods not created<br>- Pods deleted or evicted<br>- Deployment failed to create pods<br>- Label selector mismatch<br>- Namespace mismatch |
| **Possible solutions** | - Check deployment status and events<br>- Verify deployment spec is correct<br>- Review pod creation errors<br>- Check resource quotas and limits<br>- Verify namespace and label selectors<br>- Review deployment controller logs |
| **Example output (failure)** | `✗ No pods found with labels scope_id=123456 in namespace production`<br>`ℹ  Action: Check deployment status and verify label selectors match` |
| **Example output (success)** | `✓ Found 3 pod(s): web-app-123-abc web-app-123-def web-app-123-ghi` |

### 2. container_crash_detection

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Containers that are crashing repeatedly (CrashLoopBackOff state) |
| **Common causes** | - Application crashes at startup<br>- Missing dependencies or configuration<br>- Invalid command or entrypoint<br>- OOMKilled (Out of Memory)<br>- Failed health checks causing restarts |
| **Possible solutions** | - Check application logs<br>- Review container command and arguments<br>- Verify environment variables and secrets are properly mounted<br>- Increase memory limits if OOMKilled<br>- Fix application code causing the crash<br>- Ensure all required config files exist |
| **Example output (failure)** | `✗ Pod web-app-123: CrashLoopBackOff in container(s): app`<br>`⚠  Container: app \| Restarts: 5 \| Exit Code: 1`<br>`⚠  Exit 1 = Application error`<br>`ℹ  Last logs from web-app-123:`<br>`    [application logs...]`<br>`ℹ  Action: Check container logs and fix application startup issues` |
| **Example output (success)** | `✓ All 3 pod(s) running without crashes` |

### 3. image_pull_status

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Failures to pull container images from registries |
| **Common causes** | - Image does not exist in the registry<br>- Incorrect image name or tag<br>- Missing or invalid imagePullSecrets for private registries<br>- Network connectivity issues to registry<br>- Registry authentication failures<br>- Rate limiting from public registries |
| **Possible solutions** | - Verify image name and tag are correct<br>- Check if image exists in registry<br>- For private registries, ensure imagePullSecrets are configured<br>- Verify registry credentials are valid<br>- Check network connectivity to registry<br>- Consider using a registry mirror or cache |
| **Example output (failure)** | `✗ Pod web-app-123: ImagePullBackOff/ErrImagePull in container(s): app`<br>`⚠  Image: registry.example.com/app:v1.0.0`<br>`⚠  Reason: Failed to pull image: pull access denied`<br>`ℹ  Action: Verify image exists and imagePullSecrets are configured for private registries` |
| **Example output (success)** | `✓ All 3 pod(s) have images pulled successfully` |

### 4. memory_limits_check

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Containers without memory limits configured |
| **Common causes** | - Missing resource limits in deployment specification<br>- Resource limits commented out or removed<br>- Using default configurations without limits |
| **Possible solutions** | - Add memory limits to container spec:<br>  ```yaml<br>  resources:<br>    limits:<br>      memory: "512Mi"<br>    requests:<br>      memory: "256Mi"<br>  ```<br>- Follow resource sizing best practices<br>- Monitor actual memory usage to set appropriate limits<br>- Consider using LimitRanges for namespace defaults |
| **Example output (failure)** | `✗ Pod web-app-123: Container app has no memory limits`<br>`ℹ  Current resources: requests.memory=128Mi, limits.memory=NONE`<br>`⚠  Risk: Container can consume all node memory`<br>`ℹ  Action: Add memory limits to prevent resource exhaustion` |
| **Example output (success)** | `✓ No OOMKilled containers detected in 3 pod(s)` |

### 5. pod_readiness

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Pods that are not ready to serve traffic |
| **Common causes** | - Readiness probe failing (HTTP endpoint returns non-2xx)<br>- Application not fully initialized<br>- Database connection failures<br>- Dependent services unavailable<br>- Readiness probe configured incorrectly<br>- Application port mismatch |
| **Possible solutions** | - Check readiness probe endpoint responds correctly<br>- Review application logs for initialization errors<br>- Verify dependent services are accessible<br>- Adjust `initialDelaySeconds` to allow more startup time<br>- Check readiness probe configuration (path, port, timeout)<br>- Ensure application is listening on correct port |
| **Example output (failure)** | `⚠ Pod web-app-123: Phase=Running, Ready=False`<br>`⚠  Reason: ContainersNotReady`<br>`⚠  Container Status:`<br>`    app: Ready=false, Restarts=0`<br>`ℹ  Action: Check application health endpoint and ensure dependencies are available` |
| **Example output (success)** | `✓ Pod web-app-123: Running and Ready` |

### 6. resource_availability

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Insufficient cluster resources to schedule pods |
| **Common causes** | - Requesting more CPU/memory than available on any node<br>- All nodes at capacity<br>- Resource quotas exceeded<br>- Taints/tolerations preventing scheduling<br>- Node selector/affinity rules too restrictive<br>- Too many replicas requested |
| **Possible solutions** | - Reduce resource requests in deployment<br>- Scale up cluster (add more nodes)<br>- Remove or adjust node selectors/affinity rules<br>- Check and adjust resource quotas<br>- Verify node taints and add tolerations if needed<br>- Review and optimize resource usage across cluster<br>- Consider pod priority classes for critical workloads |
| **Example output (failure)** | `✗ Pod web-app-123: Cannot be scheduled`<br>`⚠  Reason: 0/3 nodes are available: 1 Insufficient cpu, 2 Insufficient memory`<br>`⚠  Issue: Insufficient CPU in cluster`<br>`⚠  Issue: Insufficient memory in cluster`<br>`ℹ  Action: Reduce resource requests or add more nodes to cluster` |
| **Example output (success)** | `✓ All 3 pod(s) successfully scheduled with sufficient resources` |

### 7. storage_mounting

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Failures to mount volumes (PVCs, ConfigMaps, Secrets) |
| **Common causes** | - Referenced PersistentVolumeClaim does not exist<br>- PVC is bound to unavailable PersistentVolume<br>- Storage class does not exist<br>- ConfigMap or Secret not found<br>- Volume attachment failures (CSI driver issues)<br>- Insufficient storage capacity<br>- Multi-attach errors for ReadWriteOnce volumes |
| **Possible solutions** | - Verify PVC exists and is bound<br>- Check PVC status and events<br>- Ensure ConfigMap/Secret exists and is in correct namespace<br>- Verify storage class is available and properly configured<br>- Check storage provisioner logs for errors<br>- For multi-attach errors, ensure volume is detached from previous node<br>- Verify sufficient storage quota |
| **Example output (failure)** | `✗ Pod web-app-123: Volume mount failed`<br>`  Volume: data-volume (PersistentVolumeClaim)`<br>`  PVC: app-data-pvc`<br>`  Status: Pending`<br>`  Events:`<br>`    MountVolume.SetUp failed: PersistentVolumeClaim "app-data-pvc" not found`<br>`ℹ  Action: Create missing PVC or fix volume reference in deployment` |
| **Example output (success)** | `✓ All volumes mounted successfully for 3 pod(s)` |

### 8. container_port_health

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Containers not listening on their declared ports |
| **Common causes** | - Application configured to listen on different port than Kubernetes configuration<br>- Application failed to bind to port (permission issues, port conflict)<br>- Application code error preventing port binding<br>- Wrong port number in deployment spec<br>- Environment variable for port not set correctly |
| **Possible solutions** | - Check application configuration files (e.g., nginx.conf, application.properties)<br>- Verify environment variables controlling port binding<br>- Review application startup logs for port binding errors<br>- Ensure containerPort in deployment matches application's listen port<br>- Test port connectivity from within cluster |
| **Example output (failure)** | `ℹ  Checking pod web-app-123:`<br>`ℹ    Container 'application':`<br>`✗      Port 8080: ✗ Declared but not listening or unreachable`<br>`ℹ      Action: Check application configuration and ensure it listens on port 8080` |
| **Example output (success)** | `ℹ  Checking pod web-app-123:`<br>`ℹ    Container 'application':`<br>`✓      Port 8080: ✓ Listening` |

### 9. health_probe_endpoints

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Health probe endpoints (readiness, liveness, startup) that are misconfigured or failing |
| **Common causes** | - Health check endpoint path not found (404)<br>- Application not exposing health endpoint<br>- Port not listening or network unreachable<br>- Application returning errors (5xx) preventing health validation<br>- Path mismatch between probe config and application routes<br>- Health check dependencies failing (database, cache, etc.) |
| **Possible solutions** | - Verify health endpoint exists in application:<br>  ```yaml<br>  readinessProbe:<br>    httpGet:<br>      path: /health<br>      port: 8080<br>  ```<br>- Check application logs for health endpoint errors<br>- Ensure health endpoint path matches probe configuration<br>- For 5xx errors, fix application dependencies or internal issues<br>- For connection failures, verify port is listening and accessible<br>- Test endpoint manually: `curl http://POD_IP:PORT/health`<br>- Review probe timing settings (initialDelaySeconds, timeoutSeconds) |
| **Example output (failed)** | `ℹ  Checking pod web-app-123:`<br>`ℹ    Container 'app':`<br>`✗      Readiness Probe on HTTP://8080/health: ✗ HTTP 404 - Health check endpoint not found, verify path in deployment config`<br>`ℹ  Action: Update probe path or implement /health endpoint in application` |
| **Example output (warning)** | `ℹ  Checking pod web-app-123:`<br>`ℹ    Container 'app':`<br>`⚠      Readiness Probe on HTTP://8080/health: ⚠ HTTP 500 - Cannot complete check due to application error`<br>`⚠      Liveness Probe on HTTP://8080/health: ⚠ Connection failed (response: connection refused, exit code: 7)` |
| **Example output (success)** | `ℹ  Checking pod web-app-123:`<br>`ℹ    Container 'app':`<br>`✓      Readiness Probe on HTTP://8080/health: ✓ HTTP 200`<br>`✓      Liveness Probe on HTTP://8080/health: ✓ HTTP 200` |

---

## Service checks

### 1. service_existence

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Missing service resources for the deployment |
| **Common causes** | - Service not created<br>- Service deleted accidentally<br>- Service in wrong namespace<br>- Label selector mismatch preventing service discovery |
| **Possible solutions** | - Create service resource<br>- Verify service is in correct namespace<br>- Check service label selectors match pods<br>- Review service creation in CI/CD pipeline |
| **Example output (failure)** | `✗ No services found with labels scope_id=123456 in namespace production`<br>`ℹ  Action: Create service resource or verify label selectors` |
| **Example output (success)** | `✓ Found 1 service(s): web-app-service` |

### 2. service_selector_match

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Service selectors that don't match any pod labels |
| **Common causes** | - Service selector labels don't match pod labels<br>- Typo in selector or labels<br>- Labels changed in deployment but not in service<br>- Using wrong label keys or values |
| **Possible solutions** | - Compare service selectors with pod labels<br>- Update service selectors to match pods<br>- Ensure consistent labeling strategy<br>- Fix selectors in service definition |
| **Example output (failure)** | `✗ Service web-app-service: No pods match selector (app=web-app,env=prod)`<br>`⚠  Existing pods with deployment_id: web-app-123`<br>`ℹ  Pod labels: app=webapp,env=production,deployment_id=123`<br>`ℹ  Selector check: 8/10 labels match`<br>`⚠  Selector mismatches:`<br>`    ✗ app: selector='web-app', pod='webapp'`<br>`    ✗ env: selector='prod', pod='production'`<br>`ℹ  Action: Update service selectors to match pod labels` |
| **Example output (success)** | `✓ Service web-app-service: Selector matches 3 pod(s)` |

### 3. service_endpoints

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Services without healthy backend endpoints |
| **Common causes** | - No pods matching service selector<br>- All pods failing readiness probes<br>- Pods not exposing the correct port<br>- Network policy blocking traffic |
| **Possible solutions** | - Verify pods exist and match service selector<br>- Fix pod readiness issues<br>- Ensure container exposes port specified in service<br>- Check network policies allow traffic<br>- Verify service targetPort matches container port |
| **Example output (failure)** | `✗ Service web-app-service: No ready endpoints available`<br>`⚠  Not ready endpoints: 3`<br>`ℹ  Action: Check pod readiness probes and pod status` |
| **Example output (success)** | `✓ Service web-app-service: 3 ready endpoint(s)` |

### 4. service_port_configuration

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Service port configuration issues |
| **Common causes** | - Service targetPort doesn't match container port<br>- Container not listening on expected port<br>- Port protocol mismatch (TCP vs UDP)<br>- Named ports not defined in container |
| **Possible solutions** | - Verify container is listening on targetPort<br>- Check container port in deployment matches service targetPort<br>- Test port connectivity from within pod<br>- Review application logs for port binding issues<br>- Ensure protocol (TCP/UDP) matches application |
| **Example output (failure)** | `✗  Port 80 -> 8080 (http): Container port 8080 not found`<br>`⚠    Available ports by container: app: 3000,9090`<br>`ℹ    Action: Update service targetPort to match container port or fix container port` |
| **Example output (success)** | `✓ Service web-app-service port configuration:`<br>`  Port 80 → 8080 (http): OK` |

### 5. service_type_validation

| **Aspect** | **Details** |
|------------|-------------|
| **What it detects** | Invalid or unsupported service types |
| **Common causes** | - Using LoadBalancer type without cloud provider support<br>- NodePort outside allowed range<br>- Attempting to use ExternalName with selectors<br>- LoadBalancer stuck in pending state |
| **Possible solutions** | - Use appropriate service type for your environment<br>- For LoadBalancer without cloud provider, use NodePort or Ingress<br>- Verify cloud provider integration is configured<br>- Check NodePort is in valid range (30000-32767)<br>- Review cloud provider load balancer logs |
| **Example output (failure)** | `ℹ Service web-app-service: Type=LoadBalancer`<br>`⚠  LoadBalancer IP/Hostname is Pending`<br>`ℹ    This may take a few minutes to provision`<br>`ℹ    Action: Wait for provisioning or check cloud provider logs for errors` |
| **Example output (success)** | `✓ Service web-app-service: Type=ClusterIP`<br>`  Internal service with ClusterIP: 10.96.100.50` |



---

## Quick reference: error categories

| **Category** | **Checks** | **Common Root Causes** |
|--------------|------------|------------------------|
| **Pod Issues** | container_crash_detection, image_pull_status, pod_readiness, container_port_health, health_probe_endpoints | Application errors, configuration issues, image problems, port misconfigurations, health check failures |
| **Resource Issues** | memory_limits_check, resource_availability, storage_mounting | Insufficient resources, missing limits, capacity planning |
| **Service Routing** | service_existence, service_selector_match, service_endpoints | Label mismatches, configuration errors, no healthy pods |
| **Ingress/Networking** | ingress_existence, ingress_class_validation, ingress_controller_sync | Missing resources, controller issues, backend problems |
| **TLS/Security** | ingress_tls_configuration, alb_capacity_check | Certificate issues, missing secrets, AWS-specific problems |