suppressMessages({library(dplyr); library(jsonlite)})

# Generate statutory-rate JSON files from the `updated_232_logic` snapshots.
#
#   Rscript gen_updated.R              -> process `basic` only (default)
#   Rscript gen_updated.R rev_24       -> process a single revision
#   Rscript gen_updated.R rev_24 rev_32 2026_basic -> multiple revisions
#   Rscript gen_updated.R all          -> process every snapshot in the dir
#
# Most s232 statutory rates are read straight from the per-program
# `statutory_rate_232_*` columns in the snapshot (deal rates are baked in there
# now). The exceptions below CANNOT be recovered from the snapshot and are
# hardcoded:
#   - autos        : snapshot bakes in the US-content rebate (23.76%); we report
#                    the headline all-in deal rates instead.
#   - auto_parts   : snapshot is a flat 0.25 for every country; deal rates and
#                    the USMCA 0% for CA/MX are not encoded.
#   - pharma       : `statutory_rate_232_pharmaceuticals` is a product-weighted
#                    average, not the headline deal rate.
# MHD vehicles / MHD parts keep their snapshot rate but get a fixed comment
# (and CA/MX get a 0% USMCA override for parts).

args <- commandArgs(trailingOnly=TRUE)

base <- '/Users/stefanliew/Documents/Claude/Budget-Lab-Yale/tariff-rate-tracker'
snap_dir <- file.path(base, 'data/timeseries/updated_232_logic')
out_dir  <- file.path(base, 'data/statutory_rates/updated')
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)

codes <- read.csv(file.path(base, 'resources/census_codes.csv'), colClasses='character')
names(codes) <- c('country','country_name')

rev_dates <- read.csv(file.path(base, 'config/revision_dates.csv'),
                      colClasses='character', na.strings=c('NA',''))
rev_ped <- ifelse(!is.na(rev_dates$policy_effective_date),
                  rev_dates$policy_effective_date, rev_dates$effective_date)
names(rev_ped) <- rev_dates$revision

# ----- Census codes for deal / special-treatment countries --------------------
UK<-'4120'; JP<-'5880'; KR<-'5800'; TW<-'5830'; RU<-'4621'
CA<-'1220'; MX<-'2010'; CHE<-'4419'; LIE<-'4411'
EU<-c('4330','4231','4870','4791','4910','4351','4099','4470','4050','4279','4280',
      '4840','4370','4190','4759','4490','4510','4239','4730','4210','4550','4710',
      '4850','4359','4792','4700','4010')

# ----- Effective-date thresholds (snapshot effective_date based) ---------------
D_UK_AUTO   <- '2025-07-01'
D_JP_AUTO   <- '2025-09-16'
D_EU_AUTO   <- '2025-09-25'
D_KR_AUTO   <- '2025-12-05'
D_TW_PARTS  <- '2026-05-01'
D_PARTS_START <- '2025-05-03'   # auto-parts 232 real program start (gates noise)
D_PHARMA    <- '2026-09-29'     # pharma 232 turn-on

CMT_US_CONTENT <- 'US content is exempt'
CMT_USMCA      <- 'Applies to USMCA-compliant goods only'

# Per-program s232 statutory columns read straight from the snapshot.
# (autos / auto_parts / pharma are handled separately and excluded here.)
snapshot_232 <- list(
  rate_232_steel            = list(name='steel',            stat='statutory_rate_232_steel'),
  rate_232_aluminum         = list(name='aluminum',         stat='statutory_rate_232_aluminum'),
  rate_232_copper           = list(name='copper',           stat='statutory_rate_232_copper'),
  rate_232_buses            = list(name='buses',            stat='statutory_rate_232_buses'),
  rate_232_softwood         = list(name='softwood_lumber',  stat='statutory_rate_232_softwood'),
  rate_232_wood_furniture   = list(name='wood_furniture',   stat='statutory_rate_232_wood_furniture'),
  rate_232_kitchen_cabinets = list(name='kitchen_cabinets', stat='statutory_rate_232_kitchen_cabinets'),
  rate_232_semiconductors   = list(name='semiconductors',   stat='statutory_rate_232_semiconductors')
)

# Other authorities (statutory rate read straight from the snapshot).
other_meta <- list(
  rate_301         = list(authority='s301',  name='china_301',   stat='statutory_rate_301'),
  rate_ieepa_recip = list(authority='ieepa', name='reciprocal',  stat='statutory_rate_ieepa_recip'),
  rate_ieepa_fent  = list(authority='ieepa', name='fentanyl',    stat='statutory_rate_ieepa_fent'),
  rate_s122        = list(authority='s122',  name='section_122', stat='statutory_rate_s122'),
  rate_other       = list(authority='other', name='other',       stat='statutory_rate_other')
)

# Reciprocal Phase 1 suspension cap (kept as-is from gen_v4).
D_RECIP_COUNTRY <- '2025-04-09'
D_RECIP_PHASE2  <- '2025-08-07'
RECIP_BASELINE  <- 0.10
CHINA_GROUP     <- c('5700','5820','5660')   # China, HK, Macao — not suspended

