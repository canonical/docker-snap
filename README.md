[![docker](https://snapcraft.io/docker/badge.svg)](https://snapcraft.io/docker)

# Docker Snap

This repository contains the source for the `docker` snap package.  The package provides a distribution of Docker Engine along with the Nvidia toolkit for Ubuntu Core and other snap-compatible systems.  The Docker Engine is built from an upstream release tag with some patches to fit the snap format and is available on `armhf`, `arm64`, `amd64`, `i386`, `ppc64el`, `riscv64` and `s390x` architectures.  The rest of this page describes installation, usage, and development.

> [!NOTE]
> [Docker's official documentation](https://docs.docker.com) does not discuss the `docker` snap package. For questions regarding the snap usage, refer to the [discussions](https://github.com/canonical/docker-snap/discussions).

## Installation

To install the latest stable release of Docker CE using `snap`:

```shell
sudo snap install docker
```

This snap is confined, which means that it can access a limited set of resources on the system.
Additional access is granted via [snap interfaces](https://snapcraft.io/docs/interfaces).

Upon installation using the above command, the snap connects automatically to the following system interface slots:
- [docker-support](https://snapcraft.io/docs/docker-support-interface)
- [firewall-control](https://snapcraft.io/docs/firewall-control-interface)
- [home](https://snapcraft.io/docs/home-interface) - only on classic/traditional distributions
- [network](https://snapcraft.io/docs/network-interface)
- [network-bind](https://snapcraft.io/docs/network-bind-interface)
- [network-control](https://snapcraft.io/docs/network-control-interface)
- [opengl](https://snapcraft.io/docs/opengl-interface)

If you are using Ubuntu Core 16, connect the `docker:home` plug as it's not auto-connected by default:

```shell
sudo snap connect docker:home
```

The `docker-compose` [alias](https://snapcraft.io/docs/commands-and-aliases) was set automatically for Compose V1 and remains for backwards-compatiblity.
The recommended command-line syntax since Compose V2 is `docker compose` as described [here](https://docs.docker.com/compose/releases/migrate/).

### Changing the data root directory

In the `docker` snap, the default location for the [data-root](https://docs.docker.com/engine/daemon/#daemon-data-directory) directory is `$SNAP_COMMON/var-lib-docker`, which maps to `/var/snap/docker/common/var-lib-docker` based on the [snap data locations](https://snapcraft.io/docs/data-locations#heading--system).

> [!WARNING]
> By default, SnapD removes the snap's data locations and creates [snapshots](https://snapcraft.io/docs/snapshots) that serve as backup. 
> Changing the root directory to a different path results in loss of snapshot functionalities, leaving you responsible for the management of those files.  
  
To modify the default location, use [snap configuration options](https://snapcraft.io/docs/configuration-in-snaps):  
  
**Get the current value:**  
```shell
sudo snap get docker data-root
```  
  
**Set a new location:**  
```shell
sudo snap set docker data-root=<new-directory>
```
Make sure to use a location that the snap has access to, which is:
- Inside the `$HOME` directory;
- Within a snap-writable area, as described in the [data locations documentation](https://snapcraft.io/docs/data-locations).

Then restart the dockerd service:
```shell
sudo snap restart docker.dockerd
```

### Running Docker as normal user

By default, Docker is only accessible with root privileges (`sudo`). If you want to use docker as a regular user, you need to add your user to the `docker` group. This isn't possible on Ubuntu Core because it disallows the addition of users to system groups [[1](https://forum.snapcraft.io/t/adding-users-to-system-groups-on-ubuntu-core/20109), [2](https://github.com/snapcore/core20/issues/72)].

> [!WARNING]
> If you add your user to the `docker` group, it will have similar power as the `root` user. For details on how this impacts security in your system, see [Docker daemon attack surface](https://docs.docker.com/engine/security/#docker-daemon-attack-surface).

If you would like to run `docker` as a normal user:

* Create and join the `docker` group:

```shell
sudo addgroup --system docker
sudo adduser $USER docker
newgrp docker
```

* Disable and re-enable the `docker` snap if you added the group while Docker Engine was running:

```shell
sudo snap disable docker
sudo snap enable docker
```

## Usage

Docker should function normally, with the following caveats:

* To configure the `docker` daemon edit `/var/snap/docker/current/config/daemon.json`.

* All files that `docker` needs access to should live within your `$HOME` folder.

  * If you are using Ubuntu Core 16, you'll need to work within a subfolder of `$HOME` that is readable by root; see [#8](https://github.com/docker/docker-snap/issues/8).

* If you need `docker` to interact with removable media (external storage drives) for use in containers, volumes, images, or any other Docker-related operations, you must connect the [removable-media interface](https://snapcraft.io/docs/removable-media-interface) to the snap:  

  ```shell
  sudo snap connect docker:removable-media
  ```

* Additional certificates used by the Docker daemon to authenticate with registries need to be located in `/var/snap/docker/common/etc/certs.d` instead of `/etc/docker/certs.d`.

* Specifying the option `--security-opt="no-new-privileges=true"` with the `docker run` command (or the equivalent in docker-compose) will result in a failure of the container to start. This is due to an an underlying external constraint on AppArmor; see [LP#1908448](https://bugs.launchpad.net/snappy/+bug/1908448) for details.

### Examples

* [Setup a secure private registry](registry-example.md)
* [Create a snap that uses this Docker Engine](https://ubuntu.com/core/docs/docker-deploy)

## NVIDIA support

The Docker snap does not include the NVIDIA GPU and CUDA drivers.
The snap includes various parts of the [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit) and [NVIDIA container runtime library](https://github.com/NVIDIA/libnvidia-container).

If the system is found to have an NVIDIA graphics card available, and the host has the required drivers installed, the NVIDIA Container Toolkit will be set up and configured to enable use of the local GPU from docker. This allows you, for instance, to use CUDA from a container.

> [!NOTE] 
> The containerized workload must be ABI-compatible with the graphics user-space libraries on the host. The Docker snap does not add any abstraction to make the container environment host-agnostic.

To enable proper use of the GPU within docker, the `nvidia` runtime must be used. By default, this runtime will be configured to use [CDI](https://github.com/cncf-tags/container-device-interface) mode, and the appropriate NVIDIA CDI config will be automatically created for the system. It is only required to specify the `nvidia` runtime when running a container.

### Ubuntu Core

On Ubuntu Core, the graphics dependencies must be provided to the Docker snap via another snap. 
This is done using one of the supported content interfaces. 

> [!TIP]
> A [content interface](https://snapcraft.io/docs/content-interface) allows sharing data between snaps.
> For NVIDIA support, the graphics user-space are shared from a *provider snap* to the Docker snap.

The provider and environment setup differs depending on the Ubuntu Core release. Refer below for specific instructions.

> [!NOTE]
> It is possible to connect multiple graphic providers to the Docker snap. In such a case, the Docker snap will only utilize the content provided by the `gpu-2404` content provider. Do not connect more than one `gpu-2404` provider at the same time as the content may partially override each other.

#### Ubuntu Core 24

The required NVIDIA kernel objects and user-space libraries are available as optional components in the [pc-kernel](https://snapcraft.io/pc-kernel) snap (24/stable channel). These libraries can be provided to the Docker snap via the [mesa-2404](https://snapcraft.io/mesa-2404) snap.

```shell
# Install kernel components
sudo snap install pc-kernel+nvidia-550-erd-ko
sudo snap install pc-kernel+nvidia-550-erd-user

# Install the content provider snap
sudo snap install mesa-2404
```

Once installed, Docker snap's gpu-2404 plug automatically connects to mesa-2404:
```console
$ snap connections docker 
Interface          Plug                     Slot                                 Notes
...
content[gpu-2404]  docker:gpu-2404          mesa-2404:gpu-2404                   -
...
```

#### Ubuntu Core 22

> [!CAUTION]
> The support for using `nvidia` runtime on Ubuntu Core 22 has been deprecated. It will be fully removed in the next Docker snap base upgrade to core26 or later.

The required NVIDIA libraries are available in the [nvidia-core22](https://snapcraft.io/nvidia-core22) content provider snap. 

Once installed, the Docker snap's graphics-core22 plug auto connects to nvidia-core22's corresponding slot:
```console
$ snap connections docker
Interface                 Plug                     Slot                                 Notes
...
content[graphics-core22]  docker:graphics-core22   nvidia-core22:graphics-core22        -
...
```

> [!NOTE]
> The [mesa-core22](https://snapcraft.io/mesa-core22) provider snap is not supported.


In addition to the content provider, install the [nvidia-assemble](https://github.com/canonical/nvidia-assemble) snap to assemble, load and setup NVIDIA graphics drivers from a compatible kernel snap, such as the pc-kernel snap (22/stable channel). 

### Ubuntu Server / Desktop

The required NVIDIA libraries are available in the NVIDIA Container Toolkit packages.

Instruction on how to install them can be found [here](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

### Custom NVIDIA runtime config

If you want to make some adjustments to the automatically generated runtime config, you can use the `nvidia-support.runtime.config-override` snap config to completely replace it.

```shell
snap set docker nvidia-support.runtime.config-override="$(cat cutom-nvidia-config.toml)"
```

### CDI device naming strategy

By default, the `device-name-strategy` for the CDI config will use `index`.  Optionally, you can specify an alternative from the currently supported:
* `index`
* `uuid`
* `type-index`

```shell
snap set docker nvidia-support.cdi.device-name-strategy=uuid
```

### Disable NVIDIA support

Setting up the NVIDIA support should be automatic when the hardware is present, but you may wish to specifically disable it so that setup is not even attempted.  You can do so via the following snap config:
```shell
snap set docker nvidia-support.disabled=true
```

### Nvidia usage examples

Generic example usage would look something like:

```shell
docker run --rm --runtime nvidia --gpus all {cuda-container-image-name}
```

or

```shell
docker run --rm --runtime nvidia --env NVIDIA_VISIBLE_DEVICES=all {cuda-container-image-name}
```

If your container image already has appropriate environment variables set, you may be able to just specify the `nvidia` runtime with no additional args required.

You may run `nvidia-smi` to validate the environment set up from a temporary container:
```
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

## Development

Developing the `docker` snap package is typically performed on a "classic" Ubuntu distribution (Ubuntu Server / Desktop).

Install the snap tooling:

```shell
sudo snap install snapcraft --classic
```

Checkout and enter this repository:

```shell
git clone https://github.com/canonical/docker-snap
cd docker-snap
```

Build the snap:

```shell
snapcraft -v
```

Install the newly-created snap package:

```shell
sudo snap install --dangerous ./docker_[VER]_[ARCH].snap
```

Manually connect the relevant plugs and slots which are not auto-connected:

```shell
sudo snap connect docker:privileged :docker-support
sudo snap connect docker:support :docker-support
sudo snap connect docker:firewall-control :firewall-control
sudo snap connect docker:network-control :network-control
sudo snap connect docker:docker-cli docker:docker-daemon
sudo snap connect docker:home

sudo snap disable docker
sudo snap enable docker
```

## Testing

The snap has various tests in place:
- [Automated smoke testing via a Github workflow](.github/workflows/smoke-test.yml)
- [Nvidia testing via Testflinger](.github/workflows/testflinger/README.md)
- [Spread tests](spread.md)
- [Checkbox tests](#checkbox)

### Checkbox
The Docker snap can be tested via [Checkbox](https://canonical-checkbox.readthedocs-hosted.com/en/stable/index.html).
The checkbox project includes various Docker tests as part of a [dedicated provider](https://github.com/canonical/checkbox/tree/main/providers/docker).

To run these tests against the Docker snap, install a revision of the snap:
```shell
sudo snap install docker --edge  
```

Then install a checkbox runtime and frontend:
```shell
sudo snap install checkbox22
sudo snap install checkbox --channel 22.04/stable --classic
```

Finally, run `checkbox.checkbox-cli`, press `f` and filter Docker plans:
```
 Select test plan
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│    ( ) Automated tests of Docker functionality for EdgeX Foundry             │
│    (X) Fully automated QA tests for Docker containers                        │
│    ( ) Manual QA tests for Docker containers                                 │
│    ( ) QA tests for Docker containers                                        │
│                                                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
 Press <Enter> to continue                                             (H) Help
```
Select `Fully automated QA tests for Docker containers` and continue to run the tests.
