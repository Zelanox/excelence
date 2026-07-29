from fastapi import APIRouter, Depends

from backend.utils.logger import get_logger

from backend.dependencies import get_controller
from backend.controller.controller import Controller

from backend.api.models import *


router = APIRouter(
    prefix="/spreadsheet",
    tags=["Spreadsheet"]
)

logger = get_logger("api.spreadsheet")


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
        headers=controller.headers(),
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        sheets=controller.sheets(),
        current_sheet=controller.current_sheet()
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
        sheets=controller.sheets(),
        current_sheet=controller.current_sheet()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        rows=controller.data(),
        row_count=controller.row_count(),
        column_count=controller.column_count()
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
        sheets=controller.sheets(),
        current_sheet=controller.current_sheet()
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
        sheets=controller.sheets(),
        current_sheet=controller.current_sheet()
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
        sheets=controller.sheets(),
        current_sheet=controller.current_sheet()
    )