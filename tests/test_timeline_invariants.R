# =============================================================================
# Tests: timeline statute invariants (unified timeline / P2-1)
# =============================================================================
# ABSOLUTE assertions on the rate state at specific dates — the kind parity vs the
# OLD golden cannot make, because the unified-timeline mints CHANGE the intervals
# they touch. Mirrors the style of tests/test_rate_calculation.R: reads the built
# snapshot_*.rds (real + bnd_) in data/timeseries and reconstructs which snapshot
# is in force on a query date from rev_dates + the bnd_ ids. SKIPS cleanly when the
# build artifacts (esp. the bnd_ snapshots) are absent.
#
# What the mints fix (verified on the production policy grid):
#   1. §232 metal country-exemption expiry 2025-03-12 (bnd, owner rev_4): CA/EU
#      steel jump 0 -> 25% on 03-12, not at the next revision (03-14).            [IN-WINDOW]
#   2. IEEPA invalidation 2026-02-20 (bnd, owner 2026_rev_3): reciprocal+fentanyl
#      zero on 02-20, not at 2026_rev_4 (02-24).                                  [out-of-window]
#   3. The genuine 4-day [02-20, 02-23] window where IEEPA AND S122 are both 0
#      (S122 starts 02-24). Deliberate; documented (risk R2).
#   4. §301 cranes/chassis (9903.91.12-.16) turn ON 2026-11-10 (bnd, owner
#      2026_rev_9) — previously masked forever by filter_active_ch99.            [out-of-window]
#   5. POSITIVE CONTROLS: §232 annex (2026-04-06) and auto-parts/Phase-1 dates sit
#      ON real revision edges => NO spurious bnd_ split.
#
# Usage: Rscript tests/test_timeline_invariants.R
# =============================================================================

suppressPackageStartupMessages({ library(here); library(dplyr) })
source(here('src', 'helpers.R'))

pass <- 0L; skip <- 0L
check <- function(cond, msg) {
  if (!isTRUE(cond)) stop('FAILED: ', msg, call. = FALSE)
  pass <<- pass + 1L; cat('  ok:', msg, '\n')
}
skip_all <- function(reason) {
  cat('  SKIP (all): ', reason, '\n', sep = '')
  cat(sprintf('\n%d timeline-invariant assertions passed; SKIPPED (build artifacts absent)\n', pass))
  quit(save = 'no', status = 0)
}

snapshot_dir <- here('data', 'timeseries')
pp <- load_policy_params(use_policy_dates = TRUE)
rd <- load_revision_dates(use_policy_dates = TRUE)
horizon <- pp$SERIES_HORIZON_END

snap_files <- list.files(snapshot_dir, pattern = '^snapshot_.*\\.rds$')
if (length(snap_files) == 0) skip_all('no snapshot_*.rds in data/timeseries')
bnd_files <- grep('^snapshot_bnd_', snap_files, value = TRUE)
if (length(bnd_files) == 0)
  skip_all('no bnd_ snapshots yet — run a build with the unified-timeline mints first')

# --- Reconstruct the in-force interval table (real revs + minted bnd_ revs) ----
revs_built <- sub('^snapshot_(.*)\\.rds$', '\\1', snap_files)
real_tbl <- rd %>% filter(revision %in% revs_built) %>%
  transmute(revision, effective_date = as.Date(effective_date))
bnd_revs <- grep('^bnd_', revs_built, value = TRUE)
bnd_tbl <- tibble(revision = bnd_revs,
                  effective_date = as.Date(sub('^bnd_', '', bnd_revs)))
intervals <- bind_rows(real_tbl, bnd_tbl) %>%
  arrange(effective_date) %>%
  mutate(valid_from = effective_date,
         valid_until = lead(effective_date) - 1,
         valid_until = if_else(is.na(valid_until), horizon, valid_until))

