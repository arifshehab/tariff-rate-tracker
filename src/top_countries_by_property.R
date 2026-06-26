# =============================================================================
# Top Countries by Property
# =============================================================================

library(tidyverse)
library(jsonlite)

# ISO-2 + region lookup keyed on country_name as it appears in the CSV.
# Regions: na=North America, sa=South America, eu=Europe,
#          af=Africa, me=Middle East, as=Asia, oc=Oceania
.COUNTRY_LOOKUP <- tribble(
  ~country_name,                                              ~iso2, ~region,
  "Afghanistan",                                             "AF",  "as",
  "Albania",                                                 "AL",  "eu",
  "Algeria",                                                 "DZ",  "af",
  "Andorra",                                                 "AD",  "eu",
  "Angola",                                                  "AO",  "af",
  "Anguilla",                                                "AI",  "na",
  "Antigua and Barbuda",                                     "AG",  "na",
  "Argentina",                                               "AR",  "sa",
  "Armenia",                                                 "AM",  "as",
  "Aruba",                                                   "AW",  "na",
  "Australia",                                               "AU",  "oc",
  "Austria",                                                 "AT",  "eu",
  "Azerbaijan",                                              "AZ",  "as",
  "Bahamas",                                                 "BS",  "na",
  "Bahrain",                                                 "BH",  "me",
  "Bangladesh",                                              "BD",  "as",
  "Barbados",                                                "BB",  "na",
  "Belarus",                                                 "BY",  "eu",
  "Belgium",                                                 "BE",  "eu",
  "Belize",                                                  "BZ",  "na",
  "Benin",                                                   "BJ",  "af",
  "Bermuda",                                                 "BM",  "na",
  "Bhutan",                                                  "BT",  "as",
  "Bolivia",                                                 "BO",  "sa",
  "Bosnia and Herzegovina",                                  "BA",  "eu",
  "Botswana",                                                "BW",  "af",
  "Brazil",                                                  "BR",  "sa",
  "British Indian Ocean Territory",                          "IO",  "as",
  "British Virgin Islands",                                  "VG",  "na",
  "Brunei",                                                  "BN",  "as",
  "Bulgaria",                                                "BG",  "eu",
  "Burkina Faso",                                            "BF",  "af",
  "Burma (Myanmar)",                                         "MM",  "as",
  "Burundi",                                                 "BI",  "af",
  "Cabo Verde",                                              "CV",  "af",
  "Cambodia",                                                "KH",  "as",
  "Cameroon",                                                "CM",  "af",
  "Canada",                                                  "CA",  "na",
  "Cayman Islands",                                          "KY",  "na",
  "Central African Republic",                                "CF",  "af",
  "Chad",                                                    "TD",  "af",
  "Chile",                                                   "CL",  "sa",
  "China",                                                   "CN",  "as",
  "Christmas Island (in the Indian Ocean)",                  "CX",  "oc",
  "Cocos (Keeling) Islands",                                 "CC",  "oc",
  "Colombia",                                                "CO",  "sa",
  "Comoros",                                                 "KM",  "af",
  "Congo, Democratic Republic of the Congo (formerly Za",   "CD",  "af",
  "Congo, Republic of the Congo",                            "CG",  "af",
  "Cook Islands",                                            "CK",  "oc",
  "Costa Rica",                                              "CR",  "na",
  "Cote d'Ivoire",                                           "CI",  "af",
  "Croatia",                                                 "HR",  "eu",
  "Cuba",                                                    "CU",  "na",
  "Curacao",                                                 "CW",  "na",
  "Cyprus",                                                  "CY",  "eu",
  "Czech Republic",                                          "CZ",  "eu",
  "Denmark, except Greenland",                               "DK",  "eu",
  "Djibouti",                                                "DJ",  "af",
  "Dominica",                                                "DM",  "na",
  "Dominican Republic",                                      "DO",  "na",
  "Ecuador",                                                 "EC",  "sa",
  "Egypt",                                                   "EG",  "af",
  "El Salvador",                                             "SV",  "na",
  "Equatorial Guinea",                                       "GQ",  "af",
  "Eritrea",                                                 "ER",  "af",
  "Estonia",                                                 "EE",  "eu",
  "Eswatini",                                                "SZ",  "af",
  "Ethiopia",                                                "ET",  "af",
  "Falkland Islands (Islas Malvinas)",                       "FK",  "sa",
  "Faroe Islands",                                           "FO",  "eu",
  "Fiji",                                                    "FJ",  "oc",
  "Finland",                                                 "FI",  "eu",
  "France",                                                  "FR",  "eu",
  "French Guiana",                                           "GF",  "sa",
  "French Polynesia",                                        "PF",  "oc",
  "French Southern and Antarctic Lands",                     "TF",  "af",
  "Gabon",                                                   "GA",  "af",
  "Gambia",                                                  "GM",  "af",
  "Gaza Strip administered by Israel",                       "PS",  "me",
  "Georgia",                                                 "GE",  "as",
  "Germany (Federal Republic of Germany)",                   "DE",  "eu",
  "Ghana",                                                   "GH",  "af",
  "Gibraltar",                                               "GI",  "eu",
  "Greece",                                                  "GR",  "eu",
  "Greenland",                                               "GL",  "na",
  "Grenada",                                                 "GD",  "na",
  "Guadeloupe",                                              "GP",  "na",
  "Guatemala",                                               "GT",  "na",
  "Guinea",                                                  "GN",  "af",
  "Guinea-Bissau",                                           "GW",  "af",
  "Guyana",                                                  "GY",  "sa",
  "Haiti",                                                   "HT",  "na",
  "Holy See (Vatican City)",                                 "VA",  "eu",
  "Honduras",                                                "HN",  "na",
  "Hong Kong",                                               "HK",  "as",
  "Hungary",                                                 "HU",  "eu",
  "Iceland",                                                 "IS",  "eu",
  "India",                                                   "IN",  "as",
  "Indonesia",                                               "ID",  "as",
  "Iran",                                                    "IR",  "me",
  "Iraq",                                                    "IQ",  "me",
  "Ireland",                                                 "IE",  "eu",
  "Israel",                                                  "IL",  "me",
  "Italy",                                                   "IT",  "eu",
  "Jamaica",                                                 "JM",  "na",
  "Japan",                                                   "JP",  "as",
  "Jordan",                                                  "JO",  "me",
  "Kazakhstan",                                              "KZ",  "as",
  "Kenya",                                                   "KE",  "af",
  "Kiribati",                                                "KI",  "oc",
  "Kosovo",                                                  "XK",  "eu",
  "Kuwait",                                                  "KW",  "me",
  "Kyrgyzstan",                                              "KG",  "as",
  "Laos (Lao People's Democratic Republic)",                 "LA",  "as",
  "Latvia",                                                  "LV",  "eu",
  "Lebanon",                                                 "LB",  "me",
  "Lesotho",                                                 "LS",  "af",
  "Liberia",                                                 "LR",  "af",
  "Libya",                                                   "LY",  "af",
  "Liechtenstein",                                           "LI",  "eu",
  "Lithuania",                                               "LT",  "eu",
  "Luxembourg",                                              "LU",  "eu",
  "Macao",                                                   "MO",  "as",
  "Madagascar",                                              "MG",  "af",
  "Malawi",                                                  "MW",  "af",
  "Malaysia",                                                "MY",  "as",
  "Maldives",                                                "MV",  "as",
  "Mali",                                                    "ML",  "af",
  "Malta",                                                   "MT",  "eu",
  "Marshall Islands",                                        "MH",  "oc",
  "Martinique",                                              "MQ",  "na",
  "Mauritania",                                              "MR",  "af",
  "Mauritius",                                               "MU",  "af",
  "Mayotte",                                                 "YT",  "af",
  "Mexico",                                                  "MX",  "na",
  "Micronesia, Federated States of",                         "FM",  "oc",
  "Moldova (Republic of Moldova)",                           "MD",  "eu",
  "Monaco",                                                  "MC",  "eu",
  "Mongolia",                                                "MN",  "as",
  "Montenegro",                                              "ME",  "eu",
  "Montserrat",                                              "MS",  "na",
  "Morocco",                                                 "MA",  "af",
  "Mozambique",                                              "MZ",  "af",
  "Namibia",                                                 "NA",  "af",
  "Nauru",                                                   "NR",  "oc",
  "Nepal",                                                   "NP",  "as",
  "Netherlands",                                             "NL",  "eu",
  "New Caledonia",                                           "NC",  "oc",
  "New Zealand",                                             "NZ",  "oc",
  "Nicaragua",                                               "NI",  "na",
  "Niger",                                                   "NE",  "af",
  "Nigeria",                                                 "NG",  "af",
  "Niue",                                                    "NU",  "oc",
  "North Korea (Democratic People's Republic of Korea)",     "KP",  "as",
  "North Macedonia",                                         "MK",  "eu",
  "Norway",                                                  "NO",  "eu",
  "Oman",                                                    "OM",  "me",
  "Pakistan",                                                "PK",  "as",
  "Palau",                                                   "PW",  "oc",
  "Panama",                                                  "PA",  "na",
  "Papua New Guinea",                                        "PG",  "oc",
  "Paraguay",                                                "PY",  "sa",
  "Peru",                                                    "PE",  "sa",
  "Philippines",                                             "PH",  "as",
  "Pitcairn Islands",                                        "PN",  "oc",
  "Poland",                                                  "PL",  "eu",
  "Portugal",                                                "PT",  "eu",
  "Qatar",                                                   "QA",  "me",
  "Reunion",                                                 "RE",  "af",
  "Romania",                                                 "RO",  "eu",
  "Russia",                                                  "RU",  "eu",
  "Rwanda",                                                  "RW",  "af",
  "Saint Helena",                                            "SH",  "af",
  "Saint Kitts and Nevis",                                   "KN",  "na",
  "Saint Lucia",                                             "LC",  "na",
  "Saint Pierre and Miquelon",                               "PM",  "na",
  "Saint Vincent and the Grenadines",                        "VC",  "na",
  "Samoa (Western Samoa)",                                   "WS",  "oc",
  "San Marino",                                              "SM",  "eu",
  "Sao Tome and Principe",                                   "ST",  "af",
  "Saudi Arabia",                                            "SA",  "me",
  "Senegal",                                                 "SN",  "af",
  "Serbia",                                                  "RS",  "eu",
  "Seychelles",                                              "SC",  "af",
  "Sierra Leone",                                            "SL",  "af",
  "Singapore",                                               "SG",  "as",
  "Sint Maarten",                                            "SX",  "na",
  "Slovakia",                                                "SK",  "eu",
  "Slovenia",                                                "SI",  "eu",
  "Solomon Islands",                                         "SB",  "oc",
  "Somalia",                                                 "SO",  "af",
  "South Africa",                                            "ZA",  "af",
  "South Korea (Republic of Korea)",                         "KR",  "as",
  "South Sudan",                                             "SS",  "af",
  "Spain",                                                   "ES",  "eu",
  "Sri Lanka",                                               "LK",  "as",
  "Sudan",                                                   "SD",  "af",
  "Suriname",                                                "SR",  "sa",
  "Svalbard and Jan Mayen",                                  "SJ",  "eu",
  "Sweden",                                                  "SE",  "eu",
  "Switzerland",                                             "CH",  "eu",
  "Syria (Syrian Arab Republic)",                            "SY",  "me",
  "Taiwan",                                                  "TW",  "as",
  "Tajikistan",                                              "TJ",  "as",
  "Tanzania (United Republic of Tanzania)",                  "TZ",  "af",
  "Thailand",                                                "TH",  "as",
  "Timor-Leste",                                             "TL",  "as",
  "Togo",                                                    "TG",  "af",
  "Tokelau",                                                 "TK",  "oc",
  "Tonga",                                                   "TO",  "oc",
  "Trinidad and Tobago",                                     "TT",  "na",
  "Tunisia",                                                 "TN",  "af",
  "Turkey",                                                  "TR",  "eu",
  "Turkmenistan",                                            "TM",  "as",
  "Turks and Caicos Islands",                                "TC",  "na",
  "Tuvalu",                                                  "TV",  "oc",
  "Uganda",                                                  "UG",  "af",
  "Ukraine",                                                 "UA",  "eu",
  "United Arab Emirates",                                    "AE",  "me",
  "United Kingdom",                                          "GB",  "eu",
  "Uruguay",                                                 "UY",  "sa",
  "Uzbekistan",                                              "UZ",  "as",
  "Vanuatu",                                                 "VU",  "oc",
  "Venezuela",                                               "VE",  "sa",
  "Vietnam",                                                 "VN",  "as",
  "Wallis and Futuna",                                       "WF",  "oc",
  "West Bank administered by Israel",                        "PS",  "me",
  "Yemen (Republic of Yemen)",                               "YE",  "me",
  "Zambia",                                                  "ZM",  "af",
  "Zimbabwe",                                                "ZW",  "af",
)

