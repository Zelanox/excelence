from pydantic import BaseModel

from .common import ApiResponse


# ==========================================================
# Requests
# ==========================================================

class OpenDocumentRequest(BaseModel):

    filename: str


# ==========================================================
# Responses
# ==========================================================

class DocumentListResponse(ApiResponse):

    documents: list[str]


class OpenDocumentResponse(ApiResponse):

    filename: str

    rows: int

    columns: int


class SaveDocumentResponse(ApiResponse):

    filename: str


class CloseDocumentResponse(ApiResponse):

    filename: str


class ReloadDocumentResponse(ApiResponse):

    filename: str


class RenameDocumentRequest(BaseModel):

    old_name: str

    new_name: str


class DeleteDocumentResponse(ApiResponse):

    filename: str


class RenameDocumentResponse(ApiResponse):

    old_name: str

    new_name: str


class SaveDocumentResponse(ApiResponse):

    filename: str

    modified: bool


class ReloadDocumentResponse(ApiResponse):

    filename: str

    rows: int

    columns: int


class CloseDocumentResponse(ApiResponse):

    filename: str