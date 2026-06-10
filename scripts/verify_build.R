#!/usr/bin/env Rscript
# =============================================================================
# verify_build.R — shared post-build verification gate (unification Phase 2)
# =============================================================================
#
# Runs the rate-calculation test suite plus the snapshot/panel sanity checks
# that used to live inline in scripts/submit_build_verify.sh, against EITHER
# build layout:
#
#   rds (repo data/timeseries or an array scratch):
#       <root>/snapshot_<rev>.rds          (per-revision snapshots)
#       <root>/rate_timeseries.parquet     (combined panel, for the NA check)
#   vintage (parquet, written by publish_vintage.R):
#       <root>/actual/snapshots/valid_from=*/rates.parquet
#       (or <root>/snapshots/... when given a series dir directly)
#
# Layout is auto-detected from <root>. Unlike the old inline steps — which only
# PRINTED the sanity values and gated solely on the test suite — every check
# here is a gate: any failure exits 1. That is the point: the array finalize
# must be able to require this to pass before repointing `latest`.
#
# Checks (expectations carried over from submit_build_verify.sh):
#   1. tests/test_rate_calculation.R passes        (skippable: --skip-tests)
#   2. Russia rev_5 (mhd strip): heading_program column present; 7320.x
#      annex_1a springs rate_232 == 0.50; 7308.20 derivative still 2.0;
#      zero annex_2 non-heading-program leak rows
#   3. rev_10 / Annex I-C: snapshot present; (c)(xi) codes carry annex_1c
#      rate_232 (>= 0.15 framework floor, 0.25 default present);
#      bnd_2026-06-08 NOT re-minted (edge-coincident with rev_10)
#   4. panel has zero NA valid_from/valid_until rows (orphan-gate regression)
#
# Usage:
#   Rscript scripts/verify_build.R                          # repo data/timeseries
#   Rscript scripts/verify_build.R --output-root <dir>      # vintage or rds dir
#   Rscript scripts/verify_build.R --skip-tests             # sanity checks only
# =============================================================================

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(arrow)
})

args <- commandArgs(trailingOnly = TRUE)
root <- here('data', 'timeseries')
skip_tests <- '--skip-tests' %in% args
for (i in seq_along(args)) {
  if (args[i] == '--output-root' && i < length(args)) root <- args[i + 1]
}
if (!dir.exists(root)) stop('output root does not exist: ', root, call. = FALSE)

# ---- layout detection -------------------------------------------------------
rds_files <- list.files(root, pattern = '^snapshot_.*\\.rds$')
snaps_dir <- NULL
if (length(rds_files) > 0) {
  layout <- 'rds'
} else {
  for (cand in c(file.path(root, 'actual', 'snapshots'),
                 file.path(root, 'snapshots'),
                 root)) {
    if (length(list.files(cand, pattern = '^valid_from=')) > 0) {
      snaps_dir <- cand
      break
    }
  }
  if (is.null(snaps_dir)) {
    stop('no build found under ', root,
         ': neither snapshot_*.rds nor a snapshots/valid_from=* parquet layout',
         call. = FALSE)
  }
  layout <- 'vintage'
}
message('verify_build: root = ', root, ' (layout: ', layout, ')')

# ---- layout-aware loaders ---------------------------------------------------
SANITY_COLS <- c('country', 'hts10', 's232_annex', 'rate_232', 'heading_program')

# The snapshots dir holds non-parquet siblings (metadata.rds), so open the
# parquet files explicitly rather than the directory. valid_from/valid_until/
# revision are real columns in each file — no Hive inference needed.
snaps_ds <- function() {
  files <- list.files(snaps_dir, pattern = '\\.parquet$',
                      recursive = TRUE, full.names = TRUE)
  if (length(files) == 0) stop('no parquet snapshots under ', snaps_dir, call. = FALSE)
  open_dataset(files)
}

rev_present <- function(rev) {
  if (layout == 'rds') {
    file.exists(file.path(root, paste0('snapshot_', rev, '.rds')))
  } else {
    nrow(snaps_ds() %>%
           filter(revision == rev) %>% head(1) %>% collect()) > 0
  }
}

# One revision's rows, projected to the sanity columns (pushed down for parquet).
load_rev <- function(rev) {
  if (layout == 'rds') {
    p <- file.path(root, paste0('snapshot_', rev, '.rds'))
    if (!file.exists(p)) return(NULL)
    s <- readRDS(p)
    s[, intersect(SANITY_COLS, names(s)), drop = FALSE]
  } else {
    s <- snaps_ds() %>%
      filter(revision == rev) %>%
      select(any_of(SANITY_COLS)) %>%
      collect()
    if (nrow(s) == 0) NULL else s
  }
}

