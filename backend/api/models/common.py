from pydantic import BaseModel, Field


# ==========================================================
# Base API Response
# ==========================================================

class ApiResponse(BaseModel):

    success: bool = True

    message: str = Field(
        default="",
        description="Optional message."
    )