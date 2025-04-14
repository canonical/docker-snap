# Testflinger scripts

This directory contains the scripts used for Nvidia testing via Github actions and Testflinger.
The tests run on devices within Canonical's test farm.

## Run locally
Running the tests locally is only possible if your machine has access to the Testflinger server.

Tested distros:
- `noble`
- `core22-latest`
- `core24-latest`

Set the input variables and execute the script from the same directory:
```bash
JOB_QUEUE=docker-nvidia SNAP_CHANNEL=latest/edge DISTRO=noble ./run.sh
```
The above replaces the inputs in the scripts and submits the Testflinger job.

Set the `--dryrun` flag to generate the scripts without submitting the job.
This is useful if you plan to make manual modifications to the job.

## Run via Github Workflow

The Testflinger job is used in the [nvidia-test.yml](../nvidia-test.yml) Github Workflow.
This workflow can only be run manually.

The workflow takes a Docker snap build artifact generated via a previous [smoke-test.yml](../smoke-test.yml) workflow run, publishes it to the Snap Store under a branch, and then uses that branch to run the tests.

To run the Github workflow, go to the [workflow page](https://github.com/canonical/docker-snap/actions/workflows/nvidia-test.yml) on Github, open the `Run workflow` menu, and provide the necessary inputs.
The `Publish to Store` option should only be set if the artifact hasn't been uploaded to the Store.