panel_na_intervals <- function() {
  ds <- if (layout == 'rds') {
    p <- file.path(root, 'rate_timeseries.parquet')
    if (!file.exists(p)) stop('panel not found: ', p, call. = FALSE)
    open_dataset(p)
  } else {
    snaps_ds()
  }
  (ds %>% filter(is.na(valid_from) | is.na(valid_until)) %>%
     count() %>% collect())$n
}

# ---- check harness ----------------------------------------------------------
results <- list()
check <- function(name, expr) {
  ok <- tryCatch(isTRUE(expr),
                 error = function(e) {
                   message('    error: ', conditionMessage(e))
                   FALSE
                 })
  message(sprintf('  %s: %s', if (ok) 'PASS' else 'FAIL', name))
  results[[name]] <<- ok
  invisible(ok)
}

# ---- 1. rate-calculation test suite -----------------------------------------
if (skip_tests) {
  message('>>> test suite: SKIPPED (--skip-tests)')
} else {
  message('>>> tests/test_rate_calculation.R')
  rc <- system2('Rscript', shQuote(here('tests', 'test_rate_calculation.R')))
  check('rate-calculation test suite exits 0', rc == 0L)
}

# ---- 2. Russia rev_5 sanity (mhd strip) --------------------------------------
message('>>> Russia rev_5 sanity checks')
rev5 <- load_rev('2026_rev_5')
check('rev_5 snapshot present', !is.null(rev5))
if (!is.null(rev5)) {
  check('heading_program column present', 'heading_program' %in% names(rev5))

  ru <- rev5 %>% filter(country == '4621')
  springs <- ru %>% filter(substr(hts10, 1, 4) == '7320', s232_annex == 'annex_1a')
  message('    Russia 7320.x annex_1a rows: ', nrow(springs),
          ' | rate_232 range: ',
          if (nrow(springs)) paste(range(springs$rate_232), collapse = '-') else 'NA')
  check('Russia 7320.x annex_1a springs rate_232 == 0.50',
        nrow(springs) > 0 && all(abs(springs$rate_232 - 0.50) < 1e-9))

  towers <- ru %>% filter(substr(hts10, 1, 6) == '730820')
  message('    Russia 7308.20 rows: ', nrow(towers),
          ' | max rate_232: ', if (nrow(towers)) max(towers$rate_232) else NA)
  check('Russia 7308.20 aluminum derivative still 2.0',
        nrow(towers) > 0 && any(abs(towers$rate_232 - 2.0) < 1e-9))

  if ('heading_program' %in% names(rev5)) {
    leak <- rev5 %>% filter(s232_annex == 'annex_2', rate_232 > 0, !heading_program)
    message('    annex_2 non-heading-program leak rows: ', nrow(leak))
    check('annex_2 non-heading-program leak rows == 0', nrow(leak) == 0)
  }
}

# ---- 3. rev_10 / Annex I-C sanity --------------------------------------------
message('>>> rev_10 / Annex I-C sanity checks')
rev10 <- load_rev('2026_rev_10')
check('rev_10 snapshot present', !is.null(rev10))
if (!is.null(rev10)) {
  cxi <- rev10 %>% filter(s232_annex == 'annex_1c')
  message('    annex_1c rows: ', nrow(cxi),
          ' | distinct hts10: ', n_distinct(cxi$hts10),
          ' | rate_232 range: ',
          if (nrow(cxi)) paste(range(cxi$rate_232), collapse = '-') else 'NA')
  check('annex_1c rows present with rate_232 >= 0.15 framework floor',
        nrow(cxi) > 0 && all(cxi$rate_232 >= 0.15 - 1e-9))
  check('annex_1c 0.25 default rate present',
        nrow(cxi) > 0 && any(abs(cxi$rate_232 - 0.25) < 1e-9))
}
check('bnd_2026-06-08 NOT re-minted (superseded by rev_10)',
      !rev_present('bnd_2026-06-08'))

# ---- 4. panel interval integrity ---------------------------------------------
message('>>> panel interval integrity')
na_n <- tryCatch(panel_na_intervals(), error = function(e) {
  message('    error: ', conditionMessage(e))
  NA_integer_
})
message('    panel rows with NA valid_from/valid_until: ', na_n)
check('panel has zero NA-interval rows', !is.na(na_n) && na_n == 0)

# ---- summary -----------------------------------------------------------------
n_fail <- sum(!unlist(results))
message('==========================================================')
message('verify_build: ', length(results) - n_fail, ' passed, ', n_fail,
        ' failed (root: ', root, ')')
message('==========================================================')
if (n_fail > 0) quit(status = 1L)
