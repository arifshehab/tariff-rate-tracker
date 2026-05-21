#!/bin/bash
#
# Submit a full Tariff Rate Tracker build + --publish-internal as a Slurm job.
#
# Usage:
#   sbatch scripts/submit_publish_internal.sh
#
# What it runs:
#   Rscript src/00_build_timeseries.R --full --with-alternatives --publish-internal
#
# Produces a complete vintage in the Budget Lab shared model-data tree:
#   /nfs/roberts/project/pi_nrs36/shared/model_data/Tariff-Rate-Tracker/<vintage>/
#
# This is the canonical "internal publication run" — full build (all 41
# revisions), all six rebuild alternatives, plus the curated mirror to the
# shared tree. For the public release/ folder, use --publish-git instead (or
# both flags in one job — see below).
#
# Companion scripts:
#   scripts/submit_build.sh                   — identical run, kept for
#                                                muscle-memory compatibility.
#   (no submit_publish_git.sh yet — the in-repo release/ workflow is the
#    same build with --publish-git appended; add a sibling script if a
#    git-only or both-modes run becomes routine.)
#
# To publish to BOTH internal NFS and the in-repo release/ in one job, edit
# the Rscript line below to add `--publish-git`:
#   Rscript src/00_build_timeseries.R --full --with-alternatives --publish-internal --publish-git
#
# Resource sizing rationale (same as submit_build.sh):
#   - Walltime: 12 hours. Main build + post-build is ~1h; each of the three
#     USMCA alternatives re-runs the 41-revision loop and takes ~3-4h, so
#     --with-alternatives needs ~10-12h total. A previous 5h budget timed
#     out partway through the third alternative (job 11201313, 2026-05-09).
#   - CPUs: 4. The build is single-threaded R; parallelization is documented
#     but not yet implemented end-to-end. 4 CPUs cover incidental BLAS / Arrow
#     / OS overhead. Bumping higher does not speed up the main loop.
#   - Memory: 192 GB. The combine-snapshots step OOM'd at 96 GB on 2026-05-08
#     (job 11189086); alternatives themselves have OOM'd in the past on the
#     184M-row combined timeseries. 192 GB gives headroom for combine +
#     alternatives. Lower it if your queue is tight.
#
# One-time setup before first submission (login node):
#   mkdir -p ~/slurm-logs
#   module load R/4.4.2-gfbf-2024a
#   Rscript src/install_dependencies.R --all   # arrow + digest required for --publish-internal
#
# Log locations:
#   ~/slurm-logs/tariff-publish-internal-<jobid>.{out,err}   (Rscript stdout/stderr)
#   output/logs/build_<timestamp>.log                         (build's structured R log)

#SBATCH --job-name=tariff-publish-internal
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=192G
#SBATCH --output=/home/%u/slurm-logs/tariff-publish-internal-%j.out
#SBATCH --error=/home/%u/slurm-logs/tariff-publish-internal-%j.err
#SBATCH --chdir=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-rate-tracker

set -euo pipefail

mkdir -p output/logs

# Match thread counts to allocated CPUs so multi-threaded BLAS / OpenMP libraries
# don't oversubscribe the node.
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"

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
echo "Job:    $SLURM_JOB_ID on $(hostname)"
echo "Start:  $(date -Iseconds)"
echo "CPUs:   ${SLURM_CPUS_PER_TASK}"
echo "Mem:    ${SLURM_MEM_PER_NODE:-?} MB"
echo "PWD:    $(pwd)"
echo "R:      $(Rscript --version 2>&1)"
echo "Cmd:    Rscript src/00_build_timeseries.R --full --with-alternatives --publish-internal"
echo "=========================================================="

RC=0
Rscript src/00_build_timeseries.R --full --with-alternatives --publish-internal || RC=$?

echo "=========================================================="
echo "End:    $(date -Iseconds)"
echo "Exit:   $RC"
echo "=========================================================="

exit $RC
