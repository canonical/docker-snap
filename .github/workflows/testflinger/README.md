# Testflinger scripts

This directory contains the scripts used for Nvidia testing via Github actions and Testflinger.
The tests run on devices within Canonical's test farm.

## Run locally
Running the tests locally is only possible if your machine has access to the Testflinger server.

Export the needed variables, for example:
```bash
export JOB_QUEUE=docker-nvidia SNAP_CHANNEL=latest/edge DISTRO=noble
```
Tested distros:
- `noble`
- `core22-latest`

Then, modify the files:
```bash
envsubst '$JOB_QUEUE $DISTRO' < nvidia-job.yaml > temp-job.yaml

envsubst '$SNAP_CHANNEL' < scripts/setup.sh > scripts/temp-setup.sh

sed -i "s|setup.sh|temp-setup.sh|" temp-job.yaml

sed -i "s|.github/workflows/testflinger/||" temp-job.yaml
```

Finally, submit the job:
```bash
testflinger submit --poll temp-job.yaml
```
