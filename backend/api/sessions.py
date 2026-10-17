from fastapi import APIRouter, Depends

from backend.dependencies import get_registry
from backend.sessions import SessionRegistry

from backend.api.models import *


router = APIRouter(
    prefix="/sessions",
    tags=["Sessions"]
)


@router.get(
    "",
    response_model=SessionListResponse
)
def list_sessions(
    registry: SessionRegistry = Depends(get_registry)
):
    """Every document currently open on the server and who is in it."""
    return SessionListResponse(
        success=True,
        sessions=registry.describe()
    )
