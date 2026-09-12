# Spread tests

This project uses [image-garden](https://gitlab.com/zygoon/image-garden) and [spread](https://github.com/snapcore/spread) to run full-system tests using QEMU virtual machines.

## Getting started

To get started, make sure that **image-garden** is installed on your system:

```bash
sudo snap install image-garden
sudo snap install image-garden+qemu-aarch64 # for arm64 emulation
sudo snap install image-garden+qemu-riscv64 # for riscv64 emulation
sudo snap install image-garden+qemu-s390x   # for s390x emulation
sudo snap install image-garden+qemu-ppc64   # for ppc64el emulation
```

The base snap ships the x86_64 emulator; each other architecture lives in an optional component, needed only if you run that architecture's systems.

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

  This runs the tests on every system, each guest installing the snap for its own architecture from the store.
  For testing a single architecture, download the snap and use the local snap file method.
  To download the snap on a different architecture, e.g. arm64 on amd64, run: `UBUNTU_STORE_ARCH=arm64 snap download docker`.

- To test a local snap file, specify the `SNAP_FILE_<ARCH>` variable for each architecture you run (`AMD64`, `ARM64`, `RISCV64`, `S390X`, `PPC64EL`):

  ```bash
  SNAP_FILE_AMD64=docker_29.3.1_amd64.snap \
    SNAP_FILE_ARM64=docker_29.3.1_arm64.snap \
    SNAP_FILE_RISCV64=docker_29.3.1_riscv.snap \
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

## Running in CI

The [Spread Tests workflow](.github/workflows/spread-tests.yml) runs these tests on GitHub Actions, on manual dispatch only.
It expands the job filter into the systems it selects and fans them out into one runner per system (one QEMU guest each), with the provisioned VM images cached per system and keyed to the image-garden snap revision.

Dispatch inputs:

- `snap_channel`: the `docker` snap channel to install in the guests
- `spread_test_filter`: which jobs to run, see below
- `force_rebuild`: ignore cached VM images and provision from scratch
- `publish_boot_logs`: always upload guest boot logs as workflow artifacts (they are uploaded on failure regardless)
- `debug`: run spread with `-vv`
- `image_garden_channel`: the `image-garden` snap channel to use; the `ubuntu-*-26.10` systems need `latest/candidate` until image-garden v0.6.4 reaches stable

### Job filter

The filter is a chain of whitespace-separated regular expressions, applied as successive greps over the spread job list (`backend:system:suite/task` lines, as printed by `spread -list`).
Each term narrows the selection, a `!` prefix inverts a term, and `|` inside a term expresses alternatives.
An empty filter selects every job.
An Ubuntu Core release counts as part of its paired LTS series: `26.04` also selects `ubuntu-core-26`, `!26.04` also excludes it, while `26.10` leaves Core alone.
Examples:

- `amd64`: all amd64 systems
- `core`: only Ubuntu Core systems
- `core !22`: Ubuntu Core, except the 22 series
- `26.04`: the 26.04 cloud systems plus `ubuntu-core-26`
- `ppc64el|amd64`: two architectures
- `hello-world`: a single task, on every system
- `!26.04 cloud amd64 build`: the `build` task on non-26.04 cloud amd64 systems

The workflow fails if the filter selects nothing.

The filter expansion lives in [.github/scripts/spread-matrix](.github/scripts/spread-matrix/spread-matrix) and can be dry-run locally:

```bash
image-garden.spread -list | .github/scripts/spread-matrix/spread-matrix '!26.04 core'
```

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
