# =============================================================================
# Publish (Internal): Build Outputs to Shared Model-Data Tree
# =============================================================================
#
# Internal counterpart to src/publish_git.R. This module mirrors a curated
# subset of build outputs from the local repo into the Budget Lab shared
# model-data tree as an immutable, dated vintage. A `latest` symlink in the
# shared root points at the most recent vintage. Audience: other Budget Lab
# models on the same NFS share — not public.
#
# Layout (under <shared_root>):
#
#   Tariff-Rate-Tracker/
#     2026-05-08/
#       actual/
#         timeseries/
#           rate_timeseries.rds
#           rate_timeseries.parquet
#           metadata.rds
#         daily/         <- output/actual/daily/*.csv
#         quality/       <- output/actual/quality/*
#         etr/           <- output/actual/etr/*     (if built)
#         etrs_config/   <- output/actual/etrs_config/*  (if built)
#       scenarios/
#         <name>/        <- output/scenarios/<name>/*   (per named what-if)
#       manifest.json
#
# The rate panel lives under actual/timeseries/ so the downstream reader
# (tariff-model src/read_rate_panel.R) finds current-law at
# <vintage>/actual/timeseries/ and each what-if at
# <vintage>/scenarios/<name>/timeseries/.
#     2026-05-09/
#       ...
#     latest -> 2026-05-09
#
# Vintages are immutable. Re-running on the same calendar day appends `_2`,
# `_3`, ... . `--alternatives-only --publish-internal` produces a new vintage
# with the panel re-copied (cheap immutability over hardlink dedup).
#
# Usage (programmatic):
#
#   source(here('src', 'publish_internal.R'))
#   publish_internal(
#     build_flags = list(full = TRUE, core_only = TRUE, with_alternatives = FALSE),
#     build_started_at = Sys.time()
#   )
#
# =============================================================================

library(jsonlite)
library(here)

source(here('src', 'output_paths.R'))   # Phase 5 layout helpers (actual/ + scenarios/)


# Default location for the shared model-data root.
SHARED_ROOT_DEFAULT <- '/nfs/roberts/project/pi_nrs36/shared/model_data/Tariff-Rate-Tracker'


