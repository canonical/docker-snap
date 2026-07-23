# Testflinger scripts

This directory contains the scripts used for Nvidia testing via Github actions and Testflinger.
The tests run on devices within Canonical's test farm.

Tested distros:

- `noble`
- `core22-latest`
- `core24-latest`

## Run on remote machine over SSH

The entry point for the tests is the `scripts/agent.sh` script.
This script can be run locally to do testing over SSH on a remote machine.
The SSH username `ubuntu` is used, and SSH key authentication is required.
One can use a Multipass VM as remote machine,
as long as your local user's ssh public key has been added to the VM's `authorized_keys` file.

A number of environment variables need to be exported for this script to run.
An example command look like this:

```bash
DEVICE_IP=192.168.86.86 DEVICE_USER=ubuntu SNAP_CHANNEL=latest/edge ./scripts/agent.sh
```

* `DEVICE_IP` - Network address of the device under test. Testflinger exports this variable in the agent's environment.
* `DEVICE_USER` - Username used to SSH to the device under test. This defaults to the value `ubuntu`.
* `SNAP_CHANNEL` - Snap Store channel from where the docker snap will be installed to perform the tests on.
* `SCRIPTS` - Directory where all the test scripts are located.

## Run on Testflinger

These tests can be submitted as a Testflinger job from your local computer.

The `nvidia-job.yaml` job definition contains variables that need to be replaced with actual values.
A convenience script `run.sh` is provided that makes a copy of the job, fills the variables,
and submits the job to Testflinger.
Export the required variables and then run the script, e.g:

```bash
JOB_QUEUE=docker-nvidia DISTRO=noble SNAP_CHANNEL=latest/edge ./run.sh
```

To create a copy of the template job with filled variables, without submitting it, set the `--dryrun` flag.
This allows manual modifications of the job before submitting it, 
like adding `reserve_data` for debugging a failed job.

## Run via Github Workflow

The Testflinger job is used in the [nvidia-test.yml](../nvidia-test.yml) Github Workflow.
This workflow can only be run manually.

The workflow takes a Docker snap build artifact generated via a previous
[smoke-test.yml](../smoke-test.yml) workflow run,
publishes it to the Snap Store under a branch, and then uses that branch to run the tests.

To run the Github workflow,
go to the [workflow page](https://github.com/canonical/docker-snap/actions/workflows/nvidia-test.yml) on Github,
open the `Run workflow` menu, and provide the necessary inputs.
The `Publish to Store` option should only be set if the artifact hasn't been uploaded to the Store.
