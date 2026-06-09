#!/bin/bash
#
# Submit a full Tariff Rate Tracker build (no publish) + the rate-calculation
# test suite + Russia annex sanity checks, as a single reviewable Slurm job.
#
# Usage:
#   sbatch scripts/submit_build_verify.sh
#
# What it runs:
#   1. Rscript src/00_build_timeseries.R --full          (rebuild all snapshots + downstream)
#   2. Rscript tests/test_rate_calculation.R             (expect 92 pass / 0 fail)
#   3. Inline sanity checks on the rebuilt snapshot_2026_rev_5.rds:
#        - Russia (4621) 7320.x springs: annex_1a rate_232 == 0.50 (was 2.0; mhd strip)
#        - Russia 7308.20 aluminum derivative: still 2.0 (correct)
#        - heading_program column present; annex_2 non-heading-program rate_232 == 0
#   4. rev_10 / Annex I-C sanity checks (added 2026-06-09 with the rev_10 merge):
#        - snapshot_2026_rev_10.rds exists; (c)(xi) codes carry annex_1c rate_232
#          (0.25 default, >= 0.15 framework floor everywhere)
#        - bnd_2026-06-08 NOT re-minted (edge-coincident with rev_10; superseded)
#        - panel has zero NA valid_from/valid_until rows (orphan-gate regression check)
#
# Profile mirrors submit_build_core.sh (the validation profile): full rebuild of
# the timeseries + downstream daily/ETR/quality, no alternatives, no publish.
#
# Resource sizing (from submit_build_core.sh):
#   - Walltime 4h: main build + post-build is ~1-3h with margin (no alternatives).
#   - Mem 192G: combine-snapshots has OOM'd at 96G (job 11189086, 2026-05-08).
#   - CPUs 4: build is single-threaded R; 4 covers BLAS/Arrow/OS overhead.

#SBATCH --job-name=tariff-build-verify
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=192G
#SBATCH --output=/home/%u/slurm-logs/tariff-build-verify-%j.out
#SBATCH --error=/home/%u/slurm-logs/tariff-build-verify-%j.err
#SBATCH --chdir=/nfs/roberts/project/pi_nrs36/ji252/repos/tariff-rate-tracker

set -uo pipefail

mkdir -p output/logs ~/slurm-logs

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
echo "CPUs:   ${SLURM_CPUS_PER_TASK}   Mem: ${SLURM_MEM_PER_NODE:-?} MB"
echo "R:      $(Rscript --version 2>&1)"
echo "=========================================================="

echo ">>> STEP 1: full rebuild (--full)"
BUILD_RC=0
Rscript src/00_build_timeseries.R --full || BUILD_RC=$?
echo ">>> build exit: $BUILD_RC"

if [ "$BUILD_RC" -ne 0 ]; then
  echo "!!! Build failed (exit $BUILD_RC) — skipping tests/sanity. Check OOM / release gate."
  echo "End: $(date -Iseconds)"
  exit $BUILD_RC
fi

echo ">>> STEP 2: tests/test_rate_calculation.R"
TEST_RC=0
Rscript tests/test_rate_calculation.R || TEST_RC=$?
echo ">>> test exit: $TEST_RC"

echo ">>> STEP 3: Russia rev_5 sanity checks"
Rscript -e '
  suppressPackageStartupMessages(library(dplyr))
  s <- readRDS("data/timeseries/snapshot_2026_rev_5.rds")
  cat("heading_program column present:", "heading_program" %in% names(s), "\n")
  ru <- s %>% filter(country == "4621")
  springs <- ru %>% filter(substr(hts10,1,4) == "7320", s232_annex == "annex_1a")
  cat("Russia 7320.x annex_1a rows:", nrow(springs),
      "| rate_232 range:", if (nrow(springs)) paste(range(springs$rate_232), collapse="-") else "NA",
      "| all == 0.50:", if (nrow(springs)) all(abs(springs$rate_232 - 0.50) < 1e-9) else NA, "\n")
  towers <- ru %>% filter(substr(hts10,1,6) == "730820")
  cat("Russia 7308.20 rows:", nrow(towers),
      "| max rate_232:", if (nrow(towers)) max(towers$rate_232) else NA,
      "| still 2.0:", if (nrow(towers)) any(abs(towers$rate_232 - 2.0) < 1e-9) else NA, "\n")
  if ("heading_program" %in% names(s)) {
    leak <- s %>% filter(s232_annex == "annex_2", rate_232 > 0, !heading_program)
    cat("annex_2 non-heading-program leak rows (expect 0):", nrow(leak), "\n")
  }
' || echo "!!! sanity check errored"

echo ">>> STEP 4: rev_10 / Annex I-C sanity checks"
Rscript -e '
  suppressPackageStartupMessages({library(dplyr); library(arrow)})
  p <- "data/timeseries/snapshot_2026_rev_10.rds"
  cat("snapshot_2026_rev_10 exists:", file.exists(p), "\n")
  if (file.exists(p)) {
    s <- readRDS(p)
    cxi <- s %>% filter(s232_annex == "annex_1c")
    cat("annex_1c rows:", nrow(cxi),
        "| distinct hts10:", n_distinct(cxi$hts10),
        "| rate_232 range:", if (nrow(cxi)) paste(range(cxi$rate_232), collapse="-") else "NA",
        "| all >= 0.15:", if (nrow(cxi)) all(cxi$rate_232 >= 0.15 - 1e-9) else NA,
        "| any == 0.25:", if (nrow(cxi)) any(abs(cxi$rate_232 - 0.25) < 1e-9) else NA, "\n")
  }
  cat("bnd_2026-06-08 NOT re-minted (expect TRUE):",
      !file.exists("data/timeseries/snapshot_bnd_2026-06-08.rds"), "\n")
  ds <- open_dataset("data/timeseries/rate_timeseries.parquet")
  na_n <- ds %>% filter(is.na(valid_from) | is.na(valid_until)) %>% count() %>% collect()
  cat("panel rows with NA intervals (expect 0):", na_n$n, "\n")
' || echo "!!! rev_10 sanity check errored"

echo "=========================================================="
echo "End:    $(date -Iseconds)   build=$BUILD_RC test=$TEST_RC"
echo "=========================================================="
exit $TEST_RC
