from typing import Any

from fastapi import APIRouter, Depends

from backend.utils.logger import get_logger

from backend.dependencies import get_controller, get_session
from backend.sessions import Session
from backend.controller.controller import Controller

from backend.api.models import *


router = APIRouter(
    prefix="/spreadsheet",
    tags=["Spreadsheet"]
)

logger = get_logger("api.spreadsheet")


def _grid_fields(controller: Controller) -> dict[str, Any]:
    """
    The complete grid payload shared by every grid-returning response.

    One snapshot of the active sheet (headers, rows, counts, column
    widths, direction, text styles) so no endpoint can forget a field.
    Before this existed each route listed its own subset, and any route
    that omitted `rtl`/`column_widths` made the client silently reset
    them (the client defaults a missing `rtl` to false).
    """
    data = controller.grid_data()

    return {
        "headers": data.headers,
        "rows": data.rows,
        "row_count": data.row_count,
        "column_count": data.column_count,
        "column_widths": data.column_widths,
        "rtl": data.rtl,
        "row_ids": data.row_ids,
        "column_ids": data.column_ids,
        "current_sheet_id": data.sheet_id,
        "cell_styles": data.cell_styles,
        "text_defaults": data.text_defaults,
        "appearance": data.appearance,
        "undo_depth": data.undo_depth,
        "redo_depth": data.redo_depth,
    }


UNDO_UNAVAILABLE = "Undo is unavailable while others are editing."


def _sheet_fields(controller: Controller) -> dict[str, Any]:
    """The worksheet list shared by every response that returns it: names,
    the active one, and the stable ID of each (an ID survives a rename)."""
    return {
        "sheets": controller.sheets(),
        "current_sheet": controller.current_sheet(),
        "sheet_ids": controller.sheet_ids(),
        "current_sheet_id": controller.current_sheet_id(),
    }


@router.get(
    "/headers",
    response_model=SpreadsheetHeadersResponse,
    summary="Get headers",
    description="Return the visible spreadsheet headers for the active worksheet."
)
def headers(
    controller: Controller = Depends(get_controller)
):
    """Return the visible spreadsheet headers."""
    return SpreadsheetHeadersResponse(
        success=True,
        message="Headers loaded.",
        headers=controller.headers()
    )


@router.get(
    "/data",
    response_model=SpreadsheetDataResponse
)
def data(
    controller: Controller = Depends(get_controller)
):
    """Return the visible spreadsheet rows."""
    return SpreadsheetDataResponse(
        success=True,
        message="Data loaded.",
        **_grid_fields(controller)
    )


@router.get(
    "/sheets",
    response_model=SpreadsheetSheetsResponse
)
def sheets(
    controller: Controller = Depends(get_controller)
):
    """Return the available worksheets and the current selection."""
    return SpreadsheetSheetsResponse(
        success=True,
        message="Sheets loaded.",
        **_sheet_fields(controller)
    )


@router.get(
    "/status",
    response_model=SpreadsheetStatusResponse
)
def status(
    controller: Controller = Depends(get_controller)
):
    """Return the current spreadsheet status summary."""
    info = controller.status()

    return SpreadsheetStatusResponse(
        success=True,
        message="Status loaded.",
        filename=info.filename,
        loaded=info.loaded,
        modified=info.modified,
        rows=info.rows,
        columns=info.columns
    )


@router.post(
    "/sheet",
    response_model=SpreadsheetSheetsResponse
)
def set_sheet(
    request: SheetRequest,
    controller: Controller = Depends(get_controller)
):
    """Switch to the requested worksheet."""
    success = controller.set_sheet(request.sheet_name)

    message = "Worksheet switched." if success else "Unable to switch worksheet."
    return SpreadsheetSheetsResponse(
        success=success,
        message=message,
        **_sheet_fields(controller)
    )


