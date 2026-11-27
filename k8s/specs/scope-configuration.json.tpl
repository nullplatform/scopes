{
  "name": "Containers",
  "description": "Settings of the k8s containers scope (k8s/README.md). Every key is optional; an unset key falls back as its description says. Providers win over the agent's environment.",
  "category": "scope-configurations",
  "icon": "mdi:kubernetes",
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "properties": {
      "cluster": {
        "type": "object",
        "title": "Cluster",
        "description": "Kubernetes namespace of the scope's objects.",
        "properties": {
          "namespace": {
            "type": "string",
            "title": "Namespace",
            "description": "Namespace, or a pattern such as {.namespace.slug} for one namespace per nullplatform namespace. Unset: container-orchestration cluster.namespace, then NAMESPACE_OVERRIDE or K8S_NAMESPACE, then nullplatform.",
            "order": 1
          },
          "create_namespace_if_not_exist": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "Create the namespace",
            "description": "Create the namespace when it does not exist. Unset: CREATE_K8S_NAMESPACE_IF_NOT_EXIST, then true.",
            "order": 2
          }
        },
        "order": 1
      },
      "networking": {
        "type": "object",
        "title": "Networking",
        "description": "Domains, DNS, gateways, load balancers and service-to-service traffic.",
        "properties": {
          "domain_name": {
            "type": "string",
            "title": "Domain name",
            "description": "Zone for public scopes (and private ones without a private zone). Unset: cloud-providers networking.domain_name, then nullapps.io.",
            "order": 1
          },
          "private_domain_name": {
            "type": "string",
            "title": "Private domain name",
            "description": "Zone for private scopes. Unset: cloud-providers networking.private_domain_name, then the domain name.",
            "order": 2
          },
          "application_domain": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "Prefix domains with the account slug",
            "description": "Unset: cloud-providers networking.application_domain, then false.",
            "order": 3
          },
          "dns_type": {
            "type": "string",
            "enum": [
              "route53",
              "azure",
              "external_dns"
            ],
            "title": "DNS type",
            "description": "Unset: DNS_TYPE, then route53.",
            "order": 4
          },
          "hosted_zone_name": {
            "type": "string",
            "title": "Azure DNS zone",
            "description": "Azure DNS hosted zone name. Unset: HOSTED_ZONE_NAME.",
            "order": 5
          },
          "hosted_zone_rg": {
            "type": "string",
            "title": "Azure DNS zone resource group",
            "description": "Unset: HOSTED_ZONE_RG.",
            "order": 6
          },
          "azure_subscription_id": {
            "type": "string",
            "title": "Azure subscription ID",
            "description": "Subscription for DNS management. Unset: AZURE_SUBSCRIPTION_ID.",
            "order": 7
          },
          "resource_group": {
            "type": "string",
            "title": "Azure resource group",
            "description": "Resource group of the cluster's resources. Unset: RESOURCE_GROUP.",
            "order": 8
          },
          "gateway_public_name": {
            "type": "string",
            "title": "Public gateway",
            "description": "Gateway of public scopes. Unset: container-orchestration gateway.public_name, then PUBLIC_GATEWAY_NAME, then gateway-public.",
            "order": 9
          },
          "gateway_private_name": {
            "type": "string",
            "title": "Private gateway",
            "description": "Gateway of private scopes. Unset: container-orchestration gateway.private_name, then PRIVATE_GATEWAY_NAME, then gateway-internal.",
            "order": 10
          },
          "gateway_namespace": {
            "type": "string",
            "title": "Gateway namespace",
            "description": "Namespace of the public and private gateways. Unset: container-orchestration gateway.namespace, then GATEWAY_NAMESPACE, then gateways.",
            "order": 11
          },
          "additional_public_gateways": {
            "type": "array",
            "title": "Additional public gateways",
            "description": "Extra gateways the HTTPRoute of public scopes is attached to. Unset: container-orchestration gateway.additional_public_gateways.",
            "items": {
              "type": "object",
              "required": [
                "name"
              ],
              "properties": {
                "name": {
                  "type": "string",
                  "title": "Name"
                },
                "namespace": {
                  "type": "string",
                  "title": "Namespace",
                  "description": "Unset: the gateway namespace."
                }
              }
            },
            "order": 12
          },
          "additional_private_gateways": {
            "type": "array",
            "title": "Additional private gateways",
            "description": "Extra gateways the HTTPRoute of private scopes is attached to. Unset: container-orchestration gateway.additional_private_gateways.",
            "items": {
              "type": "object",
              "required": [
                "name"
              ],
              "properties": {
                "name": {
                  "type": "string",
                  "title": "Name"
                },
                "namespace": {
                  "type": "string",
                  "title": "Namespace",
                  "description": "Unset: the gateway namespace."
                }
              }
            },
            "order": 13
          },
          "balancer_public_name": {
            "type": "string",
            "title": "Public ALB",
            "description": "Base ALB of public scopes. Unset: container-orchestration balancer.public_name, then ALB_NAME.",
            "order": 14
          },
          "balancer_private_name": {
            "type": "string",
            "title": "Private ALB",
            "description": "Base ALB of private scopes. Unset: container-orchestration balancer.private_name, then ALB_NAME.",
            "order": 15
          },
          "additional_public_balancers": {
            "type": "array",
            "title": "Additional public ALBs",
            "description": "ALB names added to the public candidate pool; the least loaded is used. Unset: container-orchestration balancer.additional_public_names.",
            "items": {
              "type": "string",
              "minLength": 1
            },
            "order": 16
          },
          "additional_private_balancers": {
            "type": "array",
            "title": "Additional private ALBs",
            "description": "ALB names added to the private candidate pool; the least loaded is used. Unset: container-orchestration balancer.additional_private_names.",
            "items": {
              "type": "string",
              "minLength": 1
            },
            "order": 17
          },
          "alb_max_capacity": {
            "type": "integer",
            "title": "ALB capacity threshold",
            "description": "Rule count at which an ALB counts as full. Unset: container-orchestration balancer.alb_capacity_threshold, then ALB_MAX_CAPACITY, then 75.",
            "minimum": 0,
            "order": 18
          },
          "alb_max_target_groups": {
            "type": "integer",
            "title": "ALB max target groups",
            "description": "Unset: container-orchestration balancer.alb_max_target_groups, then ALB_MAX_TARGET_GROUPS, then 98 (AWS limit 100).",
            "minimum": 0,
            "order": 19
          },
          "alb_max_listeners": {
            "type": "integer",
            "title": "ALB max listeners",
            "description": "Unset: container-orchestration balancer.alb_max_listeners, then ALB_MAX_LISTENERS, then 48 (AWS limit 50).",
            "minimum": 0,
            "order": 20
          },
          "alb_reconciliation_enabled": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "ALB reconciliation",
            "description": "Unset: ALB_RECONCILIATION_ENABLED, then false.",
            "order": 21
          },
          "alb_metrics_enabled": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "Publish ALB metrics",
            "description": "Publish rule and target group counts. Unset: ALB_METRICS_PUBLISH_ENABLED, then false.",
            "order": 22
          },
          "alb_metrics_target": {
            "type": "string",
            "enum": [
              "cloudwatch",
              "datadog"
            ],
            "title": "ALB metrics target",
            "description": "Unset: ALB_METRICS_PUBLISH_TARGET, then cloudwatch.",
            "order": 23
          },
          "service_to_service": {
            "type": "object",
            "title": "Service-to-service",
            "description": "Stable in-cluster name {app}-{scope}.{namespace}.svc.<cluster domain> through an Istio gateway (k8s/docs/service-to-service.md). Each key falls back to container-orchestration gateway.service_to_service.",
            "properties": {
              "enabled": {
                "type": "string",
                "enum": [
                  "true",
                  "false"
                ],
                "title": "Enabled",
                "description": "Unset: SERVICE_TO_SERVICE_ENABLED, then false.",
                "order": 1
              },
              "mode": {
                "type": "string",
                "enum": [
                  "shared",
                  "dedicated"
                ],
                "title": "Mode",
                "description": "shared: the scope's private gateway; dedicated: gateway-in-cluster, also answering <svc>.<ns>. Must match the gateway installed in the cluster. Unset: SERVICE_TO_SERVICE_MODE, then shared.",
                "order": 2
              },
              "gateway_name": {
                "type": "string",
                "title": "Gateway",
                "description": "Unset: the private gateway (shared) or gateway-in-cluster (dedicated).",
                "order": 3
              },
              "listener_prefix": {
                "type": "string",
                "title": "Listener prefix",
                "description": "Listeners are <prefix><port>. Unset: in-cluster-.",
                "order": 4
              },
              "cluster_domain": {
                "type": "string",
                "title": "Cluster domain",
                "description": "Unset: cluster.local.",
                "order": 5
              },
              "name_pattern": {
                "type": "string",
                "title": "Name pattern",
                "description": "Resource naming pattern of the stable name, 63 characters. Kept once created. Unset: {.application.slug}-{.scope.slug}.",
                "order": 6
              }
            },
            "order": 24
          }
        },
        "order": 2
      },
      "deployment": {
        "type": "object",
        "title": "Deployment",
        "description": "Strategy, traffic proxy, disruption budget and manifest backup.",
        "properties": {
          "deployment_strategy": {
            "type": "string",
            "enum": [
              "blue-green",
              "rolling"
            ],
            "title": "Strategy",
            "description": "Unset: DEPLOY_STRATEGY, then blue-green.",
            "order": 1
          },
          "deployment_max_wait_seconds": {
            "type": "integer",
            "title": "Max wait (seconds)",
            "description": "Unset: DEPLOYMENT_MAX_WAIT_IN_SECONDS, then 600.",
            "minimum": 1,
            "order": 2
          },
          "traffic_proxy": {
            "type": "string",
            "enum": [
              "nginx",
              "istio"
            ],
            "title": "Traffic proxy",
            "description": "nginx: traffic-manager sidecar; istio: no sidecar, metrics from the Istio gateway. Unset: TRAFFIC_PROXY, then nginx.",
            "order": 3
          },
          "traffic_container_image": {
            "type": "string",
            "title": "Traffic manager image",
            "description": "Unset: TRAFFIC_CONTAINER_IMAGE, then public.ecr.aws/nullplatform/k8s-traffic-manager:<traffic_manager.version>.",
            "order": 4
          },
          "traffic_manager_config_map": {
            "type": "string",
            "title": "Traffic manager ConfigMap",
            "description": "ConfigMap with a custom traffic manager configuration; not with the istio proxy. Unset: TRAFFIC_MANAGER_CONFIG_MAP.",
            "order": 5
          },
          "main_traffic_manager_port": {
            "type": "integer",
            "title": "Traffic manager port",
            "description": "Unset: container-orchestration traffic_manager.port, then MAIN_TRAFFIC_MANAGER_PORT, then 80.",
            "minimum": 1,
            "maximum": 65535,
            "order": 6
          },
          "prestop_sleep_mode": {
            "type": "string",
            "enum": [
              "exec",
              "native"
            ],
            "title": "preStop sleep mode",
            "description": "exec: /bin/sleep in the image; native: kubelet sleep action (Kubernetes >= 1.30). Unset: PRESTOP_SLEEP_MODE, then exec.",
            "order": 7
          },
          "pod_disruption_budget_enabled": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "Pod disruption budget",
            "description": "Unset: POD_DISRUPTION_BUDGET_ENABLED, then false.",
            "order": 8
          },
          "pod_disruption_budget_max_unavailable": {
            "type": "string",
            "title": "PDB max unavailable",
            "description": "Number or percentage. Unset: POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE, then 25%.",
            "pattern": "^[0-9]+%?$",
            "order": 9
          },
          "manifest_backup_enabled": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "Manifest backup",
            "description": "Ignored when MANIFEST_BACKUP is set. Unset: false.",
            "order": 10
          },
          "manifest_backup_type": {
            "type": "string",
            "enum": [
              "s3"
            ],
            "title": "Backup storage",
            "description": "Storage of the backups.",
            "order": 11
          },
          "manifest_backup_bucket": {
            "type": "string",
            "title": "Backup bucket",
            "description": "S3 bucket for the backups.",
            "order": 12
          },
          "manifest_backup_prefix": {
            "type": "string",
            "title": "Backup prefix",
            "description": "Path prefix within the bucket.",
            "order": 13
          }
        },
        "order": 3
      },
      "naming": {
        "type": "object",
        "title": "Naming",
        "description": "Kubernetes object names (k8s/docs/resource-naming.md). Each key falls back to container-orchestration naming.",
        "properties": {
          "strategy": {
            "type": "string",
            "enum": [
              "ids",
              "qualified",
              "custom"
            ],
            "title": "Strategy",
            "description": "Unset: NAMING_STRATEGY, then ids.",
            "order": 1
          },
          "deployment_pattern": {
            "type": "string",
            "title": "Deployment pattern",
            "description": "Used with the custom strategy. Unset: NAMING_DEPLOYMENT_PATTERN.",
            "order": 2
          },
          "scope_pattern": {
            "type": "string",
            "title": "Scope pattern",
            "description": "Used with the custom strategy. Unset: NAMING_SCOPE_PATTERN.",
            "order": 3
          },
          "max_length": {
            "type": "integer",
            "title": "Max length",
            "description": "Budget of deployment-scoped names. Unset: NAMING_MAX_LENGTH, then 46.",
            "minimum": 1,
            "maximum": 63,
            "order": 4
          }
        },
        "order": 4
      },
      "security": {
        "type": "object",
        "title": "Security",
        "description": "Image pull secrets, IAM and Vault.",
        "properties": {
          "image_pull_secrets_enabled": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "Image pull secrets",
            "description": "Ignored when IMAGE_PULL_SECRETS is set. Unset: false.",
            "order": 1
          },
          "image_pull_secrets": {
            "type": "array",
            "title": "Image pull secret names",
            "description": "Ignored when IMAGE_PULL_SECRETS is set.",
            "items": {
              "type": "string",
              "minLength": 1
            },
            "order": 2
          },
          "iam_enabled": {
            "type": "string",
            "enum": [
              "true",
              "false"
            ],
            "title": "IAM role",
            "description": "Create an IAM role per scope. Ignored when IAM is set. Unset: false.",
            "order": 3
          },
          "iam_prefix": {
            "type": "string",
            "title": "IAM prefix",
            "description": "Role name prefix, or a pattern such as {.account.slug}-{.namespace.slug}.",
            "order": 4
          },
          "iam_policies": {
            "type": "array",
            "title": "IAM policies",
            "description": "Policies attached to the role.",
            "items": {
              "type": "object",
              "required": [
                "TYPE",
                "VALUE"
              ],
              "properties": {
                "TYPE": {
                  "type": "string",
                  "enum": [
                    "arn",
                    "inline"
                  ],
                  "title": "Type"
                },
                "VALUE": {
                  "type": "string",
                  "title": "Policy ARN or inline policy JSON"
                }
              }
            },
            "order": 5
          },
          "iam_boundary_arn": {
            "type": "string",
            "title": "IAM boundary ARN",
            "description": "Permissions boundary of the role.",
            "order": 6
          },
          "vault_address": {
            "type": "string",
            "title": "Vault address",
            "description": "Unset: VAULT_ADDR.",
            "order": 7
          },
          "vault_token": {
            "type": "string",
            "title": "Vault token",
            "description": "Unset: VAULT_TOKEN.",
            "order": 8
          }
        },
        "order": 5
      },
      "object_modifiers": {
        "type": "object",
        "title": "Object modifiers",
        "description": "Labels and annotations added to the scope's Kubernetes objects, per object kind or global. Unset: K8S_MODIFIERS.",
        "properties": {
          "global": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "title": "Labels",
                "additionalProperties": {
                  "type": "string"
                }
              },
              "annotations": {
                "type": "object",
                "title": "Annotations",
                "additionalProperties": {
                  "type": "string"
                }
              }
            }
          },
          "deployment": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "title": "Labels",
                "additionalProperties": {
                  "type": "string"
                }
              },
              "annotations": {
                "type": "object",
                "title": "Annotations",
                "additionalProperties": {
                  "type": "string"
                }
              }
            }
          },
          "service": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "title": "Labels",
                "additionalProperties": {
                  "type": "string"
                }
              },
              "annotations": {
                "type": "object",
                "title": "Annotations",
                "additionalProperties": {
                  "type": "string"
                }
              }
            }
          },
          "ingress": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "title": "Labels",
                "additionalProperties": {
                  "type": "string"
                }
              },
              "annotations": {
                "type": "object",
                "title": "Annotations",
                "additionalProperties": {
                  "type": "string"
                }
              }
            }
          },
          "pdb": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "title": "Labels",
                "additionalProperties": {
                  "type": "string"
                }
              },
              "annotations": {
                "type": "object",
                "title": "Annotations",
                "additionalProperties": {
                  "type": "string"
                }
              }
            }
          },
          "secret": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "title": "Labels",
                "additionalProperties": {
                  "type": "string"
                }
              },
              "annotations": {
                "type": "object",
                "title": "Annotations",
                "additionalProperties": {
                  "type": "string"
                }
              }
            }
          },
          "service_account": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "title": "Labels",
                "additionalProperties": {
                  "type": "string"
                }
              },
              "annotations": {
                "type": "object",
                "title": "Annotations",
                "additionalProperties": {
                  "type": "string"
                }
              }
            }
          }
        },
        "order": 6
      }
    }
  }
}