#' Publish a curated subset of build outputs to the shared model-data tree
#'
#' @param shared_root Root directory under which dated vintages are written.
#' @param vintage Vintage identifier; defaults to today's date with `_2`/`_3`
#'   suffix on collision. Pass an explicit string to override.
#' @param repo_root Repo root from which outputs are read.
#' @param build_flags Named list of CLI flags actually used (recorded in manifest).
#' @param build_started_at POSIXct; recorded in manifest. Defaults to now.
#' @param dry_run If TRUE, plan only — log the copy list and manifest without
#'   touching the shared tree.
#' @param update_latest If TRUE (default), repoint <shared_root>/latest at this
#'   vintage. Set FALSE to publish an additive vintage without changing the
#'   shared default (e.g. publishing into a tree another owner maintains).
#' @param include_scenarios If TRUE (default), publish every dir under
#'   output/scenarios/. Set FALSE to publish only the actual/ (current-law)
#'   tree — e.g. when scenario outputs are stale or intentionally withheld.
#' @return Invisibly, a list with `vintage`, `vintage_dir`, `manifest`, and
#'   `n_files` on success; NULL on dry-run.
publish_internal <- function(shared_root = SHARED_ROOT_DEFAULT,
                             vintage = NULL,
                             repo_root = here(),
                             build_flags = list(),
                             build_started_at = Sys.time(),
                             dry_run = FALSE,
                             update_latest = TRUE,
                             include_scenarios = TRUE) {

  if (!requireNamespace('arrow', quietly = TRUE)) {
    stop('publish_internal requires the arrow package (parquet conversion). ',
         'Install with: Rscript src/install_dependencies.R --all')
  }
  if (!requireNamespace('digest', quietly = TRUE)) {
    stop('publish_internal requires the digest package (manifest sha256). ',
         'Install with: Rscript src/install_dependencies.R --all')
  }

  ts_rds <- file.path(repo_root, 'data', 'timeseries', 'rate_timeseries.rds')
  if (!file.exists(ts_rds)) {
    stop('Cannot publish: rate_timeseries.rds not found at ', ts_rds,
         '. Run the build first.')
  }
  # Staleness guard: when called from a build run, refuse to publish a panel
  # produced by an earlier build. Skipped when build_started_at is NULL
  # (standalone `Rscript src/publish_internal.R` operates on whatever is on disk).
  if (!is.null(build_started_at) &&
      file.info(ts_rds)$mtime < build_started_at) {
    stop('Cannot publish: rate_timeseries.rds (mtime ', file.info(ts_rds)$mtime,
         ') is older than the current build start (', build_started_at, '). ',
         'The current build did not produce this file — refusing to publish a stale panel.')
  }

  if (!dir.exists(shared_root)) {
    if (!dry_run) dir.create(shared_root, recursive = TRUE)
    message('publish: created shared root ', shared_root)
  }

  if (is.null(vintage)) vintage <- resolve_vintage(shared_root)
  vintage_dir <- file.path(shared_root, vintage)

  message('\n', strrep('=', 70))
  message('PUBLISHING TO SHARED MODEL DATA')
  message(strrep('=', 70))
  message('Shared root: ', shared_root)
  message('Vintage:     ', vintage)
  message('Repo root:   ', repo_root)
  if (dry_run) message('DRY RUN — no files will be written')
  message(strrep('=', 70))

  if (!dry_run) dir.create(vintage_dir, recursive = TRUE, showWarnings = FALSE)

  copied <- list()
  out_root <- file.path(repo_root, 'output')

  copied$timeseries <- publish_timeseries(repo_root, vintage_dir, dry_run = dry_run)

  # Phase 5: real ("actual") results publish into <vintage>/actual/<section>;
  # named what-ifs publish into <vintage>/scenarios/<name>. Section + root names
  # come from src/output_paths.R so the writers and publish can't drift apart.
  for (section in ACTUAL_SECTIONS) {
    copied[[section]] <- publish_dir(
      file.path(actual_root(out_root), section),
      file.path(vintage_dir, 'actual', section),
      min_mtime = build_started_at,
      dry_run = dry_run)
  }

  scen_root <- scenarios_root(out_root)
  if (include_scenarios && dir.exists(scen_root)) {
    for (scen_path in list.dirs(scen_root, recursive = FALSE)) {
      copied[[paste0('scenario.', basename(scen_path))]] <- publish_dir(
        scen_path,
        file.path(vintage_dir, 'scenarios', basename(scen_path)),
        min_mtime = build_started_at,
        dry_run = dry_run)
    }
  }

  manifest <- build_manifest(vintage = vintage,
                             vintage_dir = vintage_dir,
                             repo_root = repo_root,
                             build_flags = build_flags,
                             build_started_at = build_started_at,
                             copied = copied)

  if (!dry_run) {
    write(jsonlite::toJSON(manifest, pretty = TRUE, auto_unbox = TRUE, na = 'string'),
          file.path(vintage_dir, 'manifest.json'))
    if (update_latest) update_latest_symlink(shared_root, vintage)
  }

  n_files <- sum(vapply(copied, function(x) length(x$files), integer(1)))
  message('\nPublished ', n_files, ' file(s) to ', vintage_dir)
  if (update_latest) {
    message('Updated symlink: ', file.path(shared_root, 'latest'), ' -> ', vintage)
  } else {
    message('Left ', file.path(shared_root, 'latest'),
            ' unchanged (additive publish; update_latest = FALSE)')
  }
  message(strrep('=', 70), '\n')

  invisible(list(vintage = vintage,
                 vintage_dir = vintage_dir,
                 manifest = manifest,
                 n_files = n_files))
}


#' Resolve an unused vintage identifier (today's date, with _2/_3 on collision).
#'
#' @keywords internal
resolve_vintage <- function(shared_root) {
  base <- format(Sys.Date(), '%Y-%m-%d')
  candidate <- base
  i <- 2L
  while (file.exists(file.path(shared_root, candidate))) {
    candidate <- paste0(base, '_', i)
    i <- i + 1L
  }
  candidate
}


