from typing import Any

from pydantic import BaseModel, Field

from .common import ApiResponse, SpreadsheetResponse


# ==========================================================
# Requests
# ==========================================================

class SheetRequest(BaseModel):

    sheet_name: str = Field(..., description="Worksheet to activate.", json_schema_extra={"example": "Sheet1"})


class SearchRequest(BaseModel):

    text: str = Field(..., description="Text to filter rows by.", json_schema_extra={"example": "Alice"})


class SortRuleRequest(BaseModel):

    column: str = Field(..., description="Column name to sort by.", json_schema_extra={"example": "name"})

    ascending: bool = Field(default=True, description="Whether to sort in ascending order.")


class SortRequest(BaseModel):

    rules: list[SortRuleRequest] = Field(default_factory=list, description="Sort rules to apply.")


# ==========================================================
# Headers
# ==========================================================

class SpreadsheetHeadersResponse(ApiResponse):

    headers: list[str] = Field(default_factory=list, description="Visible column headers.")


# ==========================================================
# Data
# ==========================================================

class SpreadsheetDataResponse(SpreadsheetResponse):
    pass


# ==========================================================
# Search / Sort
# ==========================================================

class SearchResponse(SpreadsheetResponse):
    pass


class SortResponse(SpreadsheetResponse):
    pass


# ==========================================================
# Sheets
# ==========================================================

class SpreadsheetSheetsResponse(SpreadsheetResponse):
    pass


# ==========================================================
# Status
# ==========================================================

class SpreadsheetStatusResponse(ApiResponse):

    filename: str = Field(default="", description="Current workbook filename.")

    loaded: bool = Field(default=False, description="Whether a document is currently loaded.")

    modified: bool = Field(default=False, description="Whether the document has unsaved changes.")

    rows: int = Field(default=0, description="Number of visible rows.")

    columns: int = Field(default=0, description="Number of visible columns.")

