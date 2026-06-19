# Build imports_by_country_gtap_2024.csv
#
# One row per country (fixed full-year 2024 import basket = the weighting data).
# Columns:
#   1. country_name
#   2. cty_code
#   3. total_imports
#   4. 45 GTAP sector columns, header "code (Title-Case Name)"; these sum to total
#   5. s232_pharma_imports — sum of imports for the 131 HS codes in
#      s232_pharma_products.csv. NON-additive with the 45 (those dollars already
#      sit inside bph/chm); it's an overlapping subset, by design.

suppressMessages({
  library(here)
  library(tidyverse)
})

w <- readRDS(here('data', 'weights', 'hs10_by_country_gtap_2024_con.rds')) %>%
  mutate(gtap_code = tolower(gtap_code), cty_code = as.character(cty_code))

names_lk <- read_csv(here('resources', 'gtap_sector_names.csv'), show_col_types = FALSE) %>%
  mutate(gtap_code = tolower(gtap_code),
         header = paste0(gtap_code, ' (', str_to_title(sector_name), ')'))

# Canonical sector order = order in the lookup file.
sector_order <- names_lk$header

# Country names
ctry <- read_csv(here('resources', 'census_codes.csv'), show_col_types = FALSE) %>%
  transmute(cty_code = as.character(Code), country_name = Name)

# Pharma 232 HS codes
ph <- read_csv(here('resources', 's232_pharma_products.csv'), show_col_types = FALSE)
ph_codes <- as.character(ph[[1]])

# --- Per-country total ---
totals <- w %>% group_by(cty_code) %>% summarise(total_imports = sum(imports), .groups = 'drop')

# --- Per-country x GTAP sector (wide) ---
gtap_wide <- w %>%
  group_by(cty_code, gtap_code) %>%
  summarise(imports = sum(imports), .groups = 'drop') %>%
  left_join(names_lk %>% select(gtap_code, header), by = 'gtap_code') %>%
  select(cty_code, header, imports) %>%
  pivot_wider(names_from = header, values_from = imports, values_fill = 0)

# --- Per-country pharma-232 subset (overlapping) ---
pharma <- w %>%
  filter(hs10 %in% ph_codes) %>%
  group_by(cty_code) %>%
  summarise(`s232_pharma_imports (131 HS codes)` = sum(imports), .groups = 'drop')

out <- totals %>%
  left_join(ctry, by = 'cty_code') %>%
  left_join(gtap_wide, by = 'cty_code') %>%
  left_join(pharma, by = 'cty_code') %>%
  mutate(across(all_of(sector_order), ~ replace_na(.x, 0)),
         `s232_pharma_imports (131 HS codes)` =
           replace_na(`s232_pharma_imports (131 HS codes)`, 0)) %>%
  # Column order: name, code, total, 45 sectors (canonical), pharma
  select(country_name, cty_code, total_imports,
         all_of(sector_order), `s232_pharma_imports (131 HS codes)`) %>%
  arrange(desc(total_imports))

out_path <- here('output', 'imports_by_country_gtap_2024.csv')
if (!dir.exists(dirname(out_path))) dir.create(dirname(out_path), recursive = TRUE)
write_csv(out, out_path)

# --- Integrity checks ---
sector_sum <- rowSums(out[, sector_order])
max_diff <- max(abs(sector_sum - out$total_imports))
cat('Wrote', out_path, '\n')
cat('Rows (countries):', nrow(out), '| GTAP sector cols:', length(sector_order), '\n')
cat('Max |sum(45 sectors) - total_imports|:', format(max_diff, scientific = TRUE), '\n')
cat('Pharma codes matched in weight data:',
    n_distinct(w$hs10[w$hs10 %in% ph_codes]), 'of', length(ph_codes), '\n')
cat('Total 2024 imports ($B):', round(sum(out$total_imports) / 1e9, 1), '\n')
