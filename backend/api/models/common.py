from typing import Any

from pydantic import BaseModel, Field


# ==========================================================
# Base API Response
# ==========================================================

class ApiResponse(BaseModel):

    success: bool = Field(
        default=True,
        description="Whether the request completed successfully."
    )

    message: str = Field(
        default="",
        description="Optional status message describing the outcome."
    )


class DocumentResponse(ApiResponse):

    filename: str = Field(default="", description="Current workbook filename.")

    rows: int = Field(default=0, description="Number of visible rows.")

    columns: int = Field(default=0, description="Number of visible columns.")

    loaded: bool = Field(default=False, description="Whether a document is currently loaded.")

    modified: bool = Field(default=False, description="Whether the document has unsaved changes.")


class SpreadsheetResponse(ApiResponse):

    headers: list[str] = Field(default_factory=list, description="Visible column headers.")

    rows: list[dict[str, Any]] = Field(default_factory=list, description="Visible rows.")

    row_count: int = Field(default=0, description="Number of visible rows.")

    column_count: int = Field(default=0, description="Number of visible columns.")

    sheets: list[str] = Field(default_factory=list, description="Available worksheet names.")

    current_sheet: str = Field(default="", description="Active worksheet name.")


class StatusResponse(ApiResponse):

    status: str = Field(default="online", description="Current backend status.")

    filename: str = Field(default="", description="Current workbook filename.")

    loaded: bool = Field(default=False, description="Whether a document is currently loaded.")

    modified: bool = Field(default=False, description="Whether the document has unsaved changes.")

    rows: int = Field(default=0, description="Number of visible rows.")

    columns: int = Field(default=0, description="Number of visible columns.")


class ErrorResponse(ApiResponse):

    detail: str | None = Field(default=None, description="Error detail for the client.")