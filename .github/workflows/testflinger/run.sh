#!/bin/bash -e

temp_job=nvidia-job.yaml.tmp
temp_setup=setup.sh.tmp

# Inputs
echo "Job queue: $JOB_QUEUE"
echo "Distro: $DISTRO"
echo "Snap channel: $SNAP_CHANNEL"
echo "Lib layout: ${LIB_LAYOUT:-multiarch}"

# Replace env vars with inputs
envsubst '$JOB_QUEUE $DISTRO $SNAP_CHANNEL $LIB_LAYOUT' < nvidia-job.yaml > $temp_job

if [[ $1 == "--dryrun" ]]; then
  echo "Dry-run complete"
  echo "Submit the job with:"
  echo "testflinger submit --poll $temp_job"
  exit 0
fi

# Submit the modified job
testflinger submit --poll $temp_job
