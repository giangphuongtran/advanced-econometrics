"""Shared country metadata for the final-project data pipeline."""

COUNTRY_CENTROIDS = {
    "AT": (47.5, 14.5),
    "BE": (50.5, 4.5),
    "BG": (42.7, 25.5),
    "HR": (45.1, 15.2),
    "CZ": (49.8, 15.5),
    "DK": (56.2, 9.5),
    "FI": (61.9, 25.7),
    "FR": (46.2, 2.2),
    "DE": (51.1, 10.4),
    "GR": (39.0, 22.0),
    "HU": (47.1, 19.5),
    "IE": (53.4, -8.2),
    "IT": (41.8, 12.5),
    "NL": (52.1, 5.2),
    "PL": (51.9, 19.1),
    "PT": (39.3, -8.2),
    "RO": (45.9, 24.9),
    "SK": (48.6, 19.6),
    "SI": (46.1, 15.0),
    "ES": (40.4, -3.7),
    "SE": (60.1, 18.6),
}

COUNTRY_NAMES = {
    "AT": "Austria",
    "BE": "Belgium",
    "BG": "Bulgaria",
    "HR": "Croatia",
    "CZ": "Czechia",
    "DK": "Denmark",
    "FI": "Finland",
    "FR": "France",
    "DE": "Germany",
    "GR": "Greece",
    "HU": "Hungary",
    "IE": "Ireland",
    "IT": "Italy",
    "NL": "Netherlands",
    "PL": "Poland",
    "PT": "Portugal",
    "RO": "Romania",
    "SK": "Slovakia",
    "SI": "Slovenia",
    "ES": "Spain",
    "SE": "Sweden",
}

# ISO2 (panel) -> ISO3 (World Bank API)
ISO2_TO_ISO3 = {
    "AT": "AUT", "BE": "BEL", "BG": "BGR", "HR": "HRV", "CZ": "CZE",
    "DK": "DNK", "FI": "FIN", "FR": "FRA", "DE": "DEU", "GR": "GRC",
    "HU": "HUN", "IE": "IRL", "IT": "ITA", "NL": "NLD", "PL": "POL",
    "PT": "PRT", "RO": "ROU", "SK": "SVK", "SI": "SVN", "ES": "ESP",
    "SE": "SWE",
}

PANEL_COUNTRIES = list(COUNTRY_CENTROIDS.keys())

# Bounding box half-width (degrees) around centroid for ERA5 grid selection
BBOX_HALF_WIDTH = 2.5

# ERA5 native resolution (degrees)
ERA5_GRID_STEP = 0.25
