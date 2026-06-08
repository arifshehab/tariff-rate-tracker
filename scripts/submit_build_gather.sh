#!/bin/bash
#
# Gather step (single node): assemble the array-built snapshots into the
# timeseries + run downstream (daily / ETR / quality). Submitted by
# scripts/submit_build_array.sh with an afterok dependency on the array job, or
# standalone once all snapshots exist.
#
# Usage (standalone): sbatch scripts/submit_build_gather.sh
#   GATHER_ARGS="--unweighted" sbatch scripts/submit_build_gather.sh
#
# AUTO-PUBLISH: a baseline gather now publishes its hour-stamped vintage to the
# model-data interface (config: model_data_root) and repoints `latest` — no
# separate publish step. For a VERIFICATION / parity / scratch rebuild that must
# NOT touch the live interface, set TARIFF_NO_PUBLISH=1:
#   TARIFF_NO_PUBLISH=1 sbatch scripts/submit_build_gather.sh

#SBATCH --job-name=tariff-gather
#SBATCH --time=01:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=192G
#SBATCH --output=/home/%u/slurm-logs/tariff-gather-%j.out
#SBATCH --error=/home/%u/slurm-logs/tariff-gather-%j.err
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

echo "=========================================================="
echo "Gather job ${SLURM_JOB_ID:-<none>} on $(hostname) | Start: $(date -Iseconds)"
echo "Args: ${GATHER_ARGS:-<none>}"
echo "=========================================================="

Rscript scripts/build_gather.R ${GATHER_ARGS:-}
RC=$?
echo "Gather exit: $RC at $(date -Iseconds)"
exit $RC