@router.post(
    "/search",
    response_model=SearchResponse
)
def search(
    request: SearchRequest,
    controller: Controller = Depends(get_controller)
):
    """Filter the visible rows using a search query."""
    success = controller.search(request.text)

    message = "Search applied." if success else "Unable to apply search."
    return SearchResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/search/clear",
    response_model=SearchResponse
)
def clear_search(
    controller: Controller = Depends(get_controller)
):
    """Clear the active search filter."""
    success = controller.clear_search()

    message = "Search cleared." if success else "Unable to clear search."
    return SearchResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/sort",
    response_model=SortResponse
)
def sort(
    request: SortRequest,
    controller: Controller = Depends(get_controller)
):
    """Apply multi-level sort rules to the visible rows."""
    rules = [
        {"column": rule.column, "ascending": rule.ascending}
        for rule in request.rules
    ]
    success = controller.sort(rules)

    message = "Sort applied." if success else "Unable to apply sort."
    return SortResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/sort/clear",
    response_model=SortResponse
)
def clear_sort(
    controller: Controller = Depends(get_controller)
):
    """Clear the active sort rules."""
    success = controller.clear_sort()

    message = "Sort cleared." if success else "Unable to clear sort."
    return SortResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/edit-cell",
    response_model=SpreadsheetEditResponse
)
def edit_cell(
    request: CellEditRequest,
    controller: Controller = Depends(get_controller)
):
    """Update a cell value in the active worksheet."""
    success = controller.edit_cell(request.row, request.column, request.value)

    message = "Cell updated." if success else "Unable to update cell."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/rows/insert",
    response_model=SpreadsheetEditResponse
)
def insert_row(
    request: InsertRowRequest,
    controller: Controller = Depends(get_controller)
):
    """Insert a row into the active worksheet."""
    success = controller.insert_row(request.index)

    message = "Row inserted." if success else "Unable to insert row."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/rows/delete",
    response_model=SpreadsheetEditResponse
)
def delete_row(
    request: DeleteRowRequest,
    controller: Controller = Depends(get_controller)
):
    """Delete a row from the active worksheet."""
    success = controller.delete_row(request.index)

    message = "Row deleted." if success else "Unable to delete row."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/columns/insert",
    response_model=SpreadsheetEditResponse
)
def insert_column(
    request: InsertColumnRequest,
    controller: Controller = Depends(get_controller)
):
    """Insert a new column into the active worksheet."""
    success = controller.insert_column(request.name, request.index)

    message = "Column inserted." if success else "Unable to insert column."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/columns/delete",
    response_model=SpreadsheetEditResponse
)
def delete_column(
    request: DeleteColumnRequest,
    controller: Controller = Depends(get_controller)
):
    """Delete a column from the active worksheet."""
    success = controller.delete_column(request.name)

    message = "Column deleted." if success else "Unable to delete column."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/columns/rename",
    response_model=SpreadsheetEditResponse
)
def rename_column(
    request: RenameColumnRequest,
    controller: Controller = Depends(get_controller)
):
    """Rename a column in the active worksheet."""
    success = controller.rename_column(request.old_name, request.new_name)

    message = "Column renamed." if success else "Unable to rename column."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/columns/width",
    response_model=SpreadsheetEditResponse
)
def set_column_width(
    request: ColumnWidthRequest,
    controller: Controller = Depends(get_controller)
):
    """Set a column's display width in the active worksheet."""
    success = controller.set_column_width(request.name, request.width)

    message = "Column width updated." if success else "Unable to update column width."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/rtl",
    response_model=SpreadsheetEditResponse
)
def set_rtl(
    request: RtlRequest,
    controller: Controller = Depends(get_controller)
):
    """Set the active worksheet's right-to-left direction."""
    success = controller.set_rtl(request.rtl)

    message = "Sheet direction updated." if success else "Unable to update sheet direction."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/rows/append",
    response_model=SpreadsheetEditResponse
)
def append_row(
    request: AppendRowRequest,
    controller: Controller = Depends(get_controller)
):
    """Add a row at the end of the data, optionally filling its first cell."""
    success = controller.append_row(request.value)

    message = "Row added." if success else "Unable to add row."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/edit-cells",
    response_model=SpreadsheetEditResponse
)
def edit_cells(
    request: CellsEditRequest,
    controller: Controller = Depends(get_controller)
):
    """Update several cells at once as one undoable change."""
    success = controller.edit_cells(
        [(edit.row, edit.column, edit.value) for edit in request.edits]
    )

    message = "Cells updated." if success else "Unable to update cells."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/undo",
    response_model=SpreadsheetEditResponse
)
def undo(session: Session = Depends(get_session)):
    """Undo the last content change (cell edits, styles, row/column changes).

    Refused while other people are in the document: undo restores a snapshot
    of the whole sheet and would erase their work too.
    """
    controller = session.controller

    if len(session.clients) > 1:
        return SpreadsheetEditResponse(
            success=False,
            message=UNDO_UNAVAILABLE,
            **_grid_fields(controller)
        )

    success = controller.undo()

    message = "Undone." if success else "Nothing to undo."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/redo",
    response_model=SpreadsheetEditResponse
)
def redo(session: Session = Depends(get_session)):
    """Redo the last undone change (refused while others are in the document, like undo)."""
    controller = session.controller

    if len(session.clients) > 1:
        return SpreadsheetEditResponse(
            success=False,
            message=UNDO_UNAVAILABLE,
            **_grid_fields(controller)
        )

    success = controller.redo()

    message = "Redone." if success else "Nothing to redo."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/cells/style",
    response_model=SpreadsheetEditResponse
)
def set_cell_style(
    request: CellStyleRequest,
    controller: Controller = Depends(get_controller)
):
    """Set or clear text-style fields on a rectangle of cells."""
    success = controller.set_cell_style(
        request.start_row,
        request.start_column,
        request.end_row,
        request.end_column,
        request.style.model_dump(exclude_none=True),
        request.reset
    )

    message = "Cell style updated." if success else "Unable to update cell style."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/cells/styles",
    response_model=SpreadsheetEditResponse
)
def set_cell_styles(
    request: CellStylesRequest,
    controller: Controller = Depends(get_controller)
):
    """Set or clear text-style fields on several rectangles at once (one undo step)."""
    success = controller.set_cell_style_ranges(
        [(r.start_row, r.start_column, r.end_row, r.end_column) for r in request.ranges],
        request.style.model_dump(exclude_none=True),
        request.reset
    )

    message = "Cell styles updated." if success else "Unable to update cell styles."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/appearance",
    response_model=SpreadsheetEditResponse
)
def set_appearance(
    request: AppearanceRequest,
    controller: Controller = Depends(get_controller)
):
    """Set or clear the active worksheet's grid color / alternating row colors."""
    success = controller.set_appearance(
        request.style.model_dump(exclude_none=True),
        request.reset
    )

    message = "Appearance updated." if success else "Unable to update appearance."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/text-defaults",
    response_model=SpreadsheetEditResponse
)
def set_text_defaults(
    request: TextDefaultsRequest,
    controller: Controller = Depends(get_controller)
):
    """Set or clear the active worksheet's default text style."""
    success = controller.set_text_defaults(
        request.style.model_dump(exclude_none=True),
        request.reset
    )

    message = "Text defaults updated." if success else "Unable to update text defaults."
    return SpreadsheetEditResponse(
        success=success,
        message=message,
        **_grid_fields(controller)
    )