#' Copy the timeseries panel + metadata, and emit a parquet companion.
#'
#' @keywords internal
publish_timeseries <- function(repo_root, vintage_dir, dry_run = FALSE) {
  src_dir <- file.path(repo_root, 'data', 'timeseries')
  # The baseline (current-law) panel is the "actual" series. tariff-model's
  # read_rate_panel.R resolves it at <vintage>/actual/timeseries/.
  dest_dir <- file.path(vintage_dir, 'actual', 'timeseries')

  src_rds <- file.path(src_dir, 'rate_timeseries.rds')
  src_meta <- file.path(src_dir, 'metadata.rds')

  message('publish: timeseries -> ', dest_dir)
  if (!dry_run) dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  files <- character()

  dest_rds <- file.path(dest_dir, 'rate_timeseries.rds')
  if (!dry_run) file.copy(src_rds, dest_rds, overwrite = TRUE)
  files <- c(files, dest_rds)
  message('  copied:    rate_timeseries.rds')

  dest_parquet <- file.path(dest_dir, 'rate_timeseries.parquet')
  if (!dry_run) {
    ts <- readRDS(src_rds)
    arrow::write_parquet(ts, dest_parquet, compression = 'snappy')
    rm(ts); gc()
  }
  files <- c(files, dest_parquet)
  message('  converted: rate_timeseries.parquet')

  if (file.exists(src_meta)) {
    dest_meta <- file.path(dest_dir, 'metadata.rds')
    if (!dry_run) file.copy(src_meta, dest_meta, overwrite = TRUE)
    files <- c(files, dest_meta)
    message('  copied:    metadata.rds')
  }

  list(present = TRUE, files = files)
}


#' Copy a build output directory if it exists, recursively.
#'
#' When `min_mtime` is non-NULL, files older than that timestamp are skipped.
#' This prevents stale outputs from a previous build leaking into a new vintage
#' (e.g. `--build-only --publish-internal` should not bundle daily/ from an
#' earlier run).
#'
#' @keywords internal
publish_dir <- function(src_dir, dest_dir, min_mtime = NULL, dry_run = FALSE) {
  if (!dir.exists(src_dir)) {
    message('publish: skipping (not present) ', src_dir)
    return(list(present = FALSE, files = character()))
  }

  src_files <- list.files(src_dir, recursive = TRUE, full.names = TRUE,
                          all.files = FALSE, no.. = TRUE)
  if (length(src_files) > 0) {
    info <- file.info(src_files)
    keep <- !info$isdir
    if (!is.null(min_mtime)) {
      stale <- info$mtime < min_mtime
      stale[is.na(stale)] <- FALSE
      n_stale <- sum(stale & keep)
      if (n_stale > 0) {
        message('publish: skipping ', n_stale, ' stale file(s) under ', src_dir,
                ' (older than build start)')
      }
      keep <- keep & !stale
    }
    src_files <- src_files[keep]
  }

  if (length(src_files) == 0) {
    message('publish: skipping (empty)       ', src_dir)
    return(list(present = TRUE, files = character()))
  }

  message('publish: ', basename(dest_dir), ' -> ', dest_dir,
          ' (', length(src_files), ' file', if (length(src_files) != 1) 's' else '', ')')

  if (!dry_run) dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  copied <- character()
  for (sf in src_files) {
    rel <- substring(sf, nchar(src_dir) + 2L)
    df <- file.path(dest_dir, rel)
    if (!dry_run) {
      dir.create(dirname(df), recursive = TRUE, showWarnings = FALSE)
      file.copy(sf, df, overwrite = TRUE)
    }
    copied <- c(copied, df)
  }

  list(present = TRUE, files = copied)
}


