#!/bin/bash -e

temp_job=nvidia-job.yaml.tmp
temp_setup=setup.sh.tmp

# Inputs
echo "Job queue: $JOB_QUEUE"
echo "Distro: $DISTRO"
echo "Snap channel: $SNAP_CHANNEL"

# Replace env vars with inputs
envsubst '$JOB_QUEUE $DISTRO' < nvidia-job.yaml > $temp_job
envsubst '$SNAP_CHANNEL' < scripts/setup.sh > scripts/$temp_setup

# Switch to use the modified script
sed -i "s|setup.sh|$temp_setup|" $temp_job

if [[ $1 == "--dryrun" ]]; then
  echo "Dry-run complete"
  echo "Submit the job with:"
  echo "testflinger submit --poll $temp_job"
  exit 0
fi

# Submit the modified job
testflinger submit --poll $temp_job
