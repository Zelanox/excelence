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


class CreateDocumentRequest(BaseModel):

    filename: str = Field(
        ...,
        description="Workbook path or filename to create.",
        json_schema_extra={"example": "new.xlsx"}
    )



# ==========================================================
# Responses
# ==========================================================

class DocumentListResponse(ApiResponse):

    documents: list[str] = Field(default_factory=list, description="Available workbook filenames.")


class OpenDocumentResponse(DocumentResponse):
    pass


class CreateDocumentResponse(DocumentResponse):
    pass


class UploadDocumentResponse(ApiResponse):

    filename: str = Field(default="", description="The uploaded file's name, as stored at the documents root.")


class BrowseFolderResponse(ApiResponse):

    folder: str = Field(default="", description="Folder that was browsed, relative to the documents root.")

    folders: list[str] = Field(default_factory=list, description="Subfolder names directly inside this folder.")

    documents: list[str] = Field(default_factory=list, description="Workbook filenames directly inside this folder.")


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