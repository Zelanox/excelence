import os

from fastapi import APIRouter, Depends, File, Request, UploadFile

from backend.dependencies import get_controller, get_registry, get_session
from backend.controller.controller import Controller
from backend.sessions import DocumentBusy, Session, SessionRegistry

from backend.api.models import *


router = APIRouter(
    prefix="/documents",
    tags=["Documents"]
)


def _client(http_request: Request) -> tuple[str | None, str | None]:
    """The caller's identity, from its headers (both may be absent)."""
    return (
        http_request.headers.get("x-client-id"),
        http_request.headers.get("x-client-name"),
    )


def _document_response(response_model, session: Session):
    """A DocumentResponse describing a session (the caller holds its lock)."""
    controller = session.controller

    return response_model(
        success=True,
        filename=controller.filename(),
        rows=controller.row_count(),
        columns=controller.column_count(),
        session=session.id
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
    http_request: Request,
    registry: SessionRegistry = Depends(get_registry)
):
    """Create a new workbook.

    A client that identifies itself (``X-Client-Id``) gets a real shared
    session: the file is written to disk straight away and the response
    carries the session id. It is refused if a document with that name
    already exists, rather than silently replacing it. A client with no
    identity gets the old single-document behavior.
    """
    client_id, client_name = _client(http_request)

    if client_id:
        try:
            session = registry.create(request.filename, client_id, client_name)
        except DocumentBusy as error:
            return CreateDocumentResponse(
                success=False,
                message=str(error),
                filename=request.filename
            )

        if session is None:
            return CreateDocumentResponse(
                success=False,
                message="Unable to create document.",
                filename=request.filename
            )

        with session.lock:
            return _document_response(CreateDocumentResponse, session)

    with registry.default.lock:
        if registry.is_open_in_session(request.filename):
            return CreateDocumentResponse(
                success=False,
                message="That document is open in a shared session.",
                filename=request.filename
            )

        controller = registry.default.controller
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
    controller: Controller = Depends(get_controller),
    registry: SessionRegistry = Depends(get_registry)
):
    """Upload a workbook (refused if it would overwrite one open in a shared session)."""
    # An upload overwrites a file of the same name, which would pull the
    # rug from under anyone editing it in a shared session.
    if registry.is_open_in_session(os.path.basename(file.filename or "")):
        return UploadDocumentResponse(
            success=False,
            message="That document is open in a shared session; close it first.",
            filename=file.filename or "",
        )

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
    http_request: Request,
    registry: SessionRegistry = Depends(get_registry)
):
    """Open a workbook.

    A client that identifies itself (``X-Client-Id``) JOINS the shared
    session for that file - loading it from disk only if nobody has it open
    yet, so people see each other's unsaved changes instead of each loading
    their own copy. The response carries the session id to send as
    ``X-Document`` from then on. A client with no identity gets the old
    single-document behavior (the file is loaded into the one shared slot).
    """
    client_id, client_name = _client(http_request)

    if client_id:
        try:
            session = registry.open(request.filename, client_id, client_name)
        except DocumentBusy as error:
            return OpenDocumentResponse(
                success=False,
                message=str(error),
                filename=request.filename
            )

        if session is None:
            return OpenDocumentResponse(
                success=False,
                message="Unable to open document.",
                filename=request.filename
            )

        with session.lock:
            return _document_response(OpenDocumentResponse, session)

    with registry.default.lock:
        if registry.is_open_in_session(request.filename):
            return OpenDocumentResponse(
                success=False,
                message="That document is open in a shared session.",
                filename=request.filename
            )

        controller = registry.default.controller
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
    controller: Controller = Depends(get_controller),
    registry: SessionRegistry = Depends(get_registry)
):
    """Rename a workbook (refused while either name is open in a shared session)."""
    if registry.is_open_in_session(request.old_name) or registry.is_open_in_session(request.new_name):
        return RenameDocumentResponse(
            success=False,
            message="That document is open in a shared session; close it first.",
            old_name=request.old_name,
            new_name=request.new_name
        )

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
    http_request: Request,
    session: Session = Depends(get_session),
    registry: SessionRegistry = Depends(get_registry)
):
    """Close the document - for a shared session, LEAVE it.

    Leaving removes this client; when the last client leaves, the session is
    saved and released. Other people still in the document are unaffected.
    """
    controller = session.controller
    filename = controller.filename()

    if session.is_default:
        success = controller.close_document()
        return CloseDocumentResponse(
            success=success,
            filename=filename
        )

    client_id, _ = _client(http_request)
    registry.leave(session, client_id)

    return CloseDocumentResponse(
        success=True,
        filename=filename
    )


@router.delete(
    "/{filename}",
    response_model=DeleteDocumentResponse
)
def delete_document(
    filename: str,
    controller: Controller = Depends(get_controller),
    registry: SessionRegistry = Depends(get_registry)
):
    """Delete a workbook (refused while it is open in a shared session)."""
    if registry.is_open_in_session(filename):
        return DeleteDocumentResponse(
            success=False,
            message="That document is open in a shared session; close it first.",
            filename=filename
        )

    success = controller.delete_document(filename)
    return DeleteDocumentResponse(
        success=success,
        filename=filename
    )