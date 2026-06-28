suppressMessages({library(dplyr); library(jsonlite)})

# Optional: Rscript gen_v4.R rev_8        -> only process that revision
# Optional: Rscript gen_v4.R rev_8 rev_9  -> process multiple revisions
only_revs <- commandArgs(trailingOnly=TRUE)

codes <- read.csv('/Users/stefanliew/Documents/Claude/Budget-Lab-Yale/tariff-rate-tracker/resources/census_codes.csv', colClasses='character')
names(codes) <- c('country','country_name')

rev_dates <- read.csv('/Users/stefanliew/Documents/Claude/Budget-Lab-Yale/tariff-rate-tracker/config/revision_dates.csv',
                      colClasses='character', na.strings=c('NA',''))
# policy_effective_date: use policy_effective_date if present, else effective_date
rev_ped <- ifelse(!is.na(rev_dates$policy_effective_date), rev_dates$policy_effective_date, rev_dates$effective_date)
names(rev_ped) <- rev_dates$revision

s232_cols <- c('rate_232_steel','rate_232_aluminum','rate_232_copper','rate_232_autos',
  'rate_232_auto_parts','rate_232_mhd_vehicles','rate_232_mhd_parts','rate_232_buses',
  'rate_232_softwood','rate_232_wood_furniture','rate_232_kitchen_cabinets',
  'rate_232_semiconductors','rate_232_pharmaceuticals')
other_rate_cols <- c('rate_301','rate_ieepa_recip','rate_ieepa_fent','rate_s122','rate_section_201','rate_other')
other_stat_cols <- c('statutory_rate_301','statutory_rate_ieepa_recip','statutory_rate_ieepa_fent',
  'statutory_rate_s122','statutory_rate_section_201','statutory_rate_other')

# Census codes
UK<-'4120'; JP<-'5880'; KR<-'5800'; TW<-'5830'
EU<-c('4330','4231','4870','4791','4910','4351','4099','4470','4050','4279','4280',
      '4840','4370','4190','4759','4490','4510','4239','4730','4210','4550','4710',
      '4850','4359','4792','4700','4010')

# Effective-date thresholds (snapshot effective_date based) for framework deals
D_UK_AUTO   <- '2025-07-01'   # rev_16
D_JP_AUTO   <- '2025-09-16'   # rev_23
D_EU_AUTO   <- '2025-09-25'   # rev_24
D_KR_AUTO   <- '2025-12-05'   # rev_32
D_TW_PARTS  <- '2026-05-01'   # 2026_rev_9 (parts only; TW has no vehicle deal)
D_WOOD_JPEU <- '2025-10-14'   # rev_25
D_WOOD_KR   <- '2025-12-05'   # rev_32
D_WOOD_TW   <- '2026-05-01'   # 2026_rev_9
D_PARTS_START <- '2025-05-03' # rev_11: auto-parts 232 real start (gates pre-rev_11 noise)
D_RECIP_COUNTRY <- '2025-04-09' # Phase 1 country-specific reciprocal ladder effective date.
D_RECIP_PHASE2  <- '2025-08-07' # Phase 2: country-specific reciprocal rates return for all.
RECIP_BASELINE  <- 0.10
CHINA_GROUP     <- c('5700','5820','5660')  # China, Hong Kong, Macao — NOT suspended
# Phase 1 reciprocal cap. On Apr 9 the country ladder took effect for ~hours, then the
# 90-day pause suspended it for everyone EXCEPT China/HK/Macao (reverting them to the 10%
# baseline through Phase 1). So:
#   - before Apr 9 (rev_7, Apr 5): ladder not yet effective -> cap ALL to baseline
#     (corrects the upstream rev_7 leak: extract_effective_date_offset() misses the
#     in-transit "before Apr 9" phrasing, so Lesotho/China-group leak the Apr-9 rate early).
#   - Apr 9 .. Phase 2 (rev_8 .. rev_17): suspended -> cap NON-China-group to baseline
#     (corrects the rev_8 Lesotho leak; China-group keep their real escalation 0.84->1.25->0.10).
D_PHARMA    <- '2026-09-29'   # pharma 232 turn-on (config effective_date)
CHE<-'4419'; LIE<-'4411'      # Switzerland, Liechtenstein