@router.post(
    "/sheets/add",
    response_model=SpreadsheetSheetsResponse
)
def add_sheet(
    request: AddSheetRequest,
    controller: Controller = Depends(get_controller)
):
    """Create a worksheet in the active workbook."""
    success = controller.add_sheet(request.name)

    message = "Worksheet added." if success else "Unable to add worksheet."
    return SpreadsheetSheetsResponse(
        success=success,
        message=message,
        **_sheet_fields(controller)
    )


@router.post(
    "/sheets/delete",
    response_model=SpreadsheetSheetsResponse
)
def delete_sheet(
    request: DeleteSheetRequest,
    controller: Controller = Depends(get_controller)
):
    """Delete a worksheet from the active workbook."""
    success = controller.delete_sheet(request.name)

    message = "Worksheet deleted." if success else "Unable to delete worksheet."
    return SpreadsheetSheetsResponse(
        success=success,
        message=message,
        **_sheet_fields(controller)
    )


@router.post(
    "/sheets/rename",
    response_model=SpreadsheetSheetsResponse
)
def rename_sheet(
    request: RenameSheetRequest,
    controller: Controller = Depends(get_controller)
):
    """Rename a worksheet in the active workbook."""
    success = controller.rename_sheet(request.old_name, request.new_name)

    message = "Worksheet renamed." if success else "Unable to rename worksheet."
    return SpreadsheetSheetsResponse(
        success=success,
        message=message,
        **_sheet_fields(controller)
    )