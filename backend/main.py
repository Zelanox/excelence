from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from backend.api.status import router as status_router
from backend.api.documents import router as documents_router
from backend.api.spreadsheet import router as spreadsheet_router
from backend.api.app_state import router as app_state_router
from backend.api.sessions import router as sessions_router
from backend.dependencies import registry
from backend.api.models.common import ErrorResponse
from backend.utils.logger import get_logger
from backend.utils.settings import LOCALHOST_ORIGIN_REGEX, load_settings, token_matches

logger = get_logger("main")

settings = load_settings()


def require_access_token(request: Request) -> None:
    """Reject requests without the shared access token, when one is configured."""
    if not token_matches(request.headers.get("authorization"), settings.access_token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid access token.",
            headers={"WWW-Authenticate": "Bearer"},
        )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Run code around the server's life: nothing at start, a save at stop.

    Replaces app.add_event_handler("shutdown", ...), which newer versions of
    Starlette (the library FastAPI is built on) no longer provide.
    """
    yield

    # Save any unsaved work when the server stops, so a shutdown can't lose
    # what autosave hadn't written yet.
    await run_in_threadpool(registry.save_all)


app = FastAPI(
    lifespan=lifespan,
    dependencies=[Depends(require_access_token)],
    title="Excelence Backend",
    version="1.0.0",
    description="Local spreadsheet API for Excelence.",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Which web pages may call the API from a browser. By default any
# localhost/127.0.0.1 origin regardless of port (flutter run -d chrome picks
# a random port each launch); a client served from another machine is
# allowed by listing its exact origin in EXCELENCE_ALLOWED_ORIGINS.
# allow_credentials stays False (the access token travels in a header, not a
# cookie), which keeps these rules valid - browsers reject "*" together with
# credentials=True.
app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.allowed_origins),
    allow_origin_regex=LOCALHOST_ORIGIN_REGEX if settings.allow_any_localhost else None,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(status_router)
app.include_router(documents_router)
app.include_router(spreadsheet_router)
app.include_router(app_state_router)
app.include_router(sessions_router)


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