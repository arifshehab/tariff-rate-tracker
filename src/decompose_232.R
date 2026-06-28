# Decompose the combined rate_232 into per-program columns ("split_232").
#
# Reads each existing snapshot in data/timeseries/, adds 13 per-program 232
# columns plus two residual buckets (rate_232_metals_unspecified,
# rate_232_other), and writes the augmented snapshot to
# data/timeseries/split_232/. The ORIGINAL snapshots are never modified.
#
# Taxonomy (user choice): unified steel/aluminum/copper across the whole series;
# in the 2026 annex era the metal contribution is attributed by HS chapter
# (72/73 -> steel, 76 -> aluminum, 74 -> copper). Heading programs (autos,
# auto_parts, mhd_vehicles, mhd_parts, buses, softwood, wood_furniture,
# kitchen_cabinets, semiconductors, pharmaceuticals) are matched by their
# config prefixes / resource product lists.
#
# Attribution is a deterministic weight split, normalized so the per-program
# columns sum EXACTLY to rate_232. Weights:
#   - metals: metal share if present (derivatives), else 1 if HS chapter matches
#   - headings: 1 if the HS10 matches the program's prefixes/list
#   - annex-flagged but metal unresolved -> rate_232_metals_unspecified
#   - anything else unattributed (rate_232>0, not annex) -> rate_232_other
#
# Multi-metal derivative blends (both steel_share & aluminum_share > 0) are split
# share-proportionally; this is exact when the per-metal rates are equal (annex
# era, mid-2025+) and a close approximation in early-2025 (steel 25% / alu 10%).
# This affects a tiny share of value (see docs note) and always reconciles.

suppressMessages({
  library(here)
  library(tidyverse)
  library(yaml)
})

PROGRAMS <- c('steel', 'aluminum', 'copper', 'autos', 'auto_parts',
              'mhd_vehicles', 'mhd_parts', 'buses', 'softwood', 'wood_furniture',
              'kitchen_cabinets', 'semiconductors', 'pharmaceuticals')

# ---- Membership sources ----
pp_raw <- yaml::read_yaml(here('config', 'policy_params.yaml'))
hd <- pp_raw$section_232_headings
pat <- function(prefixes) if (length(prefixes)) paste0('^(', paste(prefixes, collapse = '|'), ')') else '^$'
autos_pat  <- pat(c(hd$autos_passenger$prefixes, hd$autos_light_trucks$prefixes))
mhdv_pat   <- pat(hd$mhd_vehicles$prefixes)
soft_pat   <- pat(hd$softwood$prefixes)
wfurn_pat  <- pat(hd$wood_furniture$prefixes)
kcab_pat   <- pat(hd$kitchen_cabinets$prefixes)
buses_pat  <- pat(hd$buses$prefixes)
auto_parts <- trimws(readLines(here('resources', 's232_auto_parts.txt'))); auto_parts <- auto_parts[auto_parts != '']
mhd_parts  <- trimws(readLines(here('resources', 's232_mhd_parts.txt')));  mhd_parts  <- mhd_parts[mhd_parts != '']
semi_codes <- as.character(read_csv(here('resources', 's232_semi_products.csv'), show_col_types = FALSE)[[1]])
pharma_codes <- as.character(read_csv(here('resources', 's232_pharma_products.csv'), show_col_types = FALSE)[[1]])

# Annex product -> metal_type (steel/aluminum/copper). Authoritative metal
# identity for the 2026 annex regime, which spans many HS chapters (72-95), so
# chapter alone is insufficient. Prefixes vary in length (8 and 10 digit); match
# the longest prefix first.
annex_tbl <- read_csv(here('resources', 's232_annex_products.csv'), show_col_types = FALSE) %>%
  transmute(prefix = as.character(hts_prefix), metal_type = tolower(metal_type)) %>%
  filter(!is.na(prefix), prefix != '') %>%
  distinct(prefix, .keep_all = TRUE)
