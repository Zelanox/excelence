from pydantic import BaseModel, Field

from .common import ApiResponse, DocumentResponse


# ==========================================================
# Requests
# ==========================================================

class OpenDocumentRequest(BaseModel):

    filename: str = Field(
        ...,
        description="Workbook path or filename to open.",
        json_schema_extra={"example": "sample.xlsx"}
    )


# ==========================================================
# Responses
# ==========================================================

class DocumentListResponse(ApiResponse):

    documents: list[str] = Field(default_factory=list, description="Available workbook filenames.")


class OpenDocumentResponse(DocumentResponse):
    pass


class SaveDocumentResponse(DocumentResponse):
    pass


class CloseDocumentResponse(DocumentResponse):
    pass


class ReloadDocumentResponse(DocumentResponse):
    pass


class RenameDocumentRequest(BaseModel):

    old_name: str = Field(..., description="Current workbook filename.", json_schema_extra={"example": "old.xlsx"})

    new_name: str = Field(..., description="Target workbook filename.", json_schema_extra={"example": "new.xlsx"})


class DeleteDocumentResponse(ApiResponse):

    filename: str = Field(default="", description="Workbook filename that was deleted.")


class RenameDocumentResponse(ApiResponse):

    old_name: str = Field(default="", description="Original workbook filename.")

    new_name: str = Field(default="", description="Updated workbook filename.")