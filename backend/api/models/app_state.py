from typing import Any

from pydantic import BaseModel, Field


class AppStateResponse(BaseModel):

    last_document: str | None = Field(default=None, description="The most recently opened document (path relative to the documents folder), or null if there is none or it no longer exists.")

    preferences: dict[str, Any] = Field(default_factory=dict, description="Stored user preferences.")


class PreferenceRequest(BaseModel):

    key: str = Field(..., description="Preference name: lowercase letters, digits and underscores.", json_schema_extra={"example": "auto_search_after_add_row"})

    value: Any = Field(default=None, description="A JSON scalar: boolean, number, short string, or null.", json_schema_extra={"example": True})


class PreferenceResponse(BaseModel):

    success: bool = Field(..., description="Whether the preference was stored.")

    message: str = Field(..., description="Human-readable result.")