stat_232_cols <- vapply(snapshot_232, function(x) x$stat, character(1))
rate_232_cols <- names(snapshot_232)
other_rate_cols <- names(other_meta)
other_stat_cols <- vapply(other_meta, function(x) x$stat, character(1))
# Extra columns needed for the hardcoded programs (presence gate).
extra_cols <- c('rate_232_autos','rate_232_auto_parts','rate_232_pharmaceuticals',
                'rate_232_mhd_vehicles','statutory_rate_232_mhd_vehicles',
                'rate_232_mhd_parts','statutory_rate_232_mhd_parts')

# ----- Select which snapshots to process --------------------------------------
files <- list.files(snap_dir, pattern='^snapshot_.*\\.rds$', full.names=TRUE)
rev_of <- function(f) sub('.*snapshot_(.+)\\.rds$','\\1', f)
if (length(args) == 0) {
  files <- files[rev_of(files) == 'basic']
} else if (!(length(args) == 1 && args[1] == 'all')) {
  files <- files[rev_of(files) %in% args]
  if (length(files) == 0) stop('No matching snapshots for: ', paste(args, collapse=', '))
}

# add a tariff entry; comment is optional (omitted when NULL/NA/"")
add <- function(lst, auth, nm, rt, comment=NULL) {
  entry <- list(tariff_authority=auth, tariff_name=nm, tariff_rate=rt)
  if (!is.null(comment) && !is.na(comment) && nzchar(comment)) entry$comment <- comment
  lst[[length(lst)+1]] <- entry
  lst
}

CMT_PARTIAL <- 'Does not apply to all products'

# Headline statutory rate = max over the per-HS10 rates that actually apply
# (value > 0); this is the core/program rate (derivative lines never exceed it).
# head_share = fraction of applicable lines that carry that headline rate; when
# it is below 0.5 the headline does not cover most products (comment flag).
head_val <- function(x) {
  x <- x[!is.na(x) & x > 0]
  if (!length(x)) return(0)
  max(x)
}
head_share <- function(x) {
  x <- x[!is.na(x) & x > 0]
  if (!length(x)) return(NA_real_)
  mean(x == max(x))
}

# Statutory columns aggregated by mode (+share); gate columns by presence (max).
stat_cols_all <- c(stat_232_cols, other_stat_cols,
                   'statutory_rate_232_mhd_vehicles', 'statutory_rate_232_mhd_parts')
gate_cols_all <- c(rate_232_cols, other_rate_cols,
                   'rate_232_autos', 'rate_232_auto_parts', 'rate_232_pharmaceuticals',
                   'rate_232_mhd_vehicles', 'rate_232_mhd_parts')

for (f in files) {
  rev <- rev_of(f)
  snap <- readRDS(f)
  eff <- as.character(max(snap$effective_date, na.rm=TRUE))   # ISO date; lexical compare OK

  gate_cols <- intersect(gate_cols_all, names(snap))
  stat_cols <- intersect(stat_cols_all, names(snap))
  agg <- snap %>% group_by(country) %>%
    summarise(across(all_of(gate_cols), \(x) max(x, na.rm=TRUE)),
              across(all_of(stat_cols), list(val=head_val, shr=head_share)),
              .groups='drop') %>%
    left_join(codes, by='country')

  ped <- if (grepl('^bnd_', rev)) sub('^bnd_', '', rev) else unname(rev_ped[rev])

  getv <- function(row, col) if (col %in% names(row)) as.numeric(row[[col]]) else NA_real_
  # statutory value/share: modal columns are named <stat>_val / <stat>_shr
  getstat <- function(row, stat) getv(row, paste0(stat, '_val'))
  partial_cmt <- function(row, stat) {
    shr <- getv(row, paste0(stat, '_shr'))
    if (!is.na(shr) && shr < 0.5) CMT_PARTIAL else NULL
  }

  result <- vector('list', nrow(agg))
  for (i in seq_len(nrow(agg))) {
    row <- agg[i,,drop=FALSE]; ctry <- as.character(row$country)
    cname <- if (!is.na(row$country_name)) row$country_name else paste('Census', ctry)
    is_eu <- ctry %in% EU
    t <- list()

    # --- s232 programs read straight from the snapshot ------------------------
    for (col in names(snapshot_232)) {
      info <- snapshot_232[[col]]
      applied <- getv(row, col); stat <- getstat(row, info$stat)
      if (!is.na(applied) && applied>0 && !is.na(stat) && stat>0) {
        cmt <- partial_cmt(row, info$stat)
        # UK metals stay at 25% under the EPD carve-out (covers core + derivatives).
        # The snapshot mislabels many UK aluminum derivative lines as 50%; force 25%.
        if (ctry==UK && info$name %in% c('steel','aluminum')) { stat <- 0.25; cmt <- NULL }
        # Russia has no Russia-specific 232 steel rate (FR 2026-06960 sets only
        # aluminum at 200%). ~178 steel-aluminum derivative lines carry the
        # Russian-aluminum 200% surcharge, inflating the steel max; cap at 0.50.
        if (ctry==RU && info$name=='steel' && stat>0.5) { stat <- 0.5; cmt <- NULL }
        t <- add(t, 's232', info$name, stat, cmt)
      }
    }

    # --- AUTOS (hardcoded all-in rates; US content exempt) --------------------
    if (!is.na(getv(row,'rate_232_autos')) && getv(row,'rate_232_autos')>0) {
      arate <- 0.25
      if (ctry==UK && eff>=D_UK_AUTO) arate <- 0.10
      else if (ctry==JP && eff>=D_JP_AUTO) arate <- 0.15
      else if (is_eu  && eff>=D_EU_AUTO) arate <- 0.15
      else if (ctry==KR && eff>=D_KR_AUTO) arate <- 0.15
      cmt <- if (ctry %in% c(CA, MX)) CMT_US_CONTENT else NULL
      t <- add(t, 's232', 'autos', arate, cmt)
    }

    # --- AUTO PARTS (hardcoded; CA/MX 0% USMCA) -------------------------------
    if (!is.na(getv(row,'rate_232_auto_parts')) && getv(row,'rate_232_auto_parts')>0 &&
        eff>=D_PARTS_START) {
      if (ctry %in% c(CA, MX)) {
        t <- add(t, 's232', 'auto_parts', 0, CMT_USMCA)
      } else {
        prate <- 0.25
        if (ctry==UK && eff>=D_UK_AUTO) prate <- 0.10
        else if (ctry==JP && eff>=D_JP_AUTO) prate <- 0.15
        else if (is_eu  && eff>=D_EU_AUTO) prate <- 0.15
        else if (ctry==KR && eff>=D_KR_AUTO) prate <- 0.15
        else if (ctry==TW && eff>=D_TW_PARTS) prate <- 0.15
        t <- add(t, 's232', 'auto_parts', prate)
      }
    }

    # --- MHD VEHICLES (snapshot rate; US content exempt) ---------------------
    mhdv_applied <- getv(row,'rate_232_mhd_vehicles'); mhdv_stat <- getstat(row,'statutory_rate_232_mhd_vehicles')
    if (!is.na(mhdv_applied) && mhdv_applied>0 && !is.na(mhdv_stat) && mhdv_stat>0) {
      cmt <- if (ctry %in% c(CA, MX)) CMT_US_CONTENT else partial_cmt(row,'statutory_rate_232_mhd_vehicles')
      t <- add(t, 's232', 'mhd_vehicles', mhdv_stat, cmt)
    }

    # --- MHD PARTS (snapshot rate; CA/MX 0% USMCA) ---------------------------
    mhdp_applied <- getv(row,'rate_232_mhd_parts'); mhdp_stat <- getstat(row,'statutory_rate_232_mhd_parts')
    if (!is.na(mhdp_applied) && mhdp_applied>0 && !is.na(mhdp_stat) && mhdp_stat>0) {
      if (ctry %in% c(CA, MX)) t <- add(t, 's232', 'mhd_parts', 0, CMT_USMCA)
      else                     t <- add(t, 's232', 'mhd_parts', mhdp_stat, partial_cmt(row,'statutory_rate_232_mhd_parts'))
    }

    # --- PHARMA (hardcoded; gated 2026-09-29) --------------------------------
    if (!is.na(getv(row,'rate_232_pharmaceuticals')) && getv(row,'rate_232_pharmaceuticals')>0 &&
        eff>=D_PHARMA) {
      phrate <- 1.00
      if (ctry==UK) phrate <- 0.10
      else if (ctry==JP || is_eu || ctry==KR || ctry==CHE || ctry==LIE) phrate <- 0.15
      t <- add(t, 's232', 'pharmaceuticals', phrate)
    }

    # --- Other authorities (statutory) ---------------------------------------
    for (col in names(other_meta)) {
      info <- other_meta[[col]]
      e <- getv(row, col); s <- getstat(row, info$stat); cmt <- partial_cmt(row, info$stat)
      if (col == 'rate_ieepa_recip' && !is.na(s) && s > RECIP_BASELINE) {
        if (eff < D_RECIP_COUNTRY) { s <- RECIP_BASELINE; cmt <- NULL }
        else if (eff < D_RECIP_PHASE2 && !(ctry %in% CHINA_GROUP)) { s <- RECIP_BASELINE; cmt <- NULL }
      }
      if (!is.na(e) && e>0 && !is.na(s) && s>0) t <- add(t, info$authority, info$name, s, cmt)
    }

    result[[i]] <- list(name=cname, census_code=ctry, tariffs=t)
  }
  names(result) <- agg$country
  out <- c(list(policy_effective_date=ped), result)
  write(toJSON(out, pretty=TRUE, auto_unbox=TRUE),
        file.path(out_dir, paste0('tariff_rates_', rev, '.json')))
  cat(sprintf('%-16s eff=%s -> %s\n', rev, eff, paste0('tariff_rates_', rev, '.json')))
}
cat('Done.\n')
