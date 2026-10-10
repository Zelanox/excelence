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


class RenameColumnRequest(BaseModel):

    old_name: str = Field(..., description="Current column name.", json_schema_extra={"example": "age"})

    new_name: str = Field(..., description="New column name.", json_schema_extra={"example": "Age"})


class ColumnWidthRequest(BaseModel):

    name: str = Field(..., description="Column name to resize.", json_schema_extra={"example": "age"})

    width: float = Field(..., gt=0, description="New column width, in Excel character-width units.", json_schema_extra={"example": 18.5})


class CellEditItem(BaseModel):

    row: int = Field(..., ge=0, description="Row of the grid as currently shown.", json_schema_extra={"example": 0})

    column: int = Field(..., ge=0, description="Zero-based column index.", json_schema_extra={"example": 0})

    value: Any = Field(..., description="New value for the cell.", json_schema_extra={"example": "Alice"})


class AppendRowRequest(BaseModel):

    value: str = Field(default="", description="Value for the new row's first cell. Leave empty for a blank row.", json_schema_extra={"example": "Alice"})


class CellsEditRequest(BaseModel):

    edits: list[CellEditItem] = Field(..., min_length=1, description="Cells to update. Applied together as ONE undoable change; all-or-nothing.")


class TextStyleFields(BaseModel):
    """Text-style fields to SET. Omitted/null fields are left unchanged."""

    bold: bool | None = Field(default=None, description="Bold on/off.")

    italic: bool | None = Field(default=None, description="Italic on/off.")

    underline: bool | None = Field(default=None, description="Underline on/off.")

    strikethrough: bool | None = Field(default=None, description="Strikethrough on/off.")

    font_family: str | None = Field(default=None, description="Font family name.", json_schema_extra={"example": "Cairo"})

    font_size: float | None = Field(default=None, description="Font size in points (1-409).", json_schema_extra={"example": 14})

    color: str | None = Field(default=None, description="Text color as RRGGBB hex (a leading # is accepted).", json_schema_extra={"example": "FF0000"})

    background: str | None = Field(default=None, description="Cell fill as RRGGBB hex, or NONE for explicitly no fill.", json_schema_extra={"example": "FFF2CC"})


class CellStyleRequest(BaseModel):

    start_row: int = Field(..., ge=0, description="First row of the range, in visible-grid coordinates.")

    start_column: int = Field(..., ge=0, description="First column of the range.")

    end_row: int = Field(..., ge=0, description="Last row of the range (inclusive).")

    end_column: int = Field(..., ge=0, description="Last column of the range (inclusive).")

    style: TextStyleFields = Field(default_factory=TextStyleFields, description="Fields to set on every cell in the range.")

    reset: list[str] = Field(default_factory=list, description="Fields to return to 'inherit from the sheet default'.", json_schema_extra={"example": ["bold"]})


class AppearanceFields(BaseModel):
    """Sheet display settings to SET. Omitted/null fields are left unchanged."""

    grid_color: str | None = Field(default=None, description="Grid line color as RRGGBB hex.", json_schema_extra={"example": "D0D0D0"})

    banding: bool | None = Field(default=None, description="Alternating row colors on/off.")

    banding_color: str | None = Field(default=None, description="Color of the alternate rows as RRGGBB hex.", json_schema_extra={"example": "F2F2F2"})


class AppearanceRequest(BaseModel):

    style: AppearanceFields = Field(default_factory=AppearanceFields, description="Settings to set.")

    reset: list[str] = Field(default_factory=list, description="Settings to return to their built-in default.", json_schema_extra={"example": ["grid_color"]})


class CellRange(BaseModel):

    start_row: int = Field(..., ge=0, description="First row of the range.")

    start_column: int = Field(..., ge=0, description="First column of the range.")

    end_row: int = Field(..., ge=0, description="Last row of the range (inclusive).")

    end_column: int = Field(..., ge=0, description="Last column of the range (inclusive).")


class CellStylesRequest(BaseModel):

    ranges: list[CellRange] = Field(..., min_length=1, description="Rectangles to style. Applied together as ONE undoable change; all-or-nothing.")

    style: TextStyleFields = Field(default_factory=TextStyleFields, description="Fields to set on every cell in every range.")

    reset: list[str] = Field(default_factory=list, description="Fields to return to 'inherit from the sheet default'.", json_schema_extra={"example": ["bold"]})


class TextDefaultsRequest(BaseModel):

    style: TextStyleFields = Field(default_factory=TextStyleFields, description="Default text-style fields to set for the whole sheet.")

    reset: list[str] = Field(default_factory=list, description="Default fields to clear.")


class RtlRequest(BaseModel):

    rtl: bool = Field(..., description="True for right-to-left, False for left-to-right.", json_schema_extra={"example": True})


class RenameSheetRequest(BaseModel):

    old_name: str = Field(..., description="Current worksheet name.", json_schema_extra={"example": "Sheet1"})

    new_name: str = Field(..., description="New worksheet name.", json_schema_extra={"example": "Sheet1Renamed"})


class AddSheetRequest(BaseModel):

    name: str = Field(..., description="Worksheet name to create.", json_schema_extra={"example": "Sheet2"})


class DeleteSheetRequest(BaseModel):

    name: str = Field(..., description="Worksheet name to delete.", json_schema_extra={"example": "Sheet2"})


class SpreadsheetEditResponse(SpreadsheetResponse):
    pass
