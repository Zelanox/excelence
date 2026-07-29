from .common import ApiResponse


# ==========================================================
# Headers
# ==========================================================

class SpreadsheetHeadersResponse(ApiResponse):

    headers: list[str]


# ==========================================================
# Data
# ==========================================================

class SpreadsheetDataResponse(ApiResponse):

    rows: list[dict]


# ==========================================================
# Sheets
# ==========================================================

class SpreadsheetSheetsResponse(ApiResponse):

    sheets: list[str]

    current_sheet: str


# ==========================================================
# Status
# ==========================================================

class SpreadsheetStatusResponse(ApiResponse):

    filename: str

    loaded: bool

    modified: bool

    rows: int

    columns: int

