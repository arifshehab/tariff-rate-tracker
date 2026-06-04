# =============================================================================
# new_coverage.R — Phase 8 no-Ch99 seeder for brand-new tariff coverage
# =============================================================================
# A counterfactual can introduce a tariff with NO Chapter-99 backing (a brand-new
# authority) via the `add_program` operation (src/scenario_ops.R). Such a program
# carries a FLAT rate + product/country scope and is parked on the `other`
# authority. At resolution time, just before stacking, the calculator applies
# these seeded programs to `rate_other` — the additive catch-all, so NO schema
# change is needed — both updating existing in-scope pairs and seeding
# product-country pairs the baseline grid doesn't yet carry (add_blanket_pairs).
#
# DORMANT IN BASELINE: the baseline `other` authority has no flat-rate program, so
# collect_seeded_programs() returns nothing and rate_other is untouched
# (byte-identical). The mechanism only fires under an add_program scenario.
#
# Depends on src/authority_spec.R (resolve_country_scope, %||%) and
# src/rate_schema.R (add_blanket_pairs). Sourced via helpers.R.
# =============================================================================

#' Resolve a program's product_scope to a vector of covered HTS10 codes.
#'
#' Supported scopes: `list(include = 'all')` (every product), `list(prefixes =
#' c(...))` (HTS10 starts-with, dots ignored), `list(list = c(<hts10>...))`
#' (explicit codes). Fail-loud on an unrecognized scope so a scenario can never
#' silently cover nothing.
#'
#' @param scope product_scope list
#' @param products product table with an `hts10` column
#' @return character vector of covered HTS10 codes
resolve_product_scope <- function(scope, products) {
  all_hts10 <- as.character(products$hts10)
  has_prefixes <- !is.null(scope$prefixes)
  has_list     <- !is.null(scope$list)
  if (!has_prefixes && !has_list) {
    # No explicit product set: only include='all' (or an empty/unspecified scope)
    # means "every product". Any other key (e.g. chapters=) is unrecognized and
    # must fail loud — a scenario can never silently cover nothing OR everything.
    if (identical(scope$include, 'all') || length(scope) == 0) return(all_hts10)
    stop('resolve_product_scope: unrecognized product_scope (need include="all", ',
         'prefixes=, or list=); got keys: ', paste(names(scope), collapse = ', '))
  }
  clean <- gsub('\\.', '', all_hts10)
  hits <- character(0)
  if (has_prefixes) {
    pref <- gsub('\\.', '', as.character(unlist(scope$prefixes)))
    keep <- Reduce(`|`, lapply(pref, function(p) startsWith(clean, p)), rep(FALSE, length(all_hts10)))
    hits <- c(hits, all_hts10[keep])
  }
  if (has_list) {
    hits <- c(hits, intersect(all_hts10, as.character(unlist(scope$list))))
  }
  unique(hits)
}

#' Collect new-coverage programs across the spec set: programs carrying a non-zero
#' flat rate (`rate$flat`), i.e. those added via add_program. Each returned record
#' is augmented with its owning authority name (`.authority`). Baseline => empty.
collect_seeded_programs <- function(specs) {
  out <- list()
  for (auth in names(specs)) {
    for (p in specs[[auth]]$programs) {
      flat <- p$rate$flat
      if (!is.null(flat) && is.numeric(flat) && length(flat) == 1L && !is.na(flat) && flat != 0) {
        p$.authority <- auth
        out[[length(out) + 1L]] <- p
      }
    }
  }
  out
}

#' Apply all new-coverage (no-Ch99) programs to rate_other, just before stacking.
#'
#' For each seeded program: add its flat rate to rate_other on existing in-scope
#' (hts10, country) pairs, then seed any in-scope pairs the grid doesn't yet carry
#' (add_blanket_pairs). No-op when there are no seeded programs => byte-identical
#' baseline. Stacking (step 8) then folds rate_other in as the additive catch-all.
#'
#' @param rates wide rate panel (must carry rate_other)
#' @param specs the (possibly operation-mutated) authority_spec_set, or NULL
#' @param products product table (hts10, base_rate)
#' @param countries full census-code universe
#' @return rates with new-coverage rate_other applied / pairs seeded
apply_new_coverage_programs <- function(rates, specs, products, countries) {
  if (is.null(specs)) return(rates)
  seeded <- collect_seeded_programs(specs)
  if (!length(seeded)) return(rates)
  for (p in seeded) {
    flat       <- p$rate$flat
    cov_hts10  <- resolve_product_scope(p$product_scope %||% list(include = 'all'), products)
    scope_ctry <- resolve_country_scope(p$country_scope %||% list(include = 'all'), countries)
    if (!length(cov_hts10) || !length(scope_ctry)) {
      message('  New-coverage program "', p$id %||% '?', '": empty product or country scope — skipped')
      next
    }
    label <- paste0('new-coverage "', p$id %||% '?', '" (', p$.authority, ')')
    message('  Seeding ', label, ': +', round(flat * 100, 1), '% to rate_other on ',
            length(cov_hts10), ' HTS10 x ', length(scope_ctry), ' countries')
    rates <- rates %>%
      mutate(rate_other = if_else(hts10 %in% cov_hts10 & country %in% scope_ctry,
                                  rate_other + flat, rate_other))
    cr <- tibble(country = scope_ctry, blanket_rate = flat)
    rates <- add_blanket_pairs(rates, products, cov_hts10, cr, 'rate_other', label)
  }
  rates
}
