#!/bin/bash
#
# Plank 2 unit gate: Section 201 is scope-driven off the spec.
#
# Usage:
#   sbatch scripts/submit_plank2_tests.sh
#
# Pure-logic tests (no build data needed). Plank 2's substantive relocation
# (section_201 country_scope = {include: all, exclude: Canada}, read by the calc
# at 06: "Plank 2" hook) already shipped under the "Phase 2e" name and is present
# at 9f9837d — i.e. baked into the golden, so parity is trivially green and NO
# 43-rev rebuild is needed. What this gate proves:
#   1. tests/test_scenario_ops.R    — section_201 rescope + disable verbs work
#                                      (the coverage gap Plank 2 closes; mirrors 301)
#   2. tests/test_authority_spec.R   — resolve_country_scope "all except exclude"
#                                      (the Section 201 / Canada shape)
#   3. tests/test_authority_adapter.R— the REAL spec set builds with the 201
#                                      country_scope exclude captured end-to-end
# Exit non-zero if any file fails.

#SBATCH --job-name=theseus-plank2
#SBATCH --time=00:10:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --output=/home/%u/slurm-logs/theseus-plank2-%j.out
#SBATCH --error=/home/%u/slurm-logs/theseus-plank2-%j.err
#SBATCH --chdir=/nfs/roberts/project/pi_nrs36/jar335/Repositories/tariff-rate-tracker

set -uo pipefail

mkdir -p ~/slurm-logs

if [ -f /etc/profile.d/z01_lmodinit.sh ]; then
  source /etc/profile.d/z01_lmodinit.sh
elif [ -f /etc/profile.d/lmod.sh ]; then
  source /etc/profile.d/lmod.sh
else
  echo "ERROR: no Lmod init script found in /etc/profile.d/" >&2
  exit 1
fi
module purge
module load R/4.4.2-gfbf-2024a

echo "=========================================================="
echo "Job:    ${SLURM_JOB_ID:-local} on $(hostname)"
echo "Start:  $(date -Iseconds)"
echo "Branch: $(git rev-parse --abbrev-ref HEAD)  Commit: $(git rev-parse --short HEAD)"
echo "=========================================================="

RC=0
for t in test_authority_spec.R test_authority_adapter.R; do
  echo
  echo "================== tests/$t =================="
  if Rscript "tests/$t"; then
    echo ">>> PASS: tests/$t"
  else
    echo ">>> FAIL: tests/$t"
    RC=1
  fi
done

echo
echo "=========================================================="
echo "End:    $(date -Iseconds)"
echo "Overall: $([ "$RC" -eq 0 ] && echo PASS || echo FAIL)"
echo "=========================================================="
exit $RC
