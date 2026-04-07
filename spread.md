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

To run the tests, just invoke spread:

```bash
image-garden.spread
```

Once you run the tests, _spread_ will instantiate several virtual machines, as specified in [spread.yaml](./spread.yaml).
On each of those, the [prepare.sh](./spread/scripts/prepare.sh) script will run and install the docker snap before launching any test.
By default, it looks for a `docker_*.snap` file in **the current directory** and installs it in `--dangerous` mode.

If multiple files match the `docker_*.snap` pattern, you have to specify which one to use:

```bash
SNAP_FILE=docker_29.3.1_amd64.snap image-garden.spread
```

To install docker from the **snap store** instead, set the snap channel:

```bash
SNAP_CHANNEL=latest/edge image-garden.spread
```

The system will download the virtual machine files and place them in the `.image-garden` directory. See [Cleanup](#cleanup) to know how to free disk space.

In order to run an **individual spread test**, please run the following command:

```bash
image-garden.spread spread/main/hello-world
```

### Keep test artifacts

To recover artifacts from VMs before they shut down, set the `artifacts` argument:

```bash
image-garden.spread -artifacts artifacts
```

### Ephimeral storage

By default, image garden VMs have ephimeral storage. To start VMs with permanent storage, set `QEMU_SNAPSHOT_OPTION=""`
as described in [Persistent Storage Mode](https://gitlab.com/zygoon/image-garden/-/blob/main/README.md?ref_type=heads#persistent-storage-mode).

## Cleanup

Image Garden will use the `.image-garden` directory to store the virtual machine images and drives. You can get rid of those files by manually deleting them or by using:

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

To enable language support in VS Code, ensure you have a YAML extension installed and add the following configuration to the `.vscode/settings.json` file:

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
