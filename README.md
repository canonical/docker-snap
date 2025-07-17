[![docker](https://snapcraft.io/docker/badge.svg)](https://snapcraft.io/docker)

# Docker Snap

This repository contains the source for the `docker` snap package.  The package provides a distribution of Docker Engine for Ubuntu Core and other snap-compatible systems.  The Docker Engine is built from an upstream release tag with some patches to fit the snap format and is available on `armhf`, `arm64`, `amd64`, `i386`, `ppc64el`, `riscv64` and `s390x` architectures.  The rest of this page describes installation, usage, and development.

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

- Create and join the `docker` group:

```shell
sudo addgroup --system docker
sudo adduser $USER docker
newgrp docker
```

- Disable and re-enable the `docker` snap if you added the group while Docker Engine was running:

```shell
sudo snap disable docker
sudo snap enable docker
```

## Usage

Docker should function normally, with the following caveats:

- All files that `docker` needs access to should live within your `$HOME` folder.

  - If you are using Ubuntu Core 16, you'll need to work within a subfolder of `$HOME` that is readable by root; see [#8](https://github.com/docker/docker-snap/issues/8).

- If you need `docker` to interact with removable media (external storage drives) for use in containers, volumes, images, or any other Docker-related operations, you must connect the [removable-media interface](https://snapcraft.io/docs/removable-media-interface) to the snap:  

  ```shell
  sudo snap connect docker:removable-media
  ```

- Additional certificates used by the Docker daemon to authenticate with registries need to be located in `/var/snap/docker/common/etc/certs.d` instead of `/etc/docker/certs.d`.

- Specifying the option `--security-opt="no-new-privileges=true"` with the `docker run` command (or the equivalent in docker-compose) will result in a failure of the container to start. This is due to an an underlying external constraint on AppArmor; see [LP#1908448](https://bugs.launchpad.net/snappy/+bug/1908448) for details.

### Examples

- [Setup a secure private registry](registry-example.md)
- [Create a snap that uses this Docker Engine](https://ubuntu.com/core/docs/docker-deploy)

## Development

Developing the `docker` snap package is typically performed on a "classic" Ubuntu distribution (Ubuntu Server / Desktop).

Install the snap tooling:

```shell
sudo snap install snapcraft --classic --channel=7.x/stable
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