#' Build the per-vintage manifest.
#'
#' @keywords internal
build_manifest <- function(vintage, vintage_dir, repo_root,
                           build_flags, build_started_at, copied) {
  all_files <- unlist(lapply(copied, function(x) x$files), use.names = FALSE)
  inventory <- lapply(all_files, function(f) {
    if (!file.exists(f)) {
      return(list(path = sub(paste0('^', vintage_dir, '/?'), '', f),
                  size_bytes = NA_integer_, sha256 = NA_character_))
    }
    list(
      path = sub(paste0('^', vintage_dir, '/?'), '', f),
      size_bytes = as.integer(file.info(f)$size),
      sha256 = digest::digest(file = f, algo = 'sha256')
    )
  })

  git_info <- capture_git_info(repo_root)

  pkgs <- c('tidyverse', 'jsonlite', 'yaml', 'here', 'arrow', 'digest', 'pdftools')
  pkg_versions <- vapply(pkgs, function(p) {
    if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else NA_character_
  }, character(1))

  list(
    vintage = vintage,
    build_started_at = if (is.null(build_started_at)) NA_character_ else format(build_started_at, '%Y-%m-%dT%H:%M:%S%z'),
    published_at = format(Sys.time(), '%Y-%m-%dT%H:%M:%S%z'),
    repo_root = repo_root,
    git = git_info,
    build_flags = build_flags,
    sections = vapply(names(copied), function(k) copied[[k]]$present, logical(1)),
    r_version = paste(R.version$major, R.version$minor, sep = '.'),
    package_versions = as.list(pkg_versions),
    files = inventory
  )
}


#' Best-effort capture of git commit, branch, and dirty bit. NA if not a repo.
#'
#' @keywords internal
capture_git_info <- function(repo_root) {
  is_repo <- system2('git', c('-C', repo_root, 'rev-parse', '--is-inside-work-tree'),
                     stdout = TRUE, stderr = FALSE)
  if (length(is_repo) == 0 || !identical(trimws(is_repo[1]), 'true')) {
    return(list(commit = NA_character_, branch = NA_character_,
                dirty = NA, remote = NA_character_))
  }
  commit <- tryCatch(trimws(system2('git', c('-C', repo_root, 'rev-parse', 'HEAD'),
                                    stdout = TRUE, stderr = FALSE))[1],
                     error = function(e) NA_character_)
  branch <- tryCatch(trimws(system2('git', c('-C', repo_root, 'rev-parse', '--abbrev-ref', 'HEAD'),
                                    stdout = TRUE, stderr = FALSE))[1],
                     error = function(e) NA_character_)
  dirty_lines <- tryCatch(system2('git', c('-C', repo_root, 'status', '--porcelain'),
                                  stdout = TRUE, stderr = FALSE),
                          error = function(e) character())
  remote <- tryCatch(trimws(system2('git', c('-C', repo_root, 'config', '--get', 'remote.origin.url'),
                                    stdout = TRUE, stderr = FALSE))[1],
                     error = function(e) NA_character_)
  list(commit = commit,
       branch = branch,
       dirty = length(dirty_lines) > 0,
       remote = remote)
}


#' Atomically point <shared_root>/latest at the new vintage.
#'
#' Writes a temp symlink and renames over the existing one so a partial publish
#' never leaves `latest` pointing at a half-written vintage.
#'
#' @keywords internal
update_latest_symlink <- function(shared_root, vintage) {
  link_path <- file.path(shared_root, 'latest')
  tmp_path <- file.path(shared_root, paste0('.latest.tmp.', Sys.getpid()))
  unlink(tmp_path, force = TRUE)  # clear stale symlink/file from a prior failed publish
  ok <- file.symlink(vintage, tmp_path)
  if (!ok) {
    warning('Failed to create symlink ', tmp_path, ' -> ', vintage,
            '. Skipping latest update.')
    return(invisible(FALSE))
  }
  file.rename(tmp_path, link_path)
  invisible(TRUE)
}


# =============================================================================
# CLI Entry Point
# =============================================================================
#
# Standalone publish (after a build has already been run):
#   Rscript src/publish_internal.R
#   Rscript src/publish_internal.R --dry-run
#   Rscript src/publish_internal.R --vintage 2026-05-08_manual
#
# This mode does NOT know which build flags produced the outputs; it records
# `manual = TRUE` in the manifest. For full provenance, prefer publishing
# via `--publish-internal` on src/00_build_timeseries.R.

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  dry_run <- '--dry-run' %in% args
  vintage <- NULL
  for (i in seq_along(args)) {
    if (args[i] == '--vintage' && i < length(args)) vintage <- args[i + 1]
  }

  publish_internal(
    vintage = vintage,
    build_flags = list(manual = TRUE),
    build_started_at = NULL,  # skip staleness guard for standalone runs
    dry_run = dry_run
  )
}