# Fixed-rate 232 programs (no country variation, no cross-revision change).
# `start` = program effective date; gates out pre-start leakage in the split
# columns (copper-content / steel-content artifacts, auto-program overlap).
# NA = rely on presence check alone (already clean: softwood, semiconductors).
fixed_232 <- list(
  rate_232_copper          = list(name='copper',           rate=0.50, start='2025-08-01'),  # rev_17
  rate_232_mhd_vehicles    = list(name='mhd_vehicles',     rate=0.25, start='2025-11-01'),  # rev_26
  rate_232_mhd_parts       = list(name='mhd_parts',        rate=0.25, start='2025-11-01'),  # rev_26
  rate_232_buses           = list(name='buses',            rate=0.10, start='2025-11-01'),  # rev_26
  rate_232_softwood        = list(name='softwood_lumber',  rate=0.10, start=NA),            # rev_25, clean
  rate_232_semiconductors  = list(name='semiconductors',   rate=0.25, start=NA)             # 2026_rev_1, clean
)
other_meta <- list(
  rate_301         = list(authority='s301',  name='china_301',       stat='statutory_rate_301'),
  rate_ieepa_recip = list(authority='ieepa', name='reciprocal',      stat='statutory_rate_ieepa_recip'),
  rate_ieepa_fent  = list(authority='ieepa', name='fentanyl',        stat='statutory_rate_ieepa_fent'),
  rate_s122        = list(authority='s122',  name='section_122',     stat='statutory_rate_s122'),
  rate_other       = list(authority='other', name='other',           stat='statutory_rate_other')
)

snap_dir <- '/Users/stefanliew/Documents/Claude/Budget-Lab-Yale/tariff-rate-tracker/data/timeseries/forced_labor_0801/split_232'
out_dir  <- '/Users/stefanliew/Documents/Claude/Budget-Lab-Yale/tariff-rate-tracker/data/statutory_rates'
files <- list.files(snap_dir, pattern='^snapshot_.*\\.rds$', full.names=TRUE)
if (length(only_revs) > 0) {
  files <- files[sub('.*snapshot_(.+)\\.rds$','\\1', files) %in% only_revs]
  if (length(files) == 0) stop('No matching snapshots found for: ', paste(only_revs, collapse=', '))
}

add <- function(lst, auth, nm, rt) { lst[[length(lst)+1]] <- list(tariff_authority=auth, tariff_name=nm, tariff_rate=rt); lst }

