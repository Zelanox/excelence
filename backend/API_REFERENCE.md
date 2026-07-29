# Excelence Backend API Reference

## Overview

This document describes the local spreadsheet API used by the Flutter frontend.

## Base response shape

All API responses include:

```json
{
  "success": true,
  "message": "Optional status message"
}
```

## Documents

### GET /documents

List available workbook files.

Response example:

```json
{
  "success": true,
  "message": "Documents listed.",
  "documents": ["sample.xlsx"]
}
```

### POST /documents/open

Open a workbook.

Request body:

```json
{
  "filename": "sample.xlsx"
}
```

Response example:

```json
{
  "success": true,
  "message": "Document opened.",
  "filename": "sample.xlsx",
  "rows": 2,
  "columns": 1,
  "loaded": true,
  "modified": false
}
```

### POST /documents/save

Save the active workbook.

### POST /documents/reload

Reload the active workbook.

### POST /documents/close

Close the active workbook.

### PUT /documents/rename

Rename a workbook.

Request body:

```json
{
  "old_name": "old.xlsx",
  "new_name": "new.xlsx"
}
```

### DELETE /documents/{filename}

Delete a workbook.

## Spreadsheet

### GET /spreadsheet/data

Return the current visible rows.

Response example:

```json
{
  "success": true,
  "message": "Data loaded.",
  "headers": ["name"],
  "rows": [{"name": "Alice"}],
  "row_count": 1,
  "column_count": 1,
  "sheets": ["Sheet1"],
  "current_sheet": "Sheet1"
}
```

### GET /spreadsheet/headers

Return the current headers.

### GET /spreadsheet/sheets

Return the available sheets.

### GET /spreadsheet/status

Return the spreadsheet status summary.

### POST /spreadsheet/sheet

Switch worksheet.

Request body:

```json
{
  "sheet_name": "Sheet1"
}
```

### POST /spreadsheet/search

Apply a text search.

Request body:

```json
{
  "text": "Alice"
}
```

### POST /spreadsheet/search/clear

Clear the active search.

### POST /spreadsheet/sort

Apply sorting.

Request body:

```json
{
  "rules": [{"column": "name", "ascending": true}]
}
```

### POST /spreadsheet/sort/clear

Clear sorting.

### POST /spreadsheet/edit-cell

Edit a specific cell.

Request body:

```json
{
  "row": 0,
  "column": 0,
  "value": "Updated"
}
```

### POST /spreadsheet/rows/insert

Insert a row.

Request body:

```json
{
  "index": 1
}
```

### POST /spreadsheet/rows/delete

Delete a row.

Request body:

```json
{
  "index": 1
}
```

### POST /spreadsheet/columns/insert

Insert a column.

Request body:

```json
{
  "name": "age",
  "index": 1
}
```

### POST /spreadsheet/columns/delete

Delete a column.

Request body:

```json
{
  "name": "age"
}
```

### POST /spreadsheet/sheets/add

Add a worksheet.

Request body:

```json
{
  "name": "Sheet2"
}
```

### POST /spreadsheet/sheets/delete

Delete a worksheet.

Request body:

```json
{
  "name": "Sheet2"
}
```

### POST /spreadsheet/sheets/rename

Rename a worksheet.

Request body:

```json
{
  "old_name": "Sheet1",
  "new_name": "Sheet1Renamed"
}
```
