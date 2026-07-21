{
  "assignable_to": "any",
  "attributes": {
   "schema":{
      "type":"object",
      "required":[
         "ram_memory",
         "ram_memory_limit",
         "visibility",
         "logs_provider_override",
         "autoscaling",
         "health_check",
         "scaling_type",
         "cpu_millicores",
         "cpu_millicores_limit",
         "fixed_instances",
         "scheduled_stop",
         "additional_ports",
         "main_http_port",
         "protocol",
         "continuous_delivery"
      ],
      "uiSchema":{
         "type":"VerticalLayout",
         "elements":[
            {
               "type":"Control",
               "label":"RAM Memory",
               "scope":"#/properties/ram_memory"
            },
            {
               "type":"Control",
               "label":"Visibility",
               "scope":"#/properties/visibility",
               "options":{
                  "format":"radio"
               }
            },
            {
               "type":"Categorization",
               "options":{
                  "collapsable":{
                     "label":"ADVANCED",
                     "collapsed":true
                  }
               },
               "elements":[
                  {
                     "type":"Category",
                     "label":"Logs",
                     "elements":[
                        {
                           "type":"Control",
                           "label":"Logs provider",
                           "scope":"#/properties/logs_provider_override",
                           "options":{
                              "format":"radio"
                           }
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Resources",
                     "elements":[
                        {
                           "type":"Control",
                           "label":"CPU Millicores",
                           "scope":"#/properties/cpu_millicores"
                        },
                        {
                           "type":"Control",
                           "label":"CPU Millicores Limit",
                           "scope":"#/properties/cpu_millicores_limit"
                        },
                        {
                           "type":"Control",
                           "label":"RAM Memory Limit",
                           "scope":"#/properties/ram_memory_limit"
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Size & Scaling",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/scaling_type"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/scaling_type",
                                 "schema":{
                                    "enum":[
                                       "fixed"
                                    ]
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/fixed_instances"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/scaling_type",
                                 "schema":{
                                    "enum":[
                                       "auto"
                                    ]
                                 }
                              }
                           },
                           "type":"Group",
                           "label":"Autoscaling Settings",
                           "elements":[
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/min_replicas"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/max_replicas"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/target_cpu_utilization"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/target_memory_enabled"
                              },
                              {
                                 "rule": {
                                   "effect": "SHOW",
                                   "condition": {
                                     "scope": "#/properties/autoscaling/properties/target_memory_enabled",
                                     "schema": {
                                       "const": true
                                     }
                                   }
                                 },
                                 "type": "Control",
                                 "scope": "#/properties/autoscaling/properties/target_memory_utilization"
                              }
                           ]
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Exposed Ports",
                     "elements":[
                        {
                           "type":"Control",
                           "label":"Main HTTP Port",
                           "scope":"#/properties/main_http_port"
                        },
                        {
                           "type":"Control",
                           "scope":"#/properties/additional_ports",
                           "options":{
                              "detail":{
                                 "type":"VerticalLayout",
                                 "elements":[
                                    {
                                       "type":"Control",
                                       "scope":"#/properties/port"
                                    },
                                    {
                                       "type":"Control",
                                       "scope":"#/properties/type"
                                    }
                                 ]
                              }
                           }
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Scheduled Stop",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/scheduled_stop/properties/enabled"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/scheduled_stop/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/scheduled_stop/properties/timer"
                        }
                     ]
                  },
                  {
                    "type": "Category",
                    "label": "Protocol",
                    "elements": [
                      {
                        "type": "Control",
                        "scope": "#/properties/protocol",
                        "options": {
                          "format": "radio"
                        }
                      }
                    ]
                  },
                  {
                     "type":"Category",
                     "label":"Continuous deployment",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/continuous_delivery/properties/enabled"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/continuous_delivery/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/continuous_delivery/properties/branches"
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Health Check",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/enabled"
                        },
                        {
                          "rule": {
                            "effect": "SHOW",
                            "condition": {
                              "scope": "#/properties/health_check/properties/enabled",
                              "schema": {
                                "const": true
                              }
                            }
                          },
                          "type": "Control",
                          "scope": "#/properties/health_check/properties/type",
                          "options":{
                            "format":"radio"
                          }
                        },
                        {
                          "rule": {
                            "effect": "SHOW",
                            "condition": {
                              "type": "AND",
                              "conditions": [
                                {
                                  "scope": "#/properties/health_check/properties/type",
                                  "schema": {
                                    "const": "HTTP"
                                  }
                                },
                                {
                                  "scope": "#/properties/health_check/properties/enabled",
                                  "schema": {
                                    "const": true
                                  }
                                }
                              ]
                            }
                          },
                          "type": "Control",
                          "scope": "#/properties/health_check/properties/path"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/health_check/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/initial_delay_seconds"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/health_check/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/period_seconds"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/health_check/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/timeout_seconds"
                        }
                     ]
                  }
               ]
            }
         ]
      },
      "properties":{
         "asset_type":{
            "type":"string",
            "export":false,
            "default":"docker-image"
         },
         "ram_memory":{
            "type":"integer",
            "oneOf":[
               {
                  "const":64,
                  "title":"64 MB"
               },
               {
                  "const":128,
                  "title":"128 MB"
               },
               {
                  "const":256,
                  "title":"256 MB"
               },
               {
                  "const":512,
                  "title":"512 MB"
               },
               {
                  "const":1024,
                  "title":"1 GB"
               },
               {
                  "const":2048,
                  "title":"2 GB"
               },
               {
                  "const":4096,
                  "title":"4 GB"
               },
               {
                  "const":8192,
                  "title":"8 GB"
               },
               {
                  "const":16384,
                  "title":"16 GB"
               }
            ],
            "title":"RAM Memory",
            "default":128,
            "description":"Amount of RAM memory to allocate to the container (in MB)"
         },
         "ram_memory_limit":{
            "type":["integer","null"],
            "oneOf":[
               {"const":null,  "title":"Same as request"},
               {"const":64,    "title":"64 MB"},
               {"const":128,   "title":"128 MB"},
               {"const":256,   "title":"256 MB"},
               {"const":512,   "title":"512 MB"},
               {"const":1024,  "title":"1 GB"},
               {"const":2048,  "title":"2 GB"},
               {"const":4096,  "title":"4 GB"},
               {"const":8192,  "title":"8 GB"},
               {"const":16384, "title":"16 GB"}
            ],
            "title":"RAM Memory Limit",
            "default":null,
            "minimum":{
               "$data":"1/ram_memory"
            },
            "description":"Maximum memory the container can use (in MB). Pick 'Same as request' to leave it equal to the request value."
         },
         "visibility":{
            "type":"string",
            "oneOf":[
               {
                  "const":"public",
                  "title":"Internet",
                  "description":"Public, reachable by anyone"
               },
               {
                  "const":"internal",
                  "title":"Main Account",
                  "description":"Only visible inside your organization"
               }
            ],
            "title":"Visibility",
            "default":"public",
            "editableOn": [
                "create"
            ],
            "description":"Define whether the scope is publicly accessible or private to your account"
         },
         "logs_provider_override":{
            "type":"string",
            "oneOf":[
               {
                  "const":"default",
                  "title":"Account default",
                  "description":"Use the account/provider-level log provider (logProvider)"
               },
               {
                  "const":"cloudwatch_logs",
                  "title":"CloudWatch",
                  "description":"Send this scope's application logs to AWS CloudWatch"
               },
               {
                  "const":"datadoglogs",
                  "title":"Datadog",
                  "description":"Send this scope's application logs to Datadog"
               }
            ],
            "title":"Logs provider",
            "default":"default",
            "description":"Override where this scope's application logs are sent. 'Account default' delegates to the account-level logProvider."
         },
         "autoscaling":{
            "type":"object",
            "properties":{
               "max_replicas":{
                  "type":"integer",
                  "title":"Maximum Replicas",
                  "default":5,
                  "maximum":20,
                  "minimum":1,
                  "description":"Maximum number of instances to scale to"
               },
               "min_replicas":{
                  "type":"integer",
                  "title":"Minimum Replicas",
                  "default":1,
                  "maximum":10,
                  "minimum":1,
                  "description":"Minimum number of instances to maintain"
               },
               "target_cpu_utilization":{
                  "type":"integer",
                  "title":"Target CPU Utilization (%)",
                  "default":70,
                  "maximum":90,
                  "minimum":50,
                  "description":"CPU utilization threshold that triggers scaling"
               },
               "target_memory_enabled": {
                 "type": "boolean",
                 "title": "Scale by memory",
                 "default": false
               },
               "target_memory_utilization": {
                 "type": "integer",
                 "title": "Target memory utilization (%)",
                 "default": 70,
                 "maximum": 90,
                 "minimum": 50,
                 "description": "Memory utilization threshold that triggers scaling"
               }
            }
         },
         "health_check":{
            "type":"object",
            "properties":{
               "path":{
                  "type":"string",
                  "title":"Health Check Path",
                  "default":"/health",
                  "description":"HTTP path for health check requests"
               },
               "enabled":{
                  "type":"boolean",
                  "title":"Enable Health Check",
                  "default":true
               },
               "period_seconds":{
                  "type":"integer",
                  "title":"Check Interval",
                  "default":10,
                  "maximum":300,
                  "minimum":1,
                  "description":"Seconds between health checks",
                  "exclusiveMinimum": {
                     "$data": "1/timeout_seconds"
                  }
               },
               "timeout_seconds":{
                  "type":"integer",
                  "title":"Timeout",
                  "default":5,
                  "maximum":60,
                  "minimum":1,
                  "description":"Seconds to wait for a health check response"
               },
               "initial_delay_seconds":{
                  "type":"integer",
                  "title":"Initial Delay",
                  "default":30,
                  "maximum":300,
                  "minimum":0,
                  "description":"Seconds to wait before starting health checks"
               },
               "type": {
                 "type": "string",
                 "title": "Health check type",
                 "default": "HTTP",
                 "enum": [
                   "HTTP",
                   "TCP"
                 ],
                 "description": "To be applied in startup, readiness and liveness probes"
               }
            }
         },
         "scaling_type":{
            "enum":[
               "fixed",
               "auto"
            ],
            "type":"string",
            "title":"Scaling Type",
            "default":"fixed",
            "description":"Choose between fixed number of instances or automatic scaling"
         },
         "cpu_millicores":{
            "type":"integer",
            "title":"CPU Millicores",
            "default":100,
            "maximum":4000,
            "minimum":100,
            "description":"Amount of CPU to allocate (in millicores, 1000m = 1 CPU core)"
         },
         "cpu_millicores_limit":{
            "type":["integer","null"],
            "oneOf":[
               {"const":null, "title":"Same as request"},
               {"const":100,  "title":"100 m"},
               {"const":250,  "title":"250 m"},
               {"const":500,  "title":"500 m"},
               {"const":1000, "title":"1000 m"},
               {"const":2000, "title":"2000 m"},
               {"const":4000, "title":"4000 m"}
            ],
            "title":"CPU Millicores Limit",
            "default":null,
            "minimum":{
               "$data":"1/cpu_millicores"
            },
            "description":"Maximum CPU the container can use (in millicores). Pick 'Same as request' to leave it equal to the request value."
         },
         "scheduled_stop":{
            "type":"object",
            "title":"Scheduled Stop",
            "required":[
               "enabled",
               "timer"
            ],
            "properties":{
               "timer":{
                  "type":"string",
                  "oneOf":[
                     {
                        "const":"3600",
                        "title":"1 hour"
                     },
                     {
                        "const":"10800",
                        "title":"3 hours"
                     },
                     {
                        "const":"21600",
                        "title":"6 hours"
                     },
                     {
                        "const":"43200",
                        "title":"12 hours"
                     },
                     {
                        "const":"tonight",
                        "title":"Tonight"
                     }
                  ],
                  "title":"Stop After",
                  "default":"3600",
                  "description":"When to automatically stop the service"
               },
               "enabled":{
                  "type":"boolean",
                  "title":"Enable Scheduled Stop",
                  "default":false,
                  "description":"Automatically stop the service after a specified time"
               }
            },
            "description":"Configure automatic stopping of the service"
         },
         "fixed_instances":{
            "type":"integer",
            "title":"Number of Instances",
            "default":1,
            "maximum":10,
            "minimum":1,
            "description":"Fixed number of instances to run"
         },
         "main_http_port":{
            "type":"integer",
            "title":"Main HTTP Port",
            "default":8080,
            "minimum":1024,
            "maximum":65535,
            "description":"Port where your application's main HTTP listener binds. Default 8080."
         },
         "additional_ports":{
            "type":"array",
            "items":{
               "type":"object",
               "required":[
                  "port",
                  "type"
               ],
               "properties":{
                  "port":{
                     "type":"integer",
                     "title":"Port Number",
                     "maximum":65535,
                     "minimum":1024,
                     "description":"The port number to expose (1024-65535)"
                  },
                  "type":{
                     "enum":[
                        "GRPC",
                        "HTTP"
                     ],
                     "type":"string",
                     "title":"Port Type",
                     "default": "HTTP",
                     "description":"The protocol type for this port"
                  }
               }
            },
            "title":"Additional Ports",
            "default":[

            ],
            "description":"Configure additional ports for your application"
         },
         "continuous_delivery":{
            "type":"object",
            "title":"Continuous Delivery",
            "required":[
               "enabled",
               "branches"
            ],
            "properties":{
               "enabled":{
                  "type":"boolean",
                  "title":"Enable Continuous Delivery",
                  "default":false,
                  "description":"Automatically deploy new versions from specified branches"
               },
               "branches":{
                  "type":"array",
                  "items":{
                     "type":"string"
                  },
                  "title":"Branches",
                  "default":[
                     "main"
                  ],
                  "description":"Git branches to monitor for automatic deployment"
               }
            },
            "description":"Configure automatic deployment from Git branches"
         },
         "custom_domains": {
            "type": "object",
            "required": [
               "enabled"
            ],
            "properties": {
               "enabled": {
               "type": "boolean",
               "default": true
               }
            }
         },
         "protocol": {
           "type": "string",
           "oneOf": [
             {
               "const": "http",
               "title": "HTTP connections",
               "description": "Enable http web server"
             },
             {
               "const": "web_sockets",
               "title": "Web sockets",
               "description": "Enable web sockets connections"
             }
           ],
           "title": "Protocol",
           "default": "http",
           "description": "Define the inbound traffic the application will accept"
         }
      }
   }
  },
  "name": "Containers",
  "selectors": {
    "category": "Scope",
    "imported": false,
    "provider": "Agent",
    "sub_category": "Containers"
  },
  "type": "scope",
  "use_default_actions": false,
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ]
}
