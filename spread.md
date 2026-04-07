# Spread tests

This project uses [image-garden](https://gitlab.com/zygoon/image-garden) and [spread](https://github.com/snapcore/spread) to run full-system tests using QEMU virtual machines.

## Getting started

To get started, make sure that **image-garden** is installed on your system:

```bash
sudo snap install image-garden
```

The snap release of image-garden also includes its dependencies, such as `spread` and `qemu`.

Optionally, you can create an **alias** so `spread` can be called directly:

```bash
sudo snap alias image-garden.spread spread
```

For more info about spread and image garden, see [Image Garden, Spread integration tests as GitHub Action](https://github.com/marketplace/actions/run-tests-with-image-garden-and-spread).

## Running tests

Once you run the tests, _spread_ will instantiate several virtual machines, as specified in [spread.yaml](./spread.yaml).
On each of those, the [prepare.sh](./spread/scripts/prepare.sh) script will run and install the docker snap before launching any test.

Before running any test, you have to choose which docker snap to test

- To test a version from the **Snap Store**, set the snap channel:

  ```bash
  SNAP_CHANNEL=latest/edge image-garden.spread
  ```

- To test a local snap file, specify the `SNAP_FILE` variable:

  ```bash
  SNAP_FILE=docker_29.3.1_amd64.snap image-garden.spread
  ```

The system will download the virtual machine files and place them in the `.image-garden` directory. See [Cleanup](#cleanup) to know how to free disk space.

### Running individual tests

To save time you can select a subset of systems and tests to run.

- To run tests on **only one system**, e.g. `ubuntu-cloud-24.04`, use:

  ```bash
  image-garden.spread ubuntu-cloud-24.04:
  ```

- To run an **individual spread test** on all system, use:

  ```bash
  image-garden.spread spread/main/hello-world
  ```

- To run only **one test** on only **one system**, combine the two:

  ```bash
  image-garden.spread ubuntu-cloud-24.04:spread/main/hello-world
  ```

### Keep test artifacts

To recover artifacts from VMs before they shut down, set the `artifacts` argument:

```bash
image-garden.spread -artifacts artifacts
```

### Ephemeral storage

By default, image garden VMs have ephimeral storage. To start VMs with permanent storage, set `QEMU_SNAPSHOT_OPTION=""`
as described in [Persistent Storage Mode](https://gitlab.com/zygoon/image-garden/-/blob/main/README.md?ref_type=heads#persistent-storage-mode).

## Cleanup

Image Garden will use the `.image-garden` directory to store virtual machine images and drives. You can get rid of those files by manually deleting them or by using:

- **Clean**: to remove all generated images, logs, and support files from the current directory without removing downloaded base images from the cache

    ```bash
    image-garden make clean
    ```

- **Distclean**: like `clean`, but also removes downloaded base images from the cache directory. Only use this if you need to reclaim disk space.

    ```bash
    image-garden make distclean
    ```

## Developing

Spread uses YAML files to define its architecture and individual tasks. You can integrate schemas such as [lengau's spread schemas](https://github.com/lengau/spread-schema) into your IDE to enable helpful features like auto-completion, validation, and documentation tooltips.
To enable language support in VS Code, ensure you have a [YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml) installed and add the following configuration to the `.vscode/settings.json` file:

```json
{
  "yaml.schemas": {
    "https://raw.githubusercontent.com/lengau/spread-schema/main/schema/spread.json": "spread.yaml",
    "https://raw.githubusercontent.com/lengau/spread-schema/main/schema/task.json": "spread/**/task.yaml"
  },
  "yaml.schemaStore.enable": false,
  "yaml.validate": true,
  "yaml.completion": true,
  "yaml.format.enable": true
}
```
