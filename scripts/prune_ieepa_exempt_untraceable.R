#!/usr/bin/env Rscript
# =============================================================================
# Prune untraceable entries from the IEEPA Annex II exempt list
# =============================================================================
#
# resources/ieepa_exempt_products.csv accumulated ~1,800 HTS10 codes with no
# basis in the printed U.S. note 2(v)(iii)(a) enumeration (verified directly
# against the chapter-99 PDF text of rev_19 (2025) and 2026_rev_9): the
# Tariff-ETRs ieepa_reciprocal.yaml merge (commit df1bf3b) and the subsequent
# full-rebuild expansion (01e8e76) imported every ETRs rate=0 line, which
# bundled three classes of non-Annex-II zeroing:
#
#   1. Residue with no legal basis found (turbine parts, diamonds, consumer
#      electronics, ...). CBP collections show no exemption claimed in
#      practice (e.g. 8479.89.95 Japan: ~19% collected vs the tracker's 3.6%).
#   2. Section 232 program members, zeroed by ETRs via EO 14257 §3(b)
#      ("232-covered articles are reciprocal-exempt"). The tracker models that
#      interplay through stacking instead: full-value 232 lines displace the
#      reciprocal (nonmetal_share = 0) and derivative lines carry it on
#      non-metal content, matching CBP assessment practice. A full-line list
#      entry on top of that double-exempts.
#   3. Ch88 civil aircraft. The carve-outs are country-conditional
#      (EU 9903.02.76, Korea 9903.02.81, ...) and modeled per-country in
#      resources/floor_exempt_products.csv; a universal entry wrongly exempts
#      non-deal countries.
#
# What stays:
#   - every row traceable (longest-prefix) to the note 2(v)(iii)(a)
#     enumeration via resources/annex_ii_first_appearance.csv (dated or not);
#   - the note 2(v)(iii)(b) "particular articles" subheadings (universal,
#     religious/specialty items — tiny trade, not extracted by the dates
#     builder, enumerated below from the printed note);
#   - ch98 (note (v)(i) exemption) and ch97/49 (Berman Amendment) rows, which
#     are deliberate curator additions with their own authority.
#
# Decision record: prune scope and outright deletion (rather than end-dating)
# approved 2026-06-11 — these lines were never in the printed enumeration, so
# there is no valid exemption window to preserve.
#
# Idempotent: re-running on a pruned list is a no-op. Run from the repo root:
#   Rscript scripts/prune_ieepa_exempt_untraceable.R [--dry-run]
# =============================================================================

suppressMessages({
  library(dplyr)
  library(readr)
  library(here)
})

dry_run <- '--dry-run' %in% commandArgs(trailingOnly = TRUE)

exempt_file <- here('resources', 'ieepa_exempt_products.csv')
exempt <- read_csv(exempt_file, col_types = cols(hts10 = col_character(),
                                                 .default = col_character()))
annex <- read_csv(here('resources', 'annex_ii_first_appearance.csv'),
                  col_types = cols(prefix = col_character(),
                                   .default = col_character()))

# Note 2(v)(iii)(b) "particular articles" subheadings (printed list has 11
# items in every revision carrying it, rev_29 → 2026_rev_10 — Etrogs,
# religious bakery items, acai, coconut water blends, religious essential
# oils, etc.). 2026-06-12 audit: this list originally omitted (b)(9)
# 2009.90.40 and (b)(11) 3301.29.51, falsely dropping 25 codes (restored to
# the exempt list with effective_date_start 2025-11-13, the rev_29 date).
viiib_subheadings <- c(
  '08059001', '08119080', '14049090', '19059010', '19059090',
  '20089921', '20093160', '20098970', '20099040', '21069099',
  '33012951'
)

matches_any_prefix <- function(codes, prefixes) {
  prefixes <- unique(prefixes[!is.na(prefixes) & nchar(prefixes) > 0])
  vapply(codes, function(h) {
    any(startsWith(h, prefixes) | startsWith(prefixes, h))
  }, logical(1))
}

classified <- exempt %>%
  mutate(
    ch2 = substr(hts10, 1, 2),
    keep_reason = case_when(
      matches_any_prefix(hts10, annex$prefix)        ~ 'note_2viiia',
      matches_any_prefix(hts10, viiib_subheadings)   ~ 'note_2viiib',
      ch2 == '98'                                    ~ 'ch98_note_2vi',
      ch2 %in% c('97', '49')                         ~ 'berman',
      TRUE                                           ~ NA_character_
    )
  )

kept    <- classified %>% filter(!is.na(keep_reason))
dropped <- classified %>% filter(is.na(keep_reason))

cat('=== Pruning untraceable IEEPA exempt entries ===\n')
cat('Input rows: ', nrow(exempt), '\n')
cat('Kept:       ', nrow(kept), '\n')
print(count(kept, keep_reason))
cat('Dropped:    ', nrow(dropped), '\n')
print(count(dropped, ch2, sort = TRUE), n = 10)

if (dry_run) {
  cat('\n--dry-run: no files written\n')
} else {
  out <- kept %>% select(hts10, effective_date_start, effective_date_end)
  write_csv(out, exempt_file, na = 'NA')
  drop_log <- here('output', 'diagnostics', 'ieepa_exempt_pruned_2026-06-11.csv')
  dir.create(dirname(drop_log), recursive = TRUE, showWarnings = FALSE)
  write_csv(dropped %>% select(hts10), drop_log)
  cat('\nWrote ', nrow(out), ' rows to ', exempt_file, '\n', sep = '')
  cat('Dropped codes logged to ', drop_log, '\n', sep = '')
}
