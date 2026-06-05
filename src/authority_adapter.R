# =============================================================================
# authority_adapter.R — JSON/param-object → AuthoritySpec re-packaging
# =============================================================================
#
# `build_authority_specs()` takes the bespoke per-authority Layer-B objects the
# parsers (03/04/05) already produce and re-packages them into a uniform
# `authority_spec_set` (see docs/authority_spec.md, src/authority_spec.R).
#
# CONTRACT (Phase 6b) — rate payloads are spec-native, parity-safe by construction:
#   * Each authority that owns a resolved rate object — `section_232`'s 21-field
#     s232_rates list, `ieepa_reciprocal`'s tibble (WITH its `universal_baseline`
#     attribute), `ieepa_fentanyl`'s tibble, `section_122`'s list — carries that
#     object VERBATIM in its first program's `rate$resolved` slot: a normal,
#     ops-mutable spec field, read back by the calculator via `*_from_specs()`.
#   * The calculator, handed a spec set, pulls those identical R objects back out
#     and runs its unchanged body — so flag-on output stays byte-identical to
#     flag-off (same objects). The Phase-1 out-of-band `raw_*` attrs are gone (6b).
#   * The other normalized fields are a scaffold the calculator reads selectively:
#     `country_scope` for 301/201 (Phase 2e); `active.until` for IEEPA invalidation
#     (Phase 2d); `heading_gates` precomputed for 232 (Phase 2c).
#   * `mfn` / `other` are constructed but inert (no resolved payload; their data
#     still flows through the calculator's internal footnote-seeding / extraction).
#
# Source order: this file depends on src/authority_spec.R (constructors,
# validation, `%||%`) being sourced first, and on get_country_constants() from
# src/05_parse_policy_params.R for census-code scope population.
# =============================================================================

# ---- read the rate payload back out of the normalized programs (Phase 6b) ----
#
# The thin cut relocates each parser object VERBATIM from its out-of-band
# `raw_*` attr into the owning program's `rate$resolved` slot (a normal spec
# field the ops engine can mutate). Reconstruction is therefore the identity —
# the calc gets back the exact same R object — so the body stays byte-identical.
# (Full per-program normalization — e.g. splitting the 21-field s232 list across
# its 7 programs — is deferred to Phase 8; not needed for the ops capability.)
# 232's payload is authority-wide, parked on programs[[1]] until that split.
.spec_resolved_rate <- function(spec) {
  if (is.null(spec) || !length(spec$programs)) return(NULL)
  spec$programs[[1]]$rate$resolved
}
ieepa_rates_from_specs    <- function(specs) .spec_resolved_rate(specs[['ieepa_reciprocal']])
s232_rates_from_specs     <- function(specs) .spec_resolved_rate(specs[['section_232']])
fentanyl_rates_from_specs <- function(specs) .spec_resolved_rate(specs[['ieepa_fentanyl']])
# (section_122 was de-blobbed in Plank 3 — its rate lives in the compositional
#  rate$default layer now, read by the calc via resolve_rate(), so it no longer
#  needs a resolved-blob accessor here.)

# ---- Section 301: resolve the additive rate tier into the spec (Plank 1) ----
#
# The Section 301 ADDITIVE rate (hts8 -> rate) was recomputed inside the
# calculator (06_calculate_rates.R ~2354-2399). Plank 1 moves that resolution
# here, into the spec's `by_product_tier`, so the calculator just READS it
# (resolve_rate's by_product_tier layer). Reproduces the calculator EXACTLY:
#   1. date-gate ch99 via filter_active_ch99 (calc line ~816 — the build passes
#      RAW ch99_data here, so we apply the same gate ourselves), then
#   2. drop suspended provisions, then
#   3. MAX(s301_rate) per hts8 across the active ADDITIVE codes (supersession:
#      Biden 9903.91.xx >= Trump 9903.88.xx, so MAX picks the superseding rate).
# The content-split flavor (rate_301_cs) is left in the calculator for now — it is
# DORMANT in baseline (section_301_content_split_codes empty), so parity is
# unaffected; relocating it cleanly wants a second program/column and is deferred.
# Returns a named numeric (names = hts8) or NULL when no active additive codes.
build_s301_additive_tier <- function(ch99_data, effective_date, pp) {
  rate_lookup <- pp$SECTION_301_RATES
  if (is.null(rate_lookup) || !nrow(rate_lookup)) return(NULL)
  s301_path <- here::here('resources', 's301_product_lists.csv')
  if (!file.exists(s301_path)) return(NULL)
  s301_products <- readr::read_csv(s301_path, col_types = readr::cols(
    hts8 = readr::col_character(), list = readr::col_character(),
    ch99_code = readr::col_character()))
  ch99_active <- filter_active_ch99(ch99_data, as.Date(effective_date))
  matched <- ch99_active[ch99_active$ch99_code %in% rate_lookup$ch99_pattern, , drop = FALSE]
  if (!nrow(matched)) return(NULL)
  descr <- matched$description %||% rep('', nrow(matched))
  active_codes <- unique(matched$ch99_code[!grepl('provision suspended', descr, ignore.case = TRUE)])
  cs_cfg    <- as.character(pp$section_301_content_split_codes %||% character(0))
  add_codes <- setdiff(active_codes, cs_cfg)
  if (!length(add_codes)) return(NULL)
  lk <- s301_products |>
    dplyr::filter(ch99_code %in% add_codes) |>
    dplyr::inner_join(rate_lookup, by = c('ch99_code' = 'ch99_pattern')) |>
    dplyr::group_by(hts8) |>
    dplyr::summarise(rate = max(s301_rate), .groups = 'drop')
  if (!nrow(lk)) return(NULL)
  stats::setNames(lk$rate, lk$hts8)
}

