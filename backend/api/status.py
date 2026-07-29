from fastapi import APIRouter
from fastapi import Depends

from backend.dependencies import get_controller
from backend.controller.controller import Controller


router = APIRouter()


@router.get("/status")
def status(
    controller: Controller = Depends(get_controller)
):

    return {
        "status": "online",
        "loaded": controller.is_loaded(),
        "modified": controller.modified()
    }