for (f in files) {
  rev <- sub('.*snapshot_(.+)\\.rds$','\\1', f)
  snap <- readRDS(f)
  eff <- as.character(max(snap$effective_date, na.rm=TRUE))   # ISO date; lexical compare OK

  # Dynamic steel/aluminum statutory rates (exclude Russia surcharge)
  steel_tbl <- snap %>% filter(country!='4621', grepl('^72|^73', hts10), statutory_rate_232>0) %>%
    group_by(country) %>% summarise(rate=max(statutory_rate_232), .groups='drop')
  alum_tbl  <- snap %>% filter(country!='4621', grepl('^76', hts10), statutory_rate_232>0) %>%
    group_by(country) %>% summarise(rate=max(statutory_rate_232), .groups='drop')
  steel_by_ctry <- setNames(steel_tbl$rate, steel_tbl$country)
  alum_by_ctry  <- setNames(alum_tbl$rate,  alum_tbl$country)

  # Section 201 SOLAR safeguard only (CSPV cells/modules, HTS 8541.42/8541.43).
  # The §201-range bucket (9903.40-45) also holds dormant country-specific 301
  # retaliation lists (Japan leather/footwear 40%, China tires 25%) that we
  # deliberately DROP — so we read solar straight from the solar HTS rather than
  # max() over the whole bucket. Rate is the config step-down (~14.5%).
  solar_tbl <- snap %>% filter(grepl('^854142|^854143', hts10), statutory_rate_section_201>0) %>%
    group_by(country) %>% summarise(solar=max(statutory_rate_section_201), .groups='drop')
  solar_rate <- setNames(solar_tbl$solar, solar_tbl$country)

  agg <- snap %>% group_by(country) %>%
    summarise(across(all_of(c(s232_cols, other_rate_cols, other_stat_cols)), max, na.rm=TRUE), .groups='drop') %>%
    left_join(codes, by='country')

  # policy_effective_date: bnd_ files use the date in the rev name; others from CSV
  ped <- if (grepl('^bnd_', rev)) sub('^bnd_', '', rev) else unname(rev_ped[rev])

  result <- vector('list', nrow(agg))
  for (i in seq_len(nrow(agg))) {
    row <- agg[i,,drop=FALSE]; ctry <- as.character(row$country)
    cname <- if(!is.na(row$country_name)) row$country_name else paste('Census', ctry)
    is_eu <- ctry %in% EU
    t <- list()

    # Steel / aluminum (dynamic, per-country — UK has its own rate under the UK-US deal)
    steel_stat <- if (!is.null(steel_by_ctry[ctry]) && !is.na(steel_by_ctry[ctry])) steel_by_ctry[[ctry]] else 0
    alum_stat  <- if (!is.null(alum_by_ctry[ctry])  && !is.na(alum_by_ctry[ctry]))  alum_by_ctry[[ctry]]  else 0
    if (!is.na(row$rate_232_steel)    && row$rate_232_steel>0    && steel_stat>0) t <- add(t,'s232','steel',steel_stat)
    if (!is.na(row$rate_232_aluminum) && row$rate_232_aluminum>0 && alum_stat>0)  t <- add(t,'s232','aluminum',alum_stat)

    # Fixed-rate 232 programs (with per-program effective-date gate vs leakage)
    for (col in names(fixed_232)) {
      v <- as.numeric(row[[col]]); info <- fixed_232[[col]]
      gate_ok <- is.na(info$start) || eff >= info$start
      if (!is.na(v) && v>0 && info$rate>0 && gate_ok) t <- add(t,'s232',info$name,info$rate)
    }

    # AUTOS framework: UK 10% all-in; JP/EU/KR 15%; else 25% (TW = 25%, no vehicle deal)
    if (!is.na(row$rate_232_autos) && row$rate_232_autos>0) {
      arate <- 0.25
      if (ctry==UK && eff>=D_UK_AUTO) arate <- 0.10
      else if (ctry==JP && eff>=D_JP_AUTO) arate <- 0.15
      else if (is_eu  && eff>=D_EU_AUTO) arate <- 0.15
      else if (ctry==KR && eff>=D_KR_AUTO) arate <- 0.15
      t <- add(t,'s232','autos',arate)
    }

    # AUTO PARTS framework (gated to real program start 2025-05-03): UK 10%; JP/EU/KR/TW 15%; else 25%
    if (!is.na(row$rate_232_auto_parts) && row$rate_232_auto_parts>0 && eff>=D_PARTS_START) {
      prate <- 0.25
      if (ctry==UK && eff>=D_UK_AUTO) prate <- 0.10
      else if (ctry==JP && eff>=D_JP_AUTO) prate <- 0.15
      else if (is_eu  && eff>=D_EU_AUTO) prate <- 0.15
      else if (ctry==KR && eff>=D_KR_AUTO) prate <- 0.15
      else if (ctry==TW && eff>=D_TW_PARTS) prate <- 0.15
      t <- add(t,'s232','auto_parts',prate)
    }

    # WOOD furniture & kitchen cabinets: 15% for framework countries, else 25%
    wood_fw <- (is_eu && eff>=D_WOOD_JPEU) || (ctry==JP && eff>=D_WOOD_JPEU) ||
               (ctry==KR && eff>=D_WOOD_KR) || (ctry==TW && eff>=D_WOOD_TW)
    if (!is.na(row$rate_232_wood_furniture)   && row$rate_232_wood_furniture>0)   t <- add(t,'s232','wood_furniture',   if(wood_fw)0.15 else 0.25)
    if (!is.na(row$rate_232_kitchen_cabinets) && row$rate_232_kitchen_cabinets>0) t <- add(t,'s232','kitchen_cabinets', if(wood_fw)0.15 else 0.25)

    # PHARMA framework (effective 2026-09-29): default 100% target; JP/EU/KR/CHE/LIE 15%; UK 10% surcharge
    if (!is.na(row$rate_232_pharmaceuticals) && row$rate_232_pharmaceuticals>0 && eff>=D_PHARMA) {
      phrate <- 1.00
      if (ctry==UK) phrate <- 0.10
      else if (ctry==JP || is_eu || ctry==KR || ctry==CHE || ctry==LIE) phrate <- 0.15
      t <- add(t,'s232','pharmaceuticals',phrate)
    }

    # Other authorities (statutory)
    for (col in names(other_meta)) {
      e <- as.numeric(row[[col]]); s <- as.numeric(row[[other_meta[[col]]$stat]]); info <- other_meta[[col]]
      # Cap reciprocal during the Phase 1 suspension (see CHINA_GROUP note above).
      if (col == 'rate_ieepa_recip' && !is.na(s) && s > RECIP_BASELINE) {
        if (eff < D_RECIP_COUNTRY) {
          s <- RECIP_BASELINE                                   # pre-Apr-9: all countries
        } else if (eff < D_RECIP_PHASE2 && !(ctry %in% CHINA_GROUP)) {
          s <- RECIP_BASELINE                                   # Apr-9..Phase2: non-China-group
        }
      }
      if (!is.na(e) && e>0 && !is.na(s) && s>0) t <- add(t,info$authority,info$name,s)
    }

    result[[i]] <- list(name=cname, census_code=ctry, tariffs=t)
  }
  names(result) <- agg$country
  out <- c(list(policy_effective_date=ped), result)
  write(toJSON(out, pretty=TRUE, auto_unbox=TRUE), file.path(out_dir, paste0('tariff_rates_',rev,'.json')))
  modal_steel <- if(length(steel_by_ctry)) max(steel_by_ctry) else 0
  modal_alum  <- if(length(alum_by_ctry))  max(alum_by_ctry)  else 0
  cat(sprintf('%-16s eff=%s steel=%.2f alum=%.2f\n', rev, eff, modal_steel, modal_alum))
}
cat('All done.\n')
