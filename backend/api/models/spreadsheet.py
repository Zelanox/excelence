<<<<<<< HEAD
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
=======
from .common import ApiResponse
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


# ==========================================================
# Headers
# ==========================================================

class SpreadsheetHeadersResponse(ApiResponse):

<<<<<<< HEAD
    headers: list[str] = Field(default_factory=list, description="Visible column headers.")
=======
    headers: list[str]
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


# ==========================================================
# Data
# ==========================================================

<<<<<<< HEAD
class SpreadsheetDataResponse(SpreadsheetResponse):
    pass


# ==========================================================
# Search / Sort
# ==========================================================

class SearchResponse(SpreadsheetResponse):
    pass


class SortResponse(SpreadsheetResponse):
    pass
=======
class SpreadsheetDataResponse(ApiResponse):

    rows: list[dict]
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


# ==========================================================
# Sheets
# ==========================================================

<<<<<<< HEAD
class SpreadsheetSheetsResponse(SpreadsheetResponse):
    pass
=======
class SpreadsheetSheetsResponse(ApiResponse):

    sheets: list[str]

    current_sheet: str
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


# ==========================================================
# Status
# ==========================================================

class SpreadsheetStatusResponse(ApiResponse):

<<<<<<< HEAD
    filename: str = Field(default="", description="Current workbook filename.")

    loaded: bool = Field(default=False, description="Whether a document is currently loaded.")

    modified: bool = Field(default=False, description="Whether the document has unsaved changes.")

    rows: int = Field(default=0, description="Number of visible rows.")

    columns: int = Field(default=0, description="Number of visible columns.")
=======
    filename: str

    loaded: bool

    modified: bool

    rows: int

    columns: int
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a

