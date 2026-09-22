from fastapi import APIRouter, Depends, File, UploadFile

from backend.dependencies import get_controller
from backend.controller.controller import Controller

from backend.api.models import *


router = APIRouter(
    prefix="/documents",
    tags=["Documents"]
)


@router.get(
    "",
    response_model=DocumentListResponse
)
def list_documents(
    controller: Controller = Depends(get_controller)
):

    return DocumentListResponse(

        documents=controller.list_documents()
    )


@router.get(
    "/browse",
    response_model=BrowseFolderResponse
)
def browse_folder(
    path: str = "",
    controller: Controller = Depends(get_controller)
):
    """List the subfolders and workbooks directly inside a folder, for
    file-browser navigation. `path` is relative to the documents root;
    omit it (or pass an empty string) to browse the root itself."""

    entries = controller.list_folder_entries(path)

    if entries is None:
        return BrowseFolderResponse(
            success=False,
            message="Invalid or inaccessible folder.",
            folder=path,
        )

    return BrowseFolderResponse(

        success=True,

        folder=path,

        folders=entries["folders"],

        documents=entries["documents"],
    )


@router.post(
    "/create",
    response_model=CreateDocumentResponse
)
def create_document(
    request: CreateDocumentRequest,
    controller: Controller = Depends(get_controller)
):

    success = controller.create_document(
        request.filename
    )

    return CreateDocumentResponse(

        success=success,

        filename=controller.filename(),

        rows=controller.row_count(),

        columns=controller.column_count()
    )


@router.post(
    "/upload",
    response_model=UploadDocumentResponse
)
async def upload_document(
    file: UploadFile = File(...),
    controller: Controller = Depends(get_controller)
):
    """Upload a workbook's raw bytes, saved directly to the documents
    root under the uploaded file's own name (any path components in
    the filename are stripped - uploads never land in a subfolder).
    Doesn't open the file as the active document; open it separately
    via POST /documents/open once it's uploaded."""

    data = await file.read()

    success = controller.upload_document(
        file.filename or "",
        data,
    )

    return UploadDocumentResponse(

        success=success,

        message="" if success else "Upload rejected: invalid filename or not an Excel file.",

        filename=file.filename or "",
    )


@router.post(
    "/open",
    response_model=OpenDocumentResponse
)
def open_document(
    request: OpenDocumentRequest,
    controller: Controller = Depends(get_controller)
):

    success = controller.open_document(
        request.filename
    )

    return OpenDocumentResponse(

        success=success,

        filename=controller.filename(),

        rows=controller.row_count(),

        columns=controller.column_count()
    )


@router.put(
    "/rename",
    response_model=RenameDocumentResponse
)
def rename_document(
    request: RenameDocumentRequest,
    controller: Controller = Depends(get_controller)
):

    success = controller.rename_document(

        request.old_name,

        request.new_name
    )

    return RenameDocumentResponse(

        success=success,

        old_name=request.old_name,

        new_name=request.new_name
    )


@router.post(
    "/save",
    response_model=SaveDocumentResponse
)
def save_document(
    controller: Controller = Depends(get_controller)
):

    success = controller.save_document()

    return SaveDocumentResponse(

        success=success,

        filename=controller.filename(),

        modified=controller.modified()
    )


@router.post(
    "/reload",
    response_model=ReloadDocumentResponse
)
def reload_document(
    controller: Controller = Depends(get_controller)
):

    success = controller.reload_document()

    return ReloadDocumentResponse(

        success=success,

        filename=controller.filename(),

        rows=controller.row_count(),

        columns=controller.column_count()
    )


@router.post(
    "/close",
    response_model=CloseDocumentResponse
)
def close_document(
    controller: Controller = Depends(get_controller)
):

    filename = controller.filename()

    success = controller.close_document()

    return CloseDocumentResponse(

        success=success,

        filename=filename
    )


@router.delete(
    "/{filename}",
    response_model=DeleteDocumentResponse
)
def delete_document(
    filename: str,
    controller: Controller = Depends(get_controller)
):

    success = controller.delete_document(filename)

    return DeleteDocumentResponse(

        success=success,

        filename=filename
    )