#!/usr/bin/env Rscript
# =============================================================================
# build_parity_manifest.R — enumerate per-file parity comparisons
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
  library(tibble)
})

source(here('src', 'parity.R'))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && i[1] < length(args)) args[i[1] + 1] else default
}

golden_root    <- get_arg('--golden')
candidate_root <- get_arg('--candidate', here())
artifacts_arg  <- get_arg('--artifacts', 'snapshot,daily_overall,daily_by_authority,daily_by_country,daily_by_category')
manifest_path  <- get_arg('--manifest', file.path('output', 'parity_manifest.tsv'))

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

rows <- list()
for (kind in kinds) {
  spec <- PARITY_ARTIFACTS[[kind]]
  if (is.null(spec)) next
  dir_g <- artifact_dir_for(gd, kind)
  dir_c <- artifact_dir_for(cd, kind)
  gfiles <- list.files(dir_g, pattern = utils::glob2rx(spec$glob), full.names = TRUE)
  cfiles <- list.files(dir_c, pattern = utils::glob2rx(spec$glob), full.names = TRUE)
  shared <- intersect(basename(gfiles), basename(cfiles))
  for (f in shared) {
    rows[[length(rows) + 1]] <- tibble(
      kind = kind,
      file = f,
      label = paste0(kind, ':', f),
      golden_path = file.path(dir_g, f),
      candidate_path = file.path(dir_c, f)
    )
  }
}

manifest <- if (length(rows)) bind_rows(rows) else tibble(
  kind = character(),
  file = character(),
  label = character(),
  golden_path = character(),
  candidate_path = character()
)

dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
write_tsv(manifest, manifest_path)
cat('Wrote manifest: ', manifest_path, ' (', nrow(manifest), ' rows)\n', sep = '')