#' Return the top-N countries ranked by a single import column and write JSON.
#'
#' Reads an imports-by-country CSV (e.g. output/imports_by_country_gtap_2024.csv),
#' sorts by the requested column from highest to lowest, joins ISO-2 and region
#' metadata, wraps with provenance fields, and writes a JSON file.
#'
#' @param filepath    Path to the imports-by-country CSV.
#' @param n           Number of top countries to return.
#' @param property    Name of the column to rank by (e.g. "total_imports").
#' @param output_path Path for the output JSON file.
#' @param last_updated Date string for the data vintage (default "2024-01-01").
#' @param source      URL or citation string for the data source.
#'
#' @return Invisibly returns the JSON string; primary effect is writing the file.
top_countries_by_property <- function(
    filepath,
    n,
    property,
    output_path,
    last_updated = "2024-01-01",
    source       = "https://www.census.gov/foreign-trade/reference/products/index.html") {

  stopifnot(
    is.character(filepath),    length(filepath)    == 1L,
    is.numeric(n),             length(n)           == 1L, n >= 0,
    is.character(property),    length(property)    == 1L,
    is.character(output_path), length(output_path) == 1L
  )

  if (!file.exists(filepath)) stop("File not found: ", filepath)

  df <- readr::read_csv(filepath, show_col_types = FALSE)

  required <- c("country_name", property)
  missing  <- setdiff(required, names(df))
  if (length(missing)) {
    stop("Column(s) not found in ", basename(filepath), ": ",
         paste(missing, collapse = ", "))
  }

  countries <- df %>%
    select(country_name, all_of(property)) %>%
    arrange(desc(.data[[property]])) %>%
    slice_head(n = n) %>%
    left_join(.COUNTRY_LOOKUP, by = "country_name") %>%
    select(country_name, iso2, region, all_of(property))

  unmatched <- countries %>% filter(is.na(iso2)) %>% pull(country_name)
  if (length(unmatched)) {
    warning("No ISO-2/region mapping for: ", paste(unmatched, collapse = ", "))
  }

  payload <- list(
    last_updated = last_updated,
    source       = source,
    countries    = jsonlite::toJSON(countries, dataframe = "rows", auto_unbox = TRUE) %>%
                     jsonlite::fromJSON()
  )

  json_out <- jsonlite::toJSON(payload, pretty = TRUE, auto_unbox = TRUE)
  writeLines(json_out, output_path)
  message("Wrote ", nrow(countries), " countries to ", output_path)
  invisible(json_out)
}
