#!/bin/bash
#
# Plank 3 parity gate: compare the freshly array-built timeseries against the
# frozen golden (tests/golden/9f9837d) after the s122 de-blob.
#
# Submitted with an afterok dependency on the gather job, so it runs once the
# array build + assembly + daily series are all complete:
#   GOLDEN=tests/golden/9f9837d sbatch --dependency=afterok:<gather> scripts/submit_plank3_parity.sh
#
# Skips the monolithic `timeseries` artifact (1.38 GB x2 OOMs even at 192 G) — the
# 43 per-snapshot comparisons + the daily artifacts cover the same data, one file
# at a time (memory-safe), with no loss of coverage. No --no-config-check needed:
# Plank 3 touches only code + tests, so policy_params.yaml still hashes to the
# golden manifest.

#SBATCH --job-name=theseus-plank3p
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --output=/home/%u/slurm-logs/theseus-plank3p-%j.out
#SBATCH --error=/home/%u/slurm-logs/theseus-plank3p-%j.err
#SBATCH --chdir=/nfs/roberts/project/pi_nrs36/jar335/Repositories/tariff-rate-tracker

set -uo pipefail

mkdir -p ~/slurm-logs

if [ -f /etc/profile.d/z01_lmodinit.sh ]; then
  source /etc/profile.d/z01_lmodinit.sh
elif [ -f /etc/profile.d/lmod.sh ]; then
  source /etc/profile.d/lmod.sh
fi
module purge
module load R/4.4.2-gfbf-2024a

GOLDEN="${GOLDEN:-tests/golden/9f9837d}"

echo "=========================================================="
echo "Job:    ${SLURM_JOB_ID:-local} on $(hostname)"
echo "Start:  $(date -Iseconds)"
echo "Branch: $(git rev-parse --abbrev-ref HEAD)  Commit: $(git rev-parse --short HEAD)"
echo "Golden: $GOLDEN"
echo "=========================================================="

Rscript scripts/run_parity_check.R \
  --golden "$GOLDEN" \
  --artifacts snapshot,daily_overall,daily_by_authority,daily_by_country,daily_by_category
RC=$?

echo
echo "=========================================================="
echo "End:    $(date -Iseconds)"
echo "Parity: $([ "$RC" -eq 0 ] && echo GREEN || echo DRIFT)"
echo "=========================================================="
exit $RC
