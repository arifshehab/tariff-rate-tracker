#!/usr/bin/env Rscript
# =============================================================================
# capture_parity_golden.R — freeze a serial build's outputs as a parity golden
# =============================================================================
#
# Run AFTER a clean serial build (scripts/submit_build_full.sh). Copies the
# per-revision snapshots, the combined timeseries, and the daily CSVs into
# tests/golden/<git-sha>/ and writes a manifest recording the exact code +
# config state the golden was produced under. The parity comparator
# (scripts/run_parity_check.R) refuses to run when the candidate's
# policy_params.yaml hash differs from the manifest — otherwise a config edit
# would silently rebase the golden (the docs/authority_spec.md impl-req-1 hazard).
#
# Usage (after a build):
#   Rscript scripts/capture_parity_golden.R
#   Rscript scripts/capture_parity_golden.R --out tests/golden/baseline_2026-06-03
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && i[1] < length(args)) args[i[1] + 1] else default
}

ts_dir    <- get_arg('--timeseries-dir', here('data', 'timeseries'))
daily_dir <- get_arg('--daily-dir', here('output', 'daily'))

git_sha_full  <- tryCatch(system('git rev-parse HEAD', intern = TRUE), error = function(e) NA_character_)
git_sha_short <- tryCatch(system('git rev-parse --short HEAD', intern = TRUE), error = function(e) 'nogit')
git_dirty <- tryCatch(length(system('git status --porcelain -- src config', intern = TRUE)) > 0,
                      error = function(e) NA)

golden_root <- get_arg('--out', here('tests', 'golden', git_sha_short))
dir.create(golden_root, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(golden_root, 'daily'), recursive = TRUE, showWarnings = FALSE)

# ---- copy snapshots + combined timeseries ----
snaps <- list.files(ts_dir, pattern = '^snapshot_.*\\.rds$', full.names = TRUE)
if (length(snaps) == 0) stop('No snapshots found in ', ts_dir, ' — run a full build first.')
file.copy(snaps, golden_root, overwrite = TRUE)

ts_path <- file.path(ts_dir, 'rate_timeseries.rds')
if (file.exists(ts_path)) file.copy(ts_path, golden_root, overwrite = TRUE)

# ---- copy daily CSVs ----
daily <- if (dir.exists(daily_dir)) list.files(daily_dir, pattern = '\\.csv$', full.names = TRUE) else character()
if (length(daily)) file.copy(daily, file.path(golden_root, 'daily'), overwrite = TRUE)

# ---- manifest ----
pp_path <- here('config', 'policy_params.yaml')
manifest <- list(
  git_sha           = git_sha_full,
  git_sha_short     = git_sha_short,
  src_config_dirty  = git_dirty,                 # TRUE => golden captured from modified tracked code
  captured_at       = format(Sys.time(), '%Y-%m-%dT%H:%M:%S%z'),
  policy_params_md5 = unname(tools::md5sum(pp_path)),
  use_policy_dates  = !('--use-hts-dates' %in% args),
  n_snapshots       = length(snaps),
  snapshots         = sort(basename(snaps)),
  daily_files       = sort(basename(daily)),
  has_timeseries    = file.exists(ts_path)
)
write_json(manifest, file.path(golden_root, 'manifest.json'),
           pretty = TRUE, auto_unbox = TRUE, na = 'null')

cat('Golden captured at:', golden_root, '\n')
cat('  snapshots:', length(snaps), '| daily CSVs:', length(daily),
    '| timeseries:', file.exists(ts_path), '\n')
cat('  git:', git_sha_short, if (isTRUE(git_dirty)) '(DIRTY src/config!)' else '(clean src/config)', '\n')
if (isTRUE(git_dirty)) {
  cat('  WARNING: tracked src/ or config/ has uncommitted changes — a golden\n')
  cat('           should be captured from clean code. Commit/stash and re-run.\n')
}
