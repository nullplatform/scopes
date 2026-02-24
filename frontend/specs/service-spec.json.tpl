{
  "assignable_to": "any",
  "attributes": {
    "schema": {
      "properties": {
        "asset_type": {
          "default": "bundle",
          "export": false,
          "type": "string"
        }
      },
      "required": [],
      "uiSchema": {
        "elements": [],
        "type": "VerticalLayout"
      }
    },
    "values": {}
  },
  "dimensions": {},
  "name": "Static files",
  "scopes": {},
  "selectors": {
    "category": "Scope",
    "imported": false,
    "provider": "Agent",
    "sub_category": "Static files"
  },
  "type": "scope",
  "use_default_actions": false,
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ]
}