annex_lens <- sort(unique(nchar(annex_tbl$prefix)), decreasing = TRUE)
annex_metal_lookup <- function(hts10) {
  out <- rep(NA_character_, length(hts10))
  for (L in annex_lens) {
    tb <- annex_tbl[nchar(annex_tbl$prefix) == L, ]
    m <- tb$metal_type[match(substr(hts10, 1, L), tb$prefix)]
    fill <- is.na(out) & !is.na(m)
    out[fill] <- m[fill]
  }
  out
}

#' Add per-program 232 columns to one snapshot (vectorized).
decompose_232 <- function(snap) {
  n   <- nrow(snap)
  ch  <- substr(snap$hts10, 1, 2)
  rate <- coalesce(snap$rate_232, 0)
  pos <- rate > 0
  ss  <- coalesce(snap$steel_share, 0)
  al  <- coalesce(snap$aluminum_share, 0)
  cu  <- coalesce(snap$copper_share, 0)
  ich <- coalesce(snap$is_copper_heading, FALSE)
  annex <- if ('s232_annex' %in% names(snap)) !is.na(snap$s232_annex) else rep(FALSE, n)
  amt <- annex_metal_lookup(snap$hts10)   # 'steel'/'aluminum'/'copper'/NA

  W <- matrix(0, nrow = n, ncol = length(PROGRAMS), dimnames = list(NULL, PROGRAMS))
  # Metals, in priority order:
  #   1. derivative metal share (steel_share/aluminum_share/copper_share)
  #   2. annex metal_type (authoritative for the 2026 annex regime, any chapter)
  #   3. HS chapter (covers pre-annex 2025 primary metals: 72/73, 76, 74)
  W[, 'steel']    <- ifelse(ss > 0, ss,
                      ifelse(coalesce(amt == 'steel', FALSE), 1,
                      ifelse(is.na(amt) & ch %in% c('72', '73'), 1, 0)))
  W[, 'aluminum'] <- ifelse(al > 0, al,
                      ifelse(coalesce(amt == 'aluminum', FALSE), 1,
                      ifelse(is.na(amt) & ch == '76', 1, 0)))
  W[, 'copper']   <- ifelse(cu > 0, cu,
                      ifelse(coalesce(amt == 'copper', FALSE), 1,
                      ifelse(is.na(amt) & (ch == '74' | ich), 1, 0)))
  # Heading programs
  W[, 'autos']            <- as.numeric(grepl(autos_pat, snap$hts10))
  W[, 'mhd_vehicles']     <- as.numeric(grepl(mhdv_pat, snap$hts10))
  W[, 'buses']            <- as.numeric(grepl(buses_pat, snap$hts10))
  W[, 'softwood']         <- as.numeric(grepl(soft_pat, snap$hts10))
  W[, 'wood_furniture']   <- as.numeric(grepl(wfurn_pat, snap$hts10))
  W[, 'kitchen_cabinets'] <- as.numeric(grepl(kcab_pat, snap$hts10))
  # annex_1b chapter 94 codes not matched by the prefix lists above fall into
  # metals_unspecified because they carry no metal shares. Attribute them here:
  # kitchen_cabinets gets priority (kcab_pat already set); everything else is
  # wood_furniture. Covers the expanded product universe in post-rev_9 snapshots
  # where the upholstered-seat codes dropped to zero and broader 9401/9403/9406
  # furniture parts became the active annex_1b carriers.
  annex_1b_ch94 <- !is.na(snap$s232_annex) & snap$s232_annex == 'annex_1b' & ch == '94'
  W[annex_1b_ch94 & W[, 'kitchen_cabinets'] == 0, 'wood_furniture'] <- 1
  W[, 'auto_parts']       <- as.numeric(snap$hts10 %in% auto_parts)
  W[, 'mhd_parts']        <- as.numeric(snap$hts10 %in% mhd_parts)
  # Pharma (eff. 2026-09-29) and semiconductors (eff. 2026-01-16) are date-gated:
  # their product lists overlap with annex chemicals/electronics that carry a 232
  # rate from OTHER programs before activation, so membership must be time-gated
  # to avoid mis-claiming that rate. Snapshot carries effective_date.
  eff <- as.Date(snap$effective_date)
  semi_active   <- !is.na(eff) & eff >= as.Date('2026-01-16')
  pharma_active <- !is.na(eff) & eff >= as.Date('2026-09-29')
  W[, 'semiconductors']   <- as.numeric(snap$hts10 %in% semi_codes & semi_active)
  W[, 'pharmaceuticals']  <- as.numeric(snap$hts10 %in% pharma_codes & pharma_active)

  # Only attribute where there's a positive 232 rate
  W[!pos, ] <- 0
  sumW <- rowSums(W)

  # Normalize weights to split rate_232 exactly across the named programs
  prop <- W
  has <- sumW > 0
  prop[has, ] <- W[has, ] / sumW[has]
  attributed <- prop * rate          # n x 13, sums to rate where has==TRUE

  # Residual (no named program matched), split into two honest buckets:
  #   - metals_unspecified: the product IS flagged as an annex metals product in
  #     the snapshot (s232_annex set) but its metal type couldn't be resolved
  #     (not in the metal_type resource file, not a metal HS chapter). It's a
  #     232 metals duty of unknown metal.
  #   - other: genuinely unsourced (not annex, no metal share, no heading match).
  unattributed     <- pos & !has
  metals_unspec    <- ifelse(unattributed & annex, rate, 0)
  other            <- ifelse(unattributed & !annex, rate, 0)

  for (p in PROGRAMS) snap[[paste0('rate_232_', p)]] <- attributed[, p]
  snap[['rate_232_metals_unspecified']] <- metals_unspec
  snap[['rate_232_other']] <- other
  snap
}

