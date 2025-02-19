[![docker](https://snapcraft.io/docker/badge.svg)](https://snapcraft.io/docker)

# Docker Snap

This repository contains the source for the `docker` snap package.  The package provides a distribution of Docker Engine along with the Nvidia toolkit for Ubuntu Core and other snap-compatible systems.  The Docker Engine is built from an upstream release tag with some patches to fit the snap format and is available on `armhf`, `arm64`, `amd64`, `i386`, and `ppc64el` architectures.  The rest of this page describes installation, usage, and development.

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

> [!IMPORTANT]  
> In the `docker` snap, the default location for the [data-root](https://docs.docker.com/engine/daemon/#daemon-data-directory) directory is `$SNAP_COMMON/var-lib-docker`, which maps to `/var/snap/docker/common/var-lib-docker` based on the [snap data locations](https://snapcraft.io/docs/data-locations#heading--system).  
>  
> You may want to change this because if the snap is removed, all Docker-related data (images, containers, volumes) will be deleted.  
>  
> To modify the default location, use [snap configuration options](https://snapcraft.io/docs/configuration-in-snaps):  
>  
> **Get the current value:**  
> ```shell
> sudo snap get docker data-dir
> ```  
>  
> **Set a new location:**  
> ```shell
> sudo snap set docker data-dir=<new-directory>
> ```
> Make sure to use a location that the snap has access, which is:
> - Inside the $HOME directory;
>
> Then restart the dockerd service:
> ```shell
> sudo snap restart docker.dockerd
> ```

* All files that `docker` needs access to should live within your `$HOME` folder.

  * If you are using Ubuntu Core 16, you'll need to work within a subfolder of `$HOME` that is readable by root; see [#8](https://github.com/docker/docker-snap/issues/8).

* Additional certificates used by the Docker daemon to authenticate with registries need to be located in `/var/snap/docker/common/etc/certs.d` instead of `/etc/docker/certs.d`.

* Specifying the option `--security-opt="no-new-privileges=true"` with the `docker run` command (or the equivalent in docker-compose) will result in a failure of the container to start. This is due to an an underlying external constraint on AppArmor; see [LP#1908448](https://bugs.launchpad.net/snappy/+bug/1908448) for details.

### Examples

* [Setup a secure private registry](registry-example.md)
* [Create a snap that uses this Docker Engine](https://ubuntu.com/core/docs/docker-deploy)

## NVIDIA support

If the system is found to have an nvidia graphics card available, and the host has the required nvidia libraries installed, the nvidia container toolkit will be setup and configured to enable use of the local GPU from docker.  This can be used to enable use of CUDA from a docker container, for instance.

To enable proper use of the GPU within docker, the nvidia runtime must be used.  By default, the nvidia runtime will be configured to use [CDI](https://github.com/cncf-tags/container-device-interface) mode, and a the appropriate nvidia CDI config will be automatically created for the system.  You just need to specify the nvidia runtime when running a container.

### Ubuntu Core 22

The required nvidia libraries are available in the nvidia-core22 snap.

This requires connection of the graphics-core22 content interface provided by the nvidia-core22 snap, which should be automatically connected once installed.

### Ubuntu Server / Desktop

The required nvidia libraries are available in the nvidia container toolkit packages.

Instruction on how to install them can be found ([here](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html))

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

Setting up the nvidia support should be automatic the hardware is present, but you may wish to specifically disable it so that setup is not even attempted.  You can do so via the following snap config:
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

If your container image already has appropriate environment variables set, may be able to just specify the nvidia runtime with no additional args required.

Please refer to [this guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html) for mode detail regarding environment variables that can be used.

*NOTE*: library path and discovery is automatically handled, but binary paths are not, so if you wish to test using something like the `nvidia-smi` binary passed into the container from the host, you could either specify the full path or set the PATH environment variable.

e.g.

```
docker run --rm --runtime=nvidia --gpus all --env PATH="${PATH}:/var/lib/snapd/hostfs/usr/bin" ubuntu nvidia-smi
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
