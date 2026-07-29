from fastapi import APIRouter, Depends

from backend.dependencies import get_controller
from backend.controller.controller import Controller

from backend.api.models import *


router = APIRouter(
    prefix="/spreadsheet",
    tags=["Spreadsheet"]
)


@router.get(
    "/headers",
    response_model=SpreadsheetHeadersResponse
)
def headers(
    controller: Controller = Depends(get_controller)
):

    return SpreadsheetHeadersResponse(

        headers=controller.headers()
    )


@router.get(
    "/data",
    response_model=SpreadsheetDataResponse
)
def data(
    controller: Controller = Depends(get_controller)
):

    return SpreadsheetDataResponse(

        rows=controller.data()
    )


@router.get(
    "/sheets",
    response_model=SpreadsheetSheetsResponse
)
def sheets(
    controller: Controller = Depends(get_controller)
):

    return SpreadsheetSheetsResponse(

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

    info = controller.status()

    return SpreadsheetStatusResponse(

        filename=info.filename,

        loaded=info.loaded,

        modified=info.modified,

        rows=info.rows,

        columns=info.columns
    )