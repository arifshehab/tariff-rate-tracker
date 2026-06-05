#!/usr/bin/env Rscript
# =============================================================================
# summarize_parity_results.R — reduce node-parallel parity task outputs
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
  library(tibble)
})

source(here('src', 'parity.R'))

`%||%` <- function(x, y) if (is.null(x)) y else x

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && i[1] < length(args)) args[i[1] + 1] else default
}

golden_root    <- get_arg('--golden')
candidate_root <- get_arg('--candidate', here())
artifacts_arg  <- get_arg('--artifacts', 'snapshot,daily_overall,daily_by_authority,daily_by_country,daily_by_category')
manifest_path  <- get_arg('--manifest', file.path('output', 'parity_manifest.tsv'))
results_dir    <- get_arg('--results-dir', file.path('output', 'parity_results'))

if (is.null(golden_root)) stop('--golden <dir> is required', call. = FALSE)
if (!dir.exists(golden_root)) stop('golden dir not found: ', golden_root, call. = FALSE)

kinds <- strsplit(artifacts_arg, ',')[[1]]

resolve_build_dirs <- function(root) {
  has_frozen <- file.exists(file.path(root, 'rate_timeseries.rds')) ||
    length(list.files(root, pattern = '^snapshot_.*\\.rds$')) > 0
  if (has_frozen) {
    return(list(ts_dir = root, daily_dir = file.path(root, 'daily')))
  }
  if (dir.exists(file.path(root, 'data', 'timeseries'))) {
    return(list(ts_dir = file.path(root, 'data', 'timeseries'),
                daily_dir = file.path(root, 'output', 'actual', 'daily')))
  }
  list(ts_dir = root, daily_dir = root)
}

artifact_dir_for <- function(dirs, kind) {
  if (grepl('^daily', kind)) dirs$daily_dir else dirs$ts_dir
}

gd <- resolve_build_dirs(golden_root)
cd <- resolve_build_dirs(candidate_root)

cat('=== Parity summary ===\n')
cat('Golden:    ', golden_root, '\n', sep = '')
cat('Candidate: ', candidate_root, '\n', sep = '')
cat('Results:   ', results_dir, '\n\n', sep = '')

manifest <- readr::read_tsv(manifest_path, show_col_types = FALSE, progress = FALSE)
result_files <- sort(list.files(results_dir, pattern = '^task_[0-9]{4}\\.tsv$', full.names = TRUE))
task_results <- if (length(result_files)) bind_rows(lapply(result_files, function(p) read_tsv(p, show_col_types = FALSE, progress = FALSE))) else tibble()

missing_tasks <- setdiff(seq_len(nrow(manifest)) - 1L, task_results$index %||% integer())
if (length(missing_tasks)) {
  cat('  [ERR] Missing task result(s): ', paste(missing_tasks, collapse = ', '), '\n', sep = '')
}

overall_fail <- length(missing_tasks) > 0

for (kind in kinds) {
  spec <- PARITY_ARTIFACTS[[kind]]
  if (is.null(spec)) next
  dir_g <- artifact_dir_for(gd, kind)
  dir_c <- artifact_dir_for(cd, kind)
  gfiles <- list.files(dir_g, pattern = utils::glob2rx(spec$glob), full.names = TRUE)
  cfiles <- list.files(dir_c, pattern = utils::glob2rx(spec$glob), full.names = TRUE)
  only_g <- setdiff(basename(gfiles), basename(cfiles))
  only_c <- setdiff(basename(cfiles), basename(gfiles))
  if (length(only_g)) {
    overall_fail <- TRUE
    for (f in only_g) cat(sprintf('  [%s] MISSING from candidate: %s\n', kind, f))
  }
  if (length(only_c)) {
    overall_fail <- TRUE
    for (f in only_c) cat(sprintf('  [%s] EXTRA in candidate:    %s\n', kind, f))
  }
}

if (nrow(task_results)) {
  for (i in seq_len(nrow(task_results))) {
    r <- task_results[i, ]
    if (isTRUE(r$pass)) {
      cat(sprintf('  [OK]   %-28s %d rows\n', r$label, r$n_rows_common))
    } else {
      overall_fail <- TRUE
      if (nzchar(r$error[[1]])) {
        cat(sprintf('  [ERR]  %-28s %s\n', r$label, r$error[[1]]))
      } else {
        cat(sprintf('  [FAIL] %-28s %d violation(s)\n', r$label, r$n_violations))
      }
    }
  }
}

expected_tasks <- nrow(manifest)
actual_tasks <- nrow(task_results)
passed_tasks <- sum(task_results$pass %in% TRUE, na.rm = TRUE)
failed_tasks <- sum(task_results$pass %in% FALSE, na.rm = TRUE) + length(missing_tasks)

cat('\n=== Summary ===\n')
cat(sprintf('  artifact tasks: %d | passed: %d | failed: %d\n',
            expected_tasks, passed_tasks, failed_tasks))

if (overall_fail || passed_tasks != expected_tasks) {
  quit(status = 1)
}
cat('  ALL ARTIFACTS WITHIN TOLERANCE\n')
quit(status = 0)