# ---- Driver ----
# Usage:
#   Rscript src/decompose_232.R [src_dir] [out_dir]
#     src_dir  directory of snapshot_*.rds to decompose
#              (default: data/timeseries/)
#     out_dir  where to write augmented snapshots
#              (default: <src_dir>/split_232/)
# Examples:
#   Rscript src/decompose_232.R                                    # baseline
#   Rscript src/decompose_232.R data/timeseries/new_301           # a scenario
#   Rscript src/decompose_232.R data/timeseries/new_301 out/foo   # explicit dest
if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  src_dir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else here('data', 'timeseries')
  out_dir <- if (length(args) >= 2 && nzchar(args[2])) args[2] else file.path(src_dir, 'split_232')
  if (!dir.exists(src_dir)) stop('Source snapshot dir not found: ', src_dir)
  if (normalizePath(out_dir, mustWork = FALSE) == normalizePath(src_dir, mustWork = FALSE)) {
    stop('out_dir must differ from src_dir (refusing to overwrite source snapshots): ', src_dir)
  }
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  # Non-recursive: only snapshots directly in src_dir (not the split_232 subdir).
  snaps <- list.files(src_dir, pattern = '^snapshot_.*\\.rds$')
  message('Decomposing 232 for ', length(snaps), ' snapshots -> ', out_dir)
  max_resid <- 0
  for (i in seq_along(snaps)) {
    s <- readRDS(file.path(src_dir, snaps[i]))
    s <- decompose_232(s)
    # Reconciliation check: per-program + metals_unspecified + other == rate_232
    prog_cols <- c(paste0('rate_232_', PROGRAMS), 'rate_232_metals_unspecified', 'rate_232_other')
    chk <- max(abs(rowSums(as.matrix(s[, prog_cols])) - coalesce(s$rate_232, 0)))
    max_resid <- max(max_resid, chk)
    saveRDS(s, file.path(out_dir, snaps[i]))
    message(sprintf('  [%2d/%2d] %s  (reconcile max diff %.2e)', i, length(snaps), snaps[i], chk))
  }
  message('Done. Worst reconciliation diff across all snapshots: ', format(max_resid, scientific = TRUE))
}
