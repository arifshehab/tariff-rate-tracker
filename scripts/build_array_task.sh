#!/bin/bash
#
# Slurm ARRAY task: build one revision's snapshot. One array index -> one
# revision (line index+1 of $REVLIST). Tasks are independent and run
# concurrently across nodes, each with its own memory allocation — this is the
# parallelism that replaces the serial 41-revision loop.
#
# Submitted by scripts/submit_build_array.sh (which sizes --array and exports
# REVLIST). Not meant to be sbatch'd directly.
#
# Per-task sizing: the heaviest 2026 revision peaks ~40 GB; 64 GB gives headroom
# and lets Slurm pack a few tasks per 192 GB node or spread across nodes.

#SBATCH --job-name=tariff-rev
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --output=/home/%u/slurm-logs/tariff-rev-%A_%a.out
#SBATCH --error=/home/%u/slurm-logs/tariff-rev-%A_%a.err
#SBATCH --chdir=/nfs/roberts/project/pi_nrs36/jar335/Repositories/tariff-rate-tracker

set -euo pipefail
mkdir -p ~/slurm-logs output/logs

export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

if [ -f /etc/profile.d/z01_lmodinit.sh ]; then
  source /etc/profile.d/z01_lmodinit.sh
elif [ -f /etc/profile.d/lmod.sh ]; then
  source /etc/profile.d/lmod.sh
fi
module purge
module load R/4.4.2-gfbf-2024a

REVLIST="${REVLIST:-output/build_array_revisions.txt}"
if [ ! -f "$REVLIST" ]; then
  echo "ERROR: revision list not found: $REVLIST" >&2
  exit 1
fi

# Array index is 0-based; revision list lines are 1-based.
REV=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$REVLIST")
if [ -z "${REV:-}" ]; then
  echo "No revision for array task ${SLURM_ARRAY_TASK_ID} (list has $(grep -c . "$REVLIST") entries) — nothing to do."
  exit 0
fi

echo "=========================================================="
echo "Array task ${SLURM_ARRAY_TASK_ID} -> revision ${REV} on $(hostname)"
echo "Start: $(date -Iseconds) | Mem: ${SLURM_MEM_PER_NODE:-?} MB"
echo "=========================================================="

Rscript scripts/build_revision.R "$REV" ${USE_HTS_DATES:+--use-hts-dates}
RC=$?

echo "Task ${SLURM_ARRAY_TASK_ID} (${REV}) exit: $RC at $(date -Iseconds)"
exit $RC
