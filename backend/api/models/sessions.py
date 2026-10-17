from pydantic import BaseModel, Field

from .common import ApiResponse


class SessionClient(BaseModel):

    id: str = Field(..., description="The client's id.")

    name: str = Field(..., description="The client's display name.")


class SessionInfo(BaseModel):

    session: str = Field(..., description="Session id.")

    document: str = Field(..., description="The document open in this session.")

    modified: bool = Field(default=False, description="Whether it has unsaved changes.")

    clients: list[SessionClient] = Field(default_factory=list, description="Who currently has it open, in the order they joined.")


class SessionListResponse(ApiResponse):

    sessions: list[SessionInfo] = Field(default_factory=list, description="Every open document and who is in it.")
