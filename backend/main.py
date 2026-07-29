from fastapi import FastAPI

from backend.api.status import router as status_router
from backend.api.documents import router as documents_router
from backend.api.spreadsheet import router as spreadsheet_router

app = FastAPI(
    title="Excelence Backend",
    version="1.0.0"
)

app.include_router(status_router)
app.include_router(documents_router)
app.include_router(spreadsheet_router)

@app.get("/")
def root():
    return {
        "application": "Excelence",
        "status": "running"
    }