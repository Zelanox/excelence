from typing import Any

from pydantic import BaseModel, Field

from .common import ApiResponse, SpreadsheetResponse


class CellEditRequest(BaseModel):

    row: int = Field(..., ge=0, description="Zero-based row index.", json_schema_extra={"example": 0})

    column: int = Field(..., ge=0, description="Zero-based column index.", json_schema_extra={"example": 0})

    value: Any = Field(..., description="New cell value.", json_schema_extra={"example": "Updated"})


class InsertRowRequest(BaseModel):

    index: int | None = Field(default=None, ge=0, description="Zero-based row insertion index.", json_schema_extra={"example": 1})


class DeleteRowRequest(BaseModel):

    index: int = Field(..., ge=0, description="Zero-based row index to delete.", json_schema_extra={"example": 1})


class InsertColumnRequest(BaseModel):

    name: str = Field(..., description="New column name.", json_schema_extra={"example": "age"})

    index: int | None = Field(default=None, ge=0, description="Zero-based column insertion index.", json_schema_extra={"example": 1})


class DeleteColumnRequest(BaseModel):

    name: str = Field(..., description="Existing column name to delete.", json_schema_extra={"example": "age"})


class RenameSheetRequest(BaseModel):

    old_name: str = Field(..., description="Current worksheet name.", json_schema_extra={"example": "Sheet1"})

    new_name: str = Field(..., description="New worksheet name.", json_schema_extra={"example": "Sheet1Renamed"})


class AddSheetRequest(BaseModel):

    name: str = Field(..., description="Worksheet name to create.", json_schema_extra={"example": "Sheet2"})


class DeleteSheetRequest(BaseModel):

    name: str = Field(..., description="Worksheet name to delete.", json_schema_extra={"example": "Sheet2"})


class SpreadsheetEditResponse(SpreadsheetResponse):
    pass