# ---- the adapter ------------------------------------------------------------

#' Re-package the bespoke per-authority parser outputs into an authority_spec_set.
#'
#' Signature mirrors calculate_rates_for_revision() so the build sites can call
#' it as a drop-in with the identical argument list.
#'
#' @param products,ch99_data,ieepa_rates,usmca parser outputs (Layer-B)
#' @param countries,revision_id,effective_date revision context
#' @param s232_rates,fentanyl_rates extracted rate objects (or NULL)
#' @param policy_params resolved policy params (or NULL → load_policy_params())
#' @return an `authority_spec_set` with raw objects embedded; validated.
build_authority_specs <- function(products, ch99_data, ieepa_rates, usmca,
                                  countries, revision_id, effective_date,
                                  s232_rates = NULL, fentanyl_rates = NULL,
                                  policy_params = NULL) {
  pp <- policy_params %||% load_policy_params()
  cc <- get_country_constants(pp)
  CTY_CHINA  <- cc$CTY_CHINA
  CTY_CANADA <- cc$CTY_CANADA
  CTY_MEXICO <- cc$CTY_MEXICO

  # IEEPA invalidation → ieepa programs' `active.until` (first inactive day,
  # exclusive — matches the calculator's `effective_date >= until` kill switch).
  # Mirror pp$IEEPA_INVALIDATION_DATE VERBATIM (incl. NULL when unset) so the
  # calc's `if (!is.null(until) && ...)` behaves identically — coercing NULL to
  # NA here would make the calc's `if (NA)` error (Phase 2d).
  ieepa_until <- pp$IEEPA_INVALIDATION_DATE

  # --- section_232 — the genuinely multi-program authority ------------------
  # Programs are a Phase-2 scaffold; the resolved 21-field rate list (rates,
  # exempt lists, deals, overrides) lives on programs[[1]]$rate$resolved (Phase 6b).
  metal_prog <- function(id, type) authority_program(
    id = id, country_scope = list(include = 'all', exclude = list()),
    stacking = list(class = 'primary_metal'), metal = list(type = type, content = 'full'))
  full_prog <- function(id) authority_program(
    id = id, country_scope = list(include = 'all', exclude = list()),
    stacking = list(class = 'primary_full'), metal = list(type = 'none'))
  section_232 <- authority_spec(
    authority = 'section_232',
    stacking  = list(class = 'primary_metal', exceptions = list()),
    usmca_treatment = 'per_program',
    active = list(from = NA, until = NA),   # per-program heading gates (Phase 2c)
    programs = list(
      metal_prog('steel',    'steel'),
      metal_prog('aluminum', 'aluminum'),
      metal_prog('copper',   'copper'),
      full_prog('autos'),
      full_prog('mhd'),
      full_prog('wood'),
      full_prog('semiconductors')
    )
  )
  # Phase 6b: park the 21-field s232 list whole on programs[[1]]$rate$resolved
  # (authority-wide; per-program split deferred to P8). Read via s232_rates_from_specs().
  section_232$programs[[1]]$rate$resolved <- s232_rates
  # Phase 2c/6c: precompute the heading-program activation gates from the
  # authoritative s232 value, so the calc reads them off the spec instead of
  # recomputing (compute_heading_gates is the single source). Since 6c the gate
  # fn is a pure function of s232_rates (which carries the date-gated
  # auto_has_parts flag) — no live-ch99 grep here anymore.
  if (!is.null(s232_rates)) {
    attr(section_232, 'heading_gates') <- compute_heading_gates(s232_rates)
  }

  # --- ieepa_reciprocal — blanket, country-level ----------------------------
  ieepa_reciprocal <- authority_spec(
    authority = 'ieepa_reciprocal',
    stacking  = list(class = 'content_split', exceptions = list()),
    usmca_treatment = 'eligible',
    active = list(from = NA, until = ieepa_until),
    programs = list(authority_program(
      id = 'reciprocal',
      product_scope = list(include = 'all'),
      country_scope = list(include = 'all'),   # universal_baseline default lives in raw
      rate = list(by_country = 'from_raw', default_unlisted_rate = 'from_raw')))
  )
  # Phase 6b: relocate into the program (the universal_baseline attr on the
  # tibble rides along verbatim). Read via ieepa_rates_from_specs().
  ieepa_reciprocal$programs[[1]]$rate$resolved <- ieepa_rates

  # --- ieepa_fentanyl — content_split except China (additive), as data ------
  fentanyl_scope <- c(CTY_CHINA, CTY_CANADA, CTY_MEXICO)
  fentanyl_scope <- fentanyl_scope[!is.na(fentanyl_scope)]
  ieepa_fentanyl <- authority_spec(
    authority = 'ieepa_fentanyl',
    stacking  = list(class = 'content_split',
                     exceptions = setNames(list('additive'), CTY_CHINA %||% 'china')),
    usmca_treatment = 'exempt',
    active = list(from = NA, until = ieepa_until),
    programs = list(authority_program(
      id = 'fentanyl',
      product_scope = list(include = 'all'),
      country_scope = list(include = fentanyl_scope),
      rate = list(by_country = 'from_raw')))
  )
  # Phase 6b: relocate into the program. Read via fentanyl_rates_from_specs().
  ieepa_fentanyl$programs[[1]]$rate$resolved <- fentanyl_rates

  # --- section_301 — China gate as data (no raw embed; footnote-seeded) -----
  section_301 <- authority_spec(
    authority = 'section_301',
    stacking  = list(class = 'additive', exceptions = list()),
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 's301',
      product_scope = list(list_file = 'resources/s301_product_lists.csv'),
      country_scope = list(include = CTY_CHINA %||% '5700'),
      rate = list(by_product_tier = 'from_list')))
  )
  # Plank 1: resolve the additive 301 tier (hts8 -> rate) into by_product_tier so
  # the calculator reads it instead of recomputing. NULL (no active codes this
  # revision) leaves the hollow 'from_list' sentinel -> calc skips 301 as before.
  section_301$programs[[1]]$rate$by_product_tier <-
    build_s301_additive_tier(ch99_data, effective_date, pp) %||% 'from_list'

  # --- section_201 — solar, Canada-exempt -----------------------------------
  section_201 <- authority_spec(
    authority = 'section_201',
    stacking  = list(class = 'additive', exceptions = list()),
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 's201',
      product_scope = list(list_file = 'resources/s201_solar_products.csv'),
      country_scope = list(include = 'all',
                           exclude = (CTY_CANADA %||% character(0)))))
  )

  # --- section_122 — non-discriminatory blanket -----------------------------
  section_122 <- authority_spec(
    authority = 'section_122',
    stacking  = list(class = 'content_split', exceptions = list()),
    usmca_treatment = 'eligible',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 's122', product_scope = list(include = 'all'),
      country_scope = list(include = 'all')))
  )
  # Plank 3: structure the Section 122 blanket rate into the compositional
  # rate$default layer (de-blobbed — no more rate$resolved). Extracted from the
  # SAME date-gated ch99 the calc uses (filter_active_ch99 at 06:766). The calc
  # READS it via resolve_rate() and gates on value > 0, so an absent program
  # (has_s122 = FALSE) leaves the rate hollow and the gate stays OFF — exactly
  # the old has_s122 ≡ rate>0 behavior. rate_type = 'surcharge': an additive duty.
  s122_extracted <- extract_section122_rates(
    filter_active_ch99(ch99_data, as.Date(effective_date)))
  if (isTRUE(s122_extracted$has_s122)) {
    section_122$programs[[1]]$rate$default   <- s122_extracted$s122_rate
    section_122$programs[[1]]$rate$rate_type <- 'surcharge'
  }

  # --- mfn (base layer) + other (catch-all) — inert in Phase 1 --------------
  mfn <- authority_spec(
    authority = 'mfn',
    stacking  = list(class = 'additive', exceptions = list()),  # base layer; placeholder
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 'mfn', product_scope = list(include = 'all'),
      country_scope = list(include = 'all'),
      rate = list(default = 'from_products_base_rate')))
  )
  other <- authority_spec(
    authority = 'other',
    stacking  = list(class = 'additive', exceptions = list()),
    usmca_treatment = 'none',
    active = list(from = NA, until = NA),
    programs = list(authority_program(
      id = 'other', product_scope = list(include = 'all'),
      country_scope = list(include = 'all')))
  )

  specs <- authority_spec_set(
    section_232, section_301, ieepa_reciprocal, ieepa_fentanyl,
    section_122, section_201, mfn, other
  )

  # Record revision context as set-level metadata (not read in Phase 1; useful
  # for per-revision persistence in Phase 8 / debugging). Kept off the specs so
  # it never perturbs the embedded-object identity the parity gate relies on.
  attr(specs, 'revision_id')     <- revision_id
  attr(specs, 'effective_date')  <- effective_date

  validate_spec_set(specs)   # fail loud on any structural violation
  specs
}
