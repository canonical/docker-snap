# Spread tests

We rely on [spread](https://github.com/snapcore/spread) to run full-system test on Ubuntu Core 16. We also provide a utility script ([run-spread-test.sh](./run-spread-tests.sh)) to launch the spread test. It will

1. Fetch primary snaps( kernel, core, gadget) and build custom Ubuntu Core image with them
2. Boot the image in qemu emulator
3. Deploy test suits in emulation environment
4. Execute full-system testing

Firstly, install ubuntu-image tool since we need to create a custom Ubuntu Core image during test preparation.

```shell
sudo snap install --beta --classic ubuntu-image
```

Secondly, install qemu-kvm package since we use it as the backend to run the spread test.

```shell
sudo apt install qemu-kvm
```

Meanwhile, you need a classic-mode supported spread binary to launch kvm from its context. You can either build spread from this [branch](https://github.com/rmescandon/spread/tree/snap-as-classic) or download the spread snap package [here](http://people.canonical.com/~gary-wzl77/spread_2017.05.24_amd64.snap).

```shell
sudo snap install --classic --dangerous spread_2017.05.24_amd64.snap
```

You may build the docker snap locally in advance and then execute the spread tests with the following commands:

```shell
snapcraft
./run-spread-tests.sh
```

When doing a local build, you can also specify --test-from-channel to fetch the snap from the specific channel of the store. The snap from `candidate` channel is used by default as test target if `--channel` option is not specified.

```shell
./run-spread-tests.sh --test-from-channel --channel=stable
```

In order to run an individual spread test, please run the following command:

```shell
spread spread/main/installation
```

This will run the test case under spread/main/installation folder.
You can specify the `SNAP_CHANNEL` environment variable to install a snap from a specific channel for the testing as well.

```shell
SNAP_CHANNEL=candidate spread spread/main/update_policy
```
