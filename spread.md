# Spread tests

This project uses [image-garden](https://gitlab.com/zygoon/image-garden) and [spread](https://github.com/snapcore/spread) to run full-system tests using QEMU virtual machines.

## Getting started

To get started, make sure that **image-garden** is installed on your system:

```bash
sudo snap install image-garden
sudo snap install image-garden+qemu-aarch64 # for arm64 emulation
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

  This runs the tests for both amd64 and arm64 architectures.
  For testing a single architecture, download the snap and use the local snap file method.
  To download the snap on a different architecture, e.g. arm64 on amd64, run: `UBUNTU_STORE_ARCH=arm64 snap download docker`.

- To test a local snap file, specify the `SNAP_FILE_AMD64` and/or `SNAP_FILE_ARM64` variables:

  ```bash
  SNAP_FILE_AMD64=docker_29.3.1_amd64.snap \
    SNAP_FILE_ARM64=docker_29.3.1_arm64.snap \
    image-garden.spread
  ```

The system will download the virtual machine files and place them in the `.image-garden` directory. See [Cleanup](#cleanup) to know how to free disk space.

### Running individual tests

To save time you can select a subset of systems and tests to run.

- To run tests on **only one system**, e.g. `ubuntu-cloud-26.04.amd64` or `ubuntu-cloud-24.04.arm64`, use:

  ```bash
  image-garden.spread ubuntu-cloud-24.04.amd64:
  ```

- To run tests on only **one system architecture**, e.g. `arm64`, use the `...` wildcard:

  ```bash
  image-garden.spread garden:...arm64:
  ```

- To run an **individual spread test**, e.g. `hello-world`, on all system, use:

  ```bash
  image-garden.spread spread/main/hello-world
  ```

- To run only **one test** on only **one system**, combine the two:

  ```bash
  image-garden.spread ubuntu-cloud-24.04.amd64:spread/main/hello-world
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
