<h2 align="center">
    <a href="https://httpie.io" target="blank_">
        <img height="100" alt="nullplatform" src="https://nullplatform.com/favicon/android-chrome-192x192.png" />
    </a>
    <br>
    <br>
    Nullplatform "Any Technology" Template
    <br>
</h2>

This is a minimalistic sample on how you can create an application on arbitrary technology.
In particular, we're spinning up an image that contains an echo server.
You can check *Echo Server* documentation [here](https://ealenn.github.io/Echo-Server/).

## How do I run locally?
1. Install the latest beta version of the NP CLI:
   ```bash
   curl https://cli.nullplatform.com/install.sh | VERSION=beta sh
   ```
2. Create an api-key with developer, ops, secops and secret-reader roles.
3. Export the api-key as `NP_API_KEY`.
4. Execute the configure script:
   ```bash
   ./configure --nrn="$NRN" --scope=k8s
   ```
   The `configure` script will create all nullplatform's entities needed to enable the custom scope (service specification, action specifications, scope type, notification channel).
5. Run the nullplatfom agent locally with the `start_dev.sh` script.
6. Create a custom scope from the nullplatform UI. You should receive the notifications in your local agent. 

## How do I modify this template to build my own application?

1. Change the Dockerfile to run the application / binary that you are building.
2. Deploy your application in nullplatform.

## IDE support for workflow YAML.

### Jetbrains
1. Go to Preferences -> Languages & Frameworks -> Schemas and DTDs -> JSON Schema.
2. Create a new schema.
3. Select the workflow.schema.json (you can find it in the root of this repository).
4. Add file path pattern with value `**/workflows/*.yaml`.

### VS Code
1. Copy the workflow.schema.json to the root of your repository (you can find it in the root of this repository).
2. Create a `.vscode/settings.json` file with this content:
    ```json
    {
      "yaml.schemas": {
        "workflow.schema.json": "**/workflows/*.yaml"
      }
    }
    ```
3. Install the YAML extension by RedHat.