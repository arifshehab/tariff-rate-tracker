#!/usr/bin/env Rscript
# =============================================================================
# capture_parity_golden.R — freeze a serial build's outputs as a parity golden
# =============================================================================
#
# Run AFTER a build. Copies the per-revision snapshots, the combined timeseries,
# and the daily CSVs to the EXTERNAL model-data interface (config:
# model_data_root) at <model_data_root>/golden/<git-sha>/ — NEVER the repo
# working tree — and writes a manifest recording the exact code + config state
# the golden was produced under. The parity comparator (scripts/run_parity_check.R)
# refuses to run when the candidate's policy_params.yaml hash differs from the
# manifest — otherwise a config edit would silently rebase the golden.
#
# Usage (after a build):
#   Rscript scripts/capture_parity_golden.R
#   Rscript scripts/capture_parity_golden.R --out <model_data_root>/golden/baseline_2026-06-03
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(jsonlite)
})
source(here('src', 'policy_params.R'))   # load_local_paths() -> model_data_root

# The golden lives on the EXTERNAL model-data interface (config:
# model_data_root), never in the repo working tree: <model_data_root>/golden/<sha>/.
MODEL_DATA_ROOT <- local({
  r <- tryCatch(load_local_paths()$model_data_root, error = function(e) NULL)
  if (is.null(r) || !nzchar(r)) stop('model_data_root not set (config/local_paths.yaml)') else r
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && i[1] < length(args)) args[i[1] + 1] else default
}

# --- Per-scenario goldens -----------------------------------------------------
# A golden can be frozen for the baseline (`actual`) OR for any counterfactual
# scenario (forced_labor, …). Each scenario gets its OWN frozen tree so the
# parity gate can guard the baseline AND every scenario at the same commit:
#   actual    -> tests/golden/<sha>/                  (flat; back-compatible)
#   <scenario>-> tests/golden/<sha>/scenarios/<name>/ (same flat-frozen layout)
# Source dirs default by the scenario harness convention (mirrors build_gather.R:
#   data/timeseries/<name>/ + output/scenario_<name>/actual/daily) but stay
# overridable via --timeseries-dir / --daily-dir for one-off candidate builds.
scenario    <- get_arg('--scenario', '')
is_baseline <- !nzchar(scenario) || scenario %in% c('actual', 'baseline')

default_ts_dir    <- if (is_baseline) here('data', 'timeseries') else here('data', 'timeseries', scenario)
default_daily_dir <- if (is_baseline) here('output', 'actual', 'daily') else here('output', paste0('scenario_', scenario), 'actual', 'daily')

ts_dir    <- get_arg('--timeseries-dir', default_ts_dir)
daily_dir <- get_arg('--daily-dir', default_daily_dir)

git_sha_full  <- tryCatch(system('git rev-parse HEAD', intern = TRUE), error = function(e) NA_character_)
git_sha_short <- tryCatch(system('git rev-parse --short HEAD', intern = TRUE), error = function(e) 'nogit')
git_dirty <- tryCatch(length(system('git status --porcelain -- src config', intern = TRUE)) > 0,
                      error = function(e) NA)

golden_base <- file.path(MODEL_DATA_ROOT, 'golden', git_sha_short)
default_out <- if (is_baseline) golden_base else file.path(golden_base, 'scenarios', scenario)
golden_root <- get_arg('--out', default_out)
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
# A scenario golden is produced from the SAME base policy_params.yaml deep-merged
# with its overlay — record both hashes so the gate can detect either drifting.
overlay_path <- if (!is_baseline) here('config', 'scenarios', scenario, 'overlay.yaml') else NA_character_
manifest <- list(
  git_sha           = git_sha_full,
  git_sha_short     = git_sha_short,
  scenario          = if (is_baseline) 'actual' else scenario,
  src_config_dirty  = git_dirty,                 # TRUE => golden captured from modified tracked code
  captured_at       = format(Sys.time(), '%Y-%m-%dT%H:%M:%S%z'),
  policy_params_md5 = unname(tools::md5sum(pp_path)),
  overlay_md5       = if (!is.na(overlay_path) && file.exists(overlay_path)) unname(tools::md5sum(overlay_path)) else NA_character_,
  use_policy_dates  = !('--use-hts-dates' %in% args),
  n_snapshots       = length(snaps),
  snapshots         = sort(basename(snaps)),
  daily_files       = sort(basename(daily)),
  has_timeseries    = file.exists(ts_path)
)
write_json(manifest, file.path(golden_root, 'manifest.json'),
           pretty = TRUE, auto_unbox = TRUE, na = 'null')

cat('Golden captured at:', golden_root, '\n')
cat('  scenario:', if (is_baseline) 'actual' else scenario,
    '| from ts:', ts_dir, '\n')
cat('  snapshots:', length(snaps), '| daily CSVs:', length(daily),
    '| timeseries:', file.exists(ts_path), '\n')
cat('  git:', git_sha_short, if (isTRUE(git_dirty)) '(DIRTY src/config!)' else '(clean src/config)', '\n')
if (isTRUE(git_dirty)) {
  cat('  WARNING: tracked src/ or config/ has uncommitted changes — a golden\n')
  cat('           should be captured from clean code. Commit/stash and re-run.\n')
}
