# Spread tests

We rely on [image-garden](https://gitlab.com/zygoon/image-garden) and [spread](https://github.com/snapcore/spread) to run full-system tests using QEMU virtual machines.

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

More info about spread and image garden, see: https://github.com/marketplace/actions/run-tests-with-image-garden-and-spread 

## Running tests

To run the tests, just invoke spread:

```bash
image-garden.spread
```

Once you run the tests, _spread_ will instantiate several virtual machines, as specified in [spread.yaml](./spread.yaml). 
On each of those, the [prepare.sh](./spread/scripts/prepare.sh) script will run and install the docker snap before launching any test.
By default, it looks for a `dockere_*.snap` file in **this directory** and installs it in `--dangerous` mode, to more quickly iterate
on locally-packed snaps. Alternatively, the script can install docker from the **snap store**, you just have to specify the store channel
to install docker from, by setting the `SNAP_CHANNEL` environment variable:

```bash
SNAP_CHANNEL=latest/edge image-garden.spread
```

The system will download the virtual machine files and place them in the `.image-garden` directory. See [Cleanup](#cleanup) to know how to free disk space.

In order to run an **individual spread test**, please run the following command:

```bash
image-garden.spread spread/main/hello-world
```

### Keep test artifacts

If any spread task need to save a file on disk, you can recover it before the virtual machine gets shut down, just specify the `artifacts` argument, pointing to a local path:

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
