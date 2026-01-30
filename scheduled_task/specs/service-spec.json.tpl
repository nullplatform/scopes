{
  "assignable_to": "any",
  "attributes": {
    "schema": {
      "properties": {
        "asset_type": {
          "default": "docker-image",
          "export": false,
          "type": "string"
        },
        "concurrency_policy": {
          "default": "Forbid",
          "description": "Determines what happens if a new run is scheduled while the previous one is still in progress.",
          "oneOf": [
            {
              "const": "Allow",
              "title": "Allow concurrenct executions."
            },
            {
              "const": "Forbid",
              "title": "Skip execution if last one still running"
            },
            {
              "const": "Replace",
              "title": "Halt running exectution and start a new one"
            }
          ],
          "type": "string"
        },
        "continuous_delivery": {
          "description": "Configure automatic deployment from Git branches or releases",
          "properties": {
            "enabled": {
              "default": false,
              "description": "Automatically deploy new versions from specified branches or releases",
              "title": "Enable Continuous Delivery",
              "type": "boolean"
            },
            "mode": {
              "type": "string",
              "title": "Mode",
              "enum": ["branch", "release"],
              "default": "branch",
              "description": "Deploy based on branch builds or release creation"
            },
            "branches": {
              "default": [
                "main"
              ],
              "description": "Git branches to monitor for automatic deployment",
              "items": {
                "type": "string"
              },
              "title": "Branches",
              "type": "array"
            },
            "releases": {
              "type": "string",
              "title": "Releases (Semver)",
              "default": ".*",
              "description": "Semver regex pattern to match releases for automatic deployment (e.g., v\\d+\\.\\d+\\.\\d+)"
            }
          },
          "required": [
            "enabled"
          ],
          "title": "Continuous Delivery",
          "type": "object"
        },
        "cpu_millicores": {
          "anyOf": [
            {
              "const": 50
            },
            {
              "const": 100
            },
            {
              "const": 200
            },
            {
              "const": 500
            },
            {
              "const": 750
            },
            {
              "const": 1000
            },
            {
              "const": 1500
            },
            {
              "const": 2000
            },
            {
              "maximum": 4000,
              "minimum": 100,
              "type": "number"
            }
          ],
          "default": 100,
          "description": "Amount of CPU to allocate (in millicores, 1000m = 1 CPU core)",
          "title": "CPU Millicores",
          "type": "integer"
        },
        "cron": {
          "anyOf": [
            {
              "const": "* * * * *",
              "title": "Every minute"
            },
            {
              "const": "*/5 * * * *",
              "title": "Every 5 minutes"
            },
            {
              "const": "*/15 * * * *",
              "title": "Every 15 minutes"
            },
            {
              "const": "0 * * * *",
              "title": "Every hour"
            },
            {
              "const": "0 */4 * * *",
              "title": "Every 4 hours"
            },
            {
              "const": "0 */12 * * *",
              "title": "Every 12 hours"
            },
            {
              "const": "0 0 * * *",
              "title": "Every day (midnight)"
            }
          ],
          "description": "Specify how often the task should run. You can select a predefined option or enter a standard cron expression for custom schedules.",
          "title": "Task Frequency",
          "type": "string"
        },
        "history_limit": {
          "default": 3,
          "description": "Number of past job runs to keep.",
          "type": "integer"
        },
        "ram_memory": {
          "default": 64,
          "description": "Amount of RAM memory to allocate to the container (in MB)",
          "oneOf": [
            {
              "const": 64,
              "title": "64 MB"
            },
            {
              "const": 128,
              "title": "128 MB"
            },
            {
              "const": 256,
              "title": "256 MB"
            },
            {
              "const": 512,
              "title": "512 MB"
            },
            {
              "const": 1024,
              "title": "1 GB"
            },
            {
              "const": 2048,
              "title": "2 GB"
            },
            {
              "const": 4096,
              "title": "4 GB"
            },
            {
              "const": 8192,
              "title": "8 GB"
            },
            {
              "const": 16384,
              "title": "16 GB"
            }
          ],
          "title": "RAM Memory",
          "type": "integer"
        },
        "retries": {
          "default": 6,
          "description": "Number of retry attempts allowed if the job fails.",
          "type": "integer"
        }
      },
      "required": [
        "ram_memory",
        "cpu_millicores",
        "cron",
        "concurrency_policy",
        "retries",
        "history_limit",
        "continuous_delivery"
      ],
      "type": "object",
      "uiSchema": {
        "elements": [
          {
            "label": "Task Frequency",
            "options": {
              "placeholder": "Pick a schedule or type cron"
            },
            "scope": "#/properties/cron",
            "type": "Control"
          },
          {
            "label": "RAM Memory",
            "scope": "#/properties/ram_memory",
            "type": "Control"
          },
          {
            "elements": [
              {
                "elements": [
                  {
                    "options": {
                      "labelSuffix": "millicores",
                      "placeholder": "Select or type the amount of millicores"
                    },
                    "scope": "#/properties/cpu_millicores",
                    "type": "Control"
                  }
                ],
                "label": "Processor",
                "type": "Category"
              },
              {
                "elements": [
                  {
                    "label": "Concurrency policy",
                    "scope": "#/properties/concurrency_policy",
                    "type": "Control"
                  },
                  {
                    "label": "Retries",
                    "scope": "#/properties/retries",
                    "type": "Control"
                  },
                  {
                    "label": "History",
                    "scope": "#/properties/history_limit",
                    "type": "Control"
                  }
                ],
                "label": "Execution",
                "type": "Category"
              },
              {
                "elements": [
                  {
                    "scope": "#/properties/continuous_delivery/properties/enabled",
                    "type": "Control"
                  },
                  {
                    "rule": {
                      "condition": {
                        "schema": {
                          "const": true
                        },
                        "scope": "#/properties/continuous_delivery/properties/enabled"
                      },
                      "effect": "SHOW"
                    },
                    "scope": "#/properties/continuous_delivery/properties/mode",
                    "type": "Control"
                  },
                  {
                    "rule": {
                      "condition": {
                        "type": "AND",
                        "conditions": [
                          {
                            "scope": "#/properties/continuous_delivery/properties/enabled",
                            "schema": {"const": true}
                          },
                          {
                            "scope": "#/properties/continuous_delivery/properties/mode",
                            "schema": {"const": "branch"}
                          }
                        ]
                      },
                      "effect": "SHOW"
                    },
                    "scope": "#/properties/continuous_delivery/properties/branches",
                    "type": "Control"
                  },
                  {
                    "rule": {
                      "condition": {
                        "type": "AND",
                        "conditions": [
                          {
                            "scope": "#/properties/continuous_delivery/properties/enabled",
                            "schema": {"const": true}
                          },
                          {
                            "scope": "#/properties/continuous_delivery/properties/mode",
                            "schema": {"const": "release"}
                          }
                        ]
                      },
                      "effect": "SHOW"
                    },
                    "scope": "#/properties/continuous_delivery/properties/releases",
                    "type": "Control"
                  }
                ],
                "label": "Continuous deployment",
                "type": "Category"
              }
            ],
            "options": {
              "collapsable": {
                "collapsed": true,
                "label": "ADVANCED"
              }
            },
            "type": "Categorization"
          }
        ],
        "type": "VerticalLayout"
      }
    },
    "values": {}
  },
  "dimensions": {},
  "name": "Scheduled task",
  "selectors": {
    "category": "Scope",
    "imported": false,
    "provider": "Agent",
    "sub_category": "Scheduled task"
  },
  "type": "scope",
  "use_default_actions": false,
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ]
}
