#!/usr/bin/env Rscript
# =============================================================================
# run_parity_check.R — compare a candidate build against a golden reference
# =============================================================================
#
# The Phase-0+ parity gate. Compares every artifact (snapshots, combined
# timeseries, daily CSVs) of a candidate build against a frozen golden using
# the tolerance comparator in src/parity.R, and exits non-zero on any drift.
#
# Layouts (auto-detected per side):
#   frozen — snapshots + rate_timeseries.rds at <root>, daily CSVs in <root>/daily
#            (this is what scripts/capture_parity_golden.R writes)
#   live   — a working repo: snapshots in <root>/data/timeseries,
#            daily CSVs in <root>/output/daily
#
# Usage:
#   Rscript scripts/run_parity_check.R --golden tests/golden/<sha>
#       # candidate defaults to the live repo (cwd)
#   Rscript scripts/run_parity_check.R --golden <dir> --candidate <dir>
#   Rscript scripts/run_parity_check.R --golden <dir> --artifacts snapshot,timeseries
#
# Exit code: 0 = all within tolerance; 1 = at least one violation (or setup error).
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
})

source(here('src', 'parity.R'))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && i[1] < length(args)) args[i[1] + 1] else default
}

golden_root    <- get_arg('--golden')
candidate_root <- get_arg('--candidate', here())
artifacts_arg  <- get_arg('--artifacts', 'snapshot,timeseries,daily_overall,daily_by_authority,daily_by_country,daily_by_category')
strict_config  <- !('--no-config-check' %in% args)

if (is.null(golden_root)) stop('--golden <dir> is required', call. = FALSE)
if (!dir.exists(golden_root)) stop('golden dir not found: ', golden_root, call. = FALSE)
kinds <- strsplit(artifacts_arg, ',')[[1]]

# Resolve where snapshots and daily CSVs live for a given root (frozen vs live).
resolve_build_dirs <- function(root) {
  has_frozen <- file.exists(file.path(root, 'rate_timeseries.rds')) ||
    length(list.files(root, pattern = '^snapshot_.*\\.rds$')) > 0
  if (has_frozen) {
    return(list(ts_dir = root, daily_dir = file.path(root, 'daily')))
  }
  if (dir.exists(file.path(root, 'data', 'timeseries'))) {
    return(list(ts_dir = file.path(root, 'data', 'timeseries'),
                daily_dir = file.path(root, 'output', 'daily')))
  }
  list(ts_dir = root, daily_dir = root)
}

gd <- resolve_build_dirs(golden_root)
cd <- resolve_build_dirs(candidate_root)

cat('=== Parity check ===\n')
cat('Golden:    ', golden_root, '  (ts:', gd$ts_dir, ')\n')
cat('Candidate: ', candidate_root, '  (ts:', cd$ts_dir, ')\n')
cat('Artifacts: ', paste(kinds, collapse = ', '), '\n\n')

# ---- config-hash guard (impl-req-1: a config edit must not silently rebase) ----
manifest_path <- file.path(golden_root, 'manifest.json')
if (strict_config && file.exists(manifest_path)) {
  manifest <- jsonlite::read_json(manifest_path)
  golden_md5 <- manifest$policy_params_md5
  cand_md5 <- unname(tools::md5sum(here('config', 'policy_params.yaml')))
  if (!is.null(golden_md5) && !is.na(cand_md5) && !identical(golden_md5, cand_md5)) {
    stop(sprintf(paste0('policy_params.yaml hash mismatch vs golden manifest:\n',
                        '  golden:    %s\n  candidate: %s\n',
                        'The golden was captured under a different config. Re-capture the\n',
                        'golden, or pass --no-config-check to override.'),
                 golden_md5, cand_md5), call. = FALSE)
  }
  cat('Config check: policy_params.yaml matches golden manifest.\n\n')
}

# ---- pair files per artifact kind and compare ----
results <- list()
pair_and_compare <- function(kind, gfiles, cfiles, ts) {
  gnames <- basename(gfiles); names(gfiles) <- gnames
  cnames <- basename(cfiles); names(cfiles) <- cnames
  shared <- intersect(gnames, cnames)
  only_g <- setdiff(gnames, cnames); only_c <- setdiff(cnames, gnames)
  for (f in only_g) cat(sprintf('  [%s] MISSING from candidate: %s\n', kind, f))
  for (f in only_c) cat(sprintf('  [%s] EXTRA in candidate:    %s\n', kind, f))
  out <- list()
  for (f in shared) {
    res <- tryCatch(
      compare_parity_files(cfiles[[f]], gfiles[[f]], kind, label = paste0(kind, ':', f)),
      error = function(e) list(label = paste0(kind, ':', f), pass = FALSE,
                               n_violations = NA, n_rows_common = NA,
                               violations = NULL, error = conditionMessage(e)))
    out[[f]] <- res
    if (isTRUE(res$pass)) {
      cat(sprintf('  [OK]   %-28s %d rows\n', res$label, res$n_rows_common))
    } else if (!is.null(res$error)) {
      cat(sprintf('  [ERR]  %-28s %s\n', res$label, res$error))
    } else {
      cat(sprintf('  [FAIL] %-28s %d violation(s)\n', res$label, res$n_violations))
    }
  }
  # Record a synthetic failure for unmatched files too.
  if (length(only_g) || length(only_c)) {
    out[['__file_set__']] <- list(label = paste0(kind, ':file-set'), pass = FALSE,
                                  n_violations = length(only_g) + length(only_c))
  }
  out
}

for (kind in kinds) {
  spec <- PARITY_ARTIFACTS[[kind]]
  if (is.null(spec)) { cat('  (skip unknown artifact kind: ', kind, ')\n'); next }
  dir_g <- if (grepl('^daily', kind)) gd$daily_dir else gd$ts_dir
  dir_c <- if (grepl('^daily', kind)) cd$daily_dir else cd$ts_dir
  gfiles <- list.files(dir_g, pattern = utils::glob2rx(spec$glob), full.names = TRUE)
  cfiles <- list.files(dir_c, pattern = utils::glob2rx(spec$glob), full.names = TRUE)
  if (length(gfiles) == 0 && length(cfiles) == 0) next
  cat(sprintf('--- %s (%d golden / %d candidate files) ---\n', kind, length(gfiles), length(cfiles)))
  results[[kind]] <- pair_and_compare(kind, gfiles, cfiles)
}

# ---- summary ----
flat <- unlist(results, recursive = FALSE)
n_total <- length(flat)
n_fail  <- sum(vapply(flat, function(r) !isTRUE(r$pass), logical(1)))
cat('\n=== Summary ===\n')
cat(sprintf('  artifacts compared: %d | passed: %d | failed: %d\n',
            n_total, n_total - n_fail, n_fail))

if (n_fail > 0) {
  cat('\n--- Failure detail (first few per artifact) ---\n')
  for (r in flat) {
    if (!isTRUE(r$pass) && !is.null(r$violations)) {
      cat(format_parity_report(r, max_show = 12), '\n\n')
    }
  }
  quit(status = 1)
}
cat('  ALL ARTIFACTS WITHIN TOLERANCE\n')
quit(status = 0)
