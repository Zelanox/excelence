from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from backend.api.status import router as status_router
from backend.api.documents import router as documents_router
from backend.api.spreadsheet import router as spreadsheet_router
from backend.api.models.common import ErrorResponse
from backend.utils.logger import get_logger

logger = get_logger("main")

app = FastAPI(
    title="Excelence Backend",
    version="1.0.0",
    description="Local spreadsheet API for Excelence.",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Excelence is a local-first desktop/web app talking to a locally-run backend,
# so we allow any localhost/127.0.0.1 origin regardless of port (flutter run
# -d chrome picks a random port each launch). allow_credentials stays False
# since we don't use cookies - this keeps allow_origin_regex valid under CORS
# rules (browsers reject "*" + credentials=True together).
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(status_router)
app.include_router(documents_router)
app.include_router(spreadsheet_router)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Return a structured JSON error for invalid requests."""
    logger.warning("Validation error for %s: %s", request.url.path, exc)
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content=ErrorResponse(
            success=False,
            message="Invalid request payload.",
            detail=str(exc)
        ).model_dump()
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Return a safe JSON error for unexpected failures."""
    logger.exception("Unhandled API error for %s", request.url.path)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=ErrorResponse(
            success=False,
            message="Internal server error.",
            detail="Unexpected server error."
        ).model_dump()
    )


@app.get(
    "/",
    summary="Health check",
    description="Return the current backend availability state.",
    response_model=dict
)
def root():
    """Return the backend health status."""
    return {
        "application": "Excelence",
        "status": "running"
    }