from fastapi import APIRouter, Depends

from backend.dependencies import get_controller
from backend.controller.controller import Controller

from backend.api.models import *


router = APIRouter(
    prefix="/app-state",
    tags=["App state"]
)


@router.get(
    "",
    response_model=AppStateResponse
)
def get_app_state(
    controller: Controller = Depends(get_controller)
):
    """What the app should restore at startup: the last opened document and
    the user's preferences. Kept on the backend because the browser's own
    storage is tied to the page's port, which changes on every launch."""

    return AppStateResponse(
        last_document=controller.last_document(),
        preferences=controller.preferences()
    )


@router.post(
    "/preferences",
    response_model=PreferenceResponse
)
def set_preference(
    request: PreferenceRequest,
    controller: Controller = Depends(get_controller)
):
    """Store one user preference."""

    success = controller.set_preference(request.key, request.value)

    return PreferenceResponse(
        success=success,
        message="Preference saved." if success else "Unable to save preference."
    )