active_rev_on <- function(D) {
  D <- as.Date(D)
  hit <- intervals %>% filter(valid_from <= D, D <= valid_until)
  if (nrow(hit) == 0) stop('no interval covers ', D)
  hit$revision[nrow(hit)]
}
snap_on <- function(D) {
  rev_id <- active_rev_on(D)
  readRDS(file.path(snapshot_dir, paste0('snapshot_', rev_id, '.rds'))) %>% enforce_rate_schema()
}
# rate_232 for a country's products in given HTS2 chapters
r232_chapter <- function(D, country, chapters) {
  s <- snap_on(D)
  s %>% filter(country == !!country, substr(hts10, 1, 2) %in% chapters) %>% pull(rate_232)
}

DE <- '4280'; CA <- '1220'  # Germany (EU), Canada

# --- (1) §232 metal country-exemption expiry: 0 on 03-11, 25% on 03-12 ---------
check(file.exists(file.path(snapshot_dir, 'snapshot_bnd_2025-03-12.rds')),
      'bnd_2025-03-12 snapshot exists (in-window §232 exemption mint)')
for (cc in list(c('CA', CA), c('EU/DE', DE))) {
  pre  <- r232_chapter('2025-03-11', cc[2], c('72', '73'))
  post <- r232_chapter('2025-03-12', cc[2], c('72', '73'))
  check(length(pre) > 0 && max(pre) == 0,
        paste0(cc[1], ' steel (ch72/73) rate_232 == 0 on 2025-03-11 (exemption active)'))
  check(length(post) > 0 && max(post) == 0.25,
        paste0(cc[1], ' steel (ch72/73) rate_232 == 0.25 on 2025-03-12 (exemption expired, not held to 03-14)'))
}

# --- POSITIVE CONTROL: §232 auto-parts / Phase-1 dates are real edges (no mint) -
for (edge in c('2025-05-03', '2025-04-09', '2026-04-06')) {
  check(!file.exists(file.path(snapshot_dir, paste0('snapshot_bnd_', edge, '.rds'))),
        paste0('no spurious bnd_ mint at the revision edge ', edge))
}
# Annex edge: 04-05 is the pre-annex regime, 04-06 the annex regime (different revs).
check(active_rev_on('2026-04-05') == '2026_rev_4' && active_rev_on('2026-04-06') == '2026_rev_5',
      '§232 annex edge: 2026-04-05 -> 2026_rev_4 (pre-annex), 2026-04-06 -> 2026_rev_5 (annex)')

# --- (2)+(3) IEEPA invalidation + the 4-day [02-20, 02-23] both-zero window -----
check(file.exists(file.path(snapshot_dir, 'snapshot_bnd_2026-02-20.rds')),
      'bnd_2026-02-20 snapshot exists (IEEPA invalidation mint)')
pre_inv <- snap_on('2026-02-19')
check(max(pre_inv$rate_ieepa_recip) > 0,
      'IEEPA reciprocal is LIVE on 2026-02-19 (before invalidation)')
inv <- snap_on('2026-02-20')
check(max(inv$rate_ieepa_recip) == 0 && max(inv$rate_ieepa_fent) == 0,
      'IEEPA reciprocal AND fentanyl == 0 on 2026-02-20 (invalidation)')
gap <- snap_on('2026-02-23')
check(max(gap$rate_ieepa_recip) == 0 && max(gap$rate_s122) == 0,
      'the 4-day gap: on 2026-02-23 BOTH IEEPA reciprocal and S122 are 0 (R2)')
s122_on <- snap_on('2026-02-24')
check(max(s122_on$rate_s122) > 0,
      'S122 turns on 2026-02-24 (rate_s122 > 0)')

# --- (4) §301 cranes/chassis turn ON 2026-11-10 (China) ------------------------
check(file.exists(file.path(snapshot_dir, 'snapshot_bnd_2026-11-10.rds')),
      'bnd_2026-11-10 snapshot exists (§301 cranes/chassis turn-on mint)')
china301_on <- function(D) {
  s <- snap_on(D)
  sum(s$rate_301[s$country == '5700'] > 0)
}
n_before <- china301_on('2026-11-09')
n_after  <- china301_on('2026-11-10')
check(n_after > n_before,
      sprintf('China §301 footprint grows on 2026-11-10 (%d -> %d products with rate_301 > 0)',
              n_before, n_after))

cat(sprintf('\nALL %d TIMELINE-INVARIANT ASSERTIONS PASSED (%d skipped)\n', pass, skip))
