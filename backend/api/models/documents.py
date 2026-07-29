<<<<<<< HEAD
from pydantic import BaseModel, Field

from .common import ApiResponse, DocumentResponse
=======
from pydantic import BaseModel

from .common import ApiResponse
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


# ==========================================================
# Requests
# ==========================================================

class OpenDocumentRequest(BaseModel):

<<<<<<< HEAD
    filename: str = Field(
        ...,
        description="Workbook path or filename to open.",
        json_schema_extra={"example": "sample.xlsx"}
    )
=======
    filename: str
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


# ==========================================================
# Responses
# ==========================================================

class DocumentListResponse(ApiResponse):

<<<<<<< HEAD
    documents: list[str] = Field(default_factory=list, description="Available workbook filenames.")


class OpenDocumentResponse(DocumentResponse):
    pass


class SaveDocumentResponse(DocumentResponse):
    pass


class CloseDocumentResponse(DocumentResponse):
    pass


class ReloadDocumentResponse(DocumentResponse):
    pass
=======
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
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


class RenameDocumentRequest(BaseModel):

<<<<<<< HEAD
    old_name: str = Field(..., description="Current workbook filename.", json_schema_extra={"example": "old.xlsx"})

    new_name: str = Field(..., description="Target workbook filename.", json_schema_extra={"example": "new.xlsx"})
=======
    old_name: str

    new_name: str
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


class DeleteDocumentResponse(ApiResponse):

<<<<<<< HEAD
    filename: str = Field(default="", description="Workbook filename that was deleted.")
=======
    filename: str
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a


class RenameDocumentResponse(ApiResponse):

<<<<<<< HEAD
    old_name: str = Field(default="", description="Original workbook filename.")

    new_name: str = Field(default="", description="Updated workbook filename.")
=======
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
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a
