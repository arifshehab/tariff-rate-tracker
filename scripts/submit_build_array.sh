#!/bin/bash
#
# Submit the node-parallel array build: one Slurm array task per revision,
# running concurrently across nodes. Replaces the serial 41-revision loop.
#
# Steps:
#   1. Generate the ordered revision list (via a short srun) into $REVLIST.
#   2. Submit the array, sized to the revision count, one task per revision.
#   3. Submit the gather step (assembly + downstream) with an afterok dependency
#      on the whole array, so it runs once every revision succeeds.
#
# Run from the repo root on the login node:
#   bash scripts/submit_build_array.sh
#   NO_GATHER=1 bash scripts/submit_build_array.sh   # array only, no gather
#   GATHER_ARGS="--unweighted" bash scripts/submit_build_array.sh
#
# WARNING: array tasks write snapshots into data/timeseries/. Do NOT run while a
# serial build is writing there, and freeze any golden you care about first
# (scripts/capture_parity_golden.R).

set -euo pipefail
cd /nfs/roberts/project/pi_nrs36/jar335/Repositories/tariff-rate-tracker

# Scenario support: SCENARIO=<name> builds a counterfactual into an ISOLATED
# data/timeseries/<name>/ with its own revlist/timeline — never the baseline. The
# list-revs srun, every array task, and the gather all load the overlay because
# TARIFF_SCENARIO is exported (load_policy_params reads it). Unset / actual / baseline
# => the normal baseline build, unchanged.
#   SCENARIO=forced_labor bash scripts/submit_build_array.sh
SCENARIO="${SCENARIO:-}"
if [ -n "$SCENARIO" ] && [ "$SCENARIO" != "actual" ] && [ "$SCENARIO" != "baseline" ]; then
  export TARIFF_SCENARIO="$SCENARIO"
  export TARIFF_TS_DIR="${TARIFF_TS_DIR:-data/timeseries/$SCENARIO}"
  REVLIST="${REVLIST:-output/build_array_revisions_${SCENARIO}.txt}"
  REV_TIMELINE="${REV_TIMELINE:-output/build_array_timeline_${SCENARIO}.rds}"
  if [ "$(readlink -m "$TARIFF_TS_DIR")" = "$(readlink -m data/timeseries)" ]; then
    echo "REFUSING: scenario '$SCENARIO' TARIFF_TS_DIR resolves to baseline data/timeseries" >&2
    exit 1
  fi
  echo "*** SCENARIO build: $SCENARIO  ->  $TARIFF_TS_DIR  (timeline $REV_TIMELINE) ***"
else
  export TARIFF_SCENARIO=""
fi

REVLIST="${REVLIST:-output/build_array_revisions.txt}"
REV_TIMELINE="${REV_TIMELINE:-output/build_array_timeline.rds}"
export REVLIST REV_TIMELINE TARIFF_SCENARIO
[ -n "${TARIFF_TS_DIR:-}" ] && export TARIFF_TS_DIR
mkdir -p output

echo "--- Generating revision list (srun) ---"
srun --job-name=list-revs --partition=devel --time=00:10:00 --mem=8G --cpus-per-task=1 \
  bash -lc 'module load R/4.4.2-gfbf-2024a 2>/dev/null; Rscript scripts/list_revisions.R'

N=$(grep -c . "$REVLIST")
if [ "$N" -lt 1 ]; then
  echo "ERROR: no revisions found in $REVLIST" >&2
  exit 1
fi
echo "Revisions to build: $N"
echo "  first: $(head -1 "$REVLIST")  last: $(tail -1 "$REVLIST")"

BUILD_REVISION_ARGS="${BUILD_REVISION_ARGS:-}"
if [[ " ${GATHER_ARGS:-} " == *" --unweighted "* && " $BUILD_REVISION_ARGS " != *" --unweighted "* ]]; then
  BUILD_REVISION_ARGS="${BUILD_REVISION_ARGS:+$BUILD_REVISION_ARGS }--unweighted"
fi
echo "  build revision args: ${BUILD_REVISION_ARGS:-<none>}"

echo "--- Submitting array build (0-$((N - 1))) ---"
ARRAY_JOB=$(REVLIST="$REVLIST" REV_TIMELINE="$REV_TIMELINE" BUILD_REVISION_ARGS="$BUILD_REVISION_ARGS" \
  TARIFF_SCENARIO="${TARIFF_SCENARIO:-}" TARIFF_TS_DIR="${TARIFF_TS_DIR:-}" TARIFF_OUTPUT_DIR="${TARIFF_OUTPUT_DIR:-}" \
  sbatch --parsable --array=0-$((N - 1)) scripts/build_array_task.sh)
echo "Array job: $ARRAY_JOB"

if [ -n "${NO_GATHER:-}" ]; then
  echo
  echo "Array only (NO_GATHER set). Watch: squeue -j $ARRAY_JOB"
  echo "Then gather manually: sbatch scripts/submit_build_gather.sh"
  exit 0
fi

echo "--- Submitting gather (afterok:$ARRAY_JOB) ---"
GATHER_JOB=$(GATHER_ARGS="${GATHER_ARGS:-}" \
  TARIFF_SCENARIO="${TARIFF_SCENARIO:-}" TARIFF_TS_DIR="${TARIFF_TS_DIR:-}" TARIFF_OUTPUT_DIR="${TARIFF_OUTPUT_DIR:-}" REV_TIMELINE="$REV_TIMELINE" \
  sbatch --parsable --dependency=afterok:"$ARRAY_JOB" scripts/submit_build_gather.sh)
echo "Gather job: $GATHER_JOB (runs after the array fully succeeds)"
echo
echo "Watch:    squeue -j $ARRAY_JOB,$GATHER_JOB"
echo "Validate: Rscript scripts/run_parity_check.R --golden <golden-dir>"
