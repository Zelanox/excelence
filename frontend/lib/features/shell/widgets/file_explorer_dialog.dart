import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/services/spreadsheet_service.dart';

/// Which action the dialog is being used for - changes the bottom bar
/// (New needs a filename field and a "Create" button; Open needs an
/// enabled/disabled "Open" button tied to having a file selected) while
/// sharing the same folder-browsing UI for both.
enum FileExplorerMode { open, create }

/// Browses the backend's documents tree (via SpreadsheetController.
/// browseFolder, so it only ever sees what's under the server's
/// documents root - not the user's actual local filesystem) and
/// resolves to a document path relative to that root.
///
/// Returns the chosen path (e.g. "reports/q1.xlsx") on confirm, or null
/// if the user cancels. Doesn't touch the currently-open document itself
/// - the caller (FileMenu) is responsible for actually calling
/// loadDocument/newDocument with whatever path this resolves to.
class FileExplorerDialog extends StatefulWidget {
  const FileExplorerDialog({
    super.key,
    required this.spreadsheetController,
    required this.mode,
  });

  final SpreadsheetController spreadsheetController;
  final FileExplorerMode mode;

  static Future<String?> show(
    BuildContext context, {
    required SpreadsheetController spreadsheetController,
    required FileExplorerMode mode,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => FileExplorerDialog(
        spreadsheetController: spreadsheetController,
        mode: mode,
      ),
    );
  }

  @override
  State<FileExplorerDialog> createState() => _FileExplorerDialogState();
}

class _FileExplorerDialogState extends State<FileExplorerDialog> {
  // "" means the documents root. Path segments are joined with "/"
  // regardless of platform - this always matches what the backend's
  // browse/open/create endpoints expect, since path resolution there is
  // relative to DOCUMENTS_FOLDER using "/"-separated segments.
  String _currentFolder = '';

  Future<FolderEntries>? _entriesFuture;
  String? _selectedDocument;
  final TextEditingController _newFilenameController =
      TextEditingController();

  bool _uploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newFilenameController.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _selectedDocument = null;
      _uploadError = null;
      _entriesFuture =
          widget.spreadsheetController.browseFolder(_currentFolder);
    });
  }

  /// Opens the device's native file picker, uploads the chosen .xlsx to
  /// the backend's documents root, then re-browses the current folder
  /// so a newly uploaded file shows up immediately if the dialog
  /// happens to already be looking at the root (uploads always land at
  /// the root server-side, regardless of which folder is open here).
  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xltx', 'xltm'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;

    if (bytes == null) {
      setState(() {
        _uploadError = 'Could not read the selected file.';
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _uploading = true;
      _uploadError = null;
    });

    try {
      await widget.spreadsheetController.uploadDocument(picked.name, bytes);
      if (!mounted) return;
      _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadError = 'Upload failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  void _openFolder(String name) {
    _currentFolder = _currentFolder.isEmpty ? name : '$_currentFolder/$name';
    _load();
  }

  void _goUp() {
    final segments = _currentFolder.split('/');
    segments.removeLast();
    _currentFolder = segments.join('/');
    _load();
  }

  void _goToBreadcrumb(int index) {
    final segments = _currentFolder.split('/');
    _currentFolder = segments.sublist(0, index + 1).join('/');
    _load();
  }

  String _joinPath(String folder, String filename) {
    return folder.isEmpty ? filename : '$folder/$filename';
  }

  void _confirm() {
    if (widget.mode == FileExplorerMode.open) {
      if (_selectedDocument == null) return;
      Navigator.of(context).pop(
        _joinPath(_currentFolder, _selectedDocument!),
      );
      return;
    }

    final name = _newFilenameController.text.trim();
    if (name.isEmpty) return;

    final withExtension = name.toLowerCase().endsWith('.xlsx')
        ? name
        : '$name.xlsx';

    Navigator.of(context).pop(_joinPath(_currentFolder, withExtension));
  }

  @override
  Widget build(BuildContext context) {
    final breadcrumbSegments =
        _currentFolder.isEmpty ? <String>[] : _currentFolder.split('/');

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    widget.mode == FileExplorerMode.open
                        ? 'Open spreadsheet'
                        : 'New spreadsheet',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (widget.mode == FileExplorerMode.open)
                    _uploading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.upload_file),
                            onPressed: _pickAndUpload,
                            tooltip: 'Upload from this device',
                          ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cancel',
                  ),
                ],
              ),
            ),
            if (_uploadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _uploadError!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            _buildBreadcrumbs(breadcrumbSegments),
            const Divider(height: 1),
            Expanded(child: _buildEntryList()),
            const Divider(height: 1),
            if (widget.mode == FileExplorerMode.create) _buildFilenameField(),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(List<String> segments) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (segments.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: _goUp,
              tooltip: 'Up one level',
              visualDensity: VisualDensity.compact,
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _breadcrumbButton('Documents', () {
                    _currentFolder = '';
                    _load();
                  }),
                  for (int i = 0; i < segments.length; i++) ...[
                    const Text(' / '),
                    _breadcrumbButton(
                      segments[i],
                      () => _goToBreadcrumb(i),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumbButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildEntryList() {
    return FutureBuilder<FolderEntries>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load this folder: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          );
        }

        final entries = snapshot.data;
        if (entries == null ||
            (entries.folders.isEmpty && entries.documents.isEmpty)) {
          return const Center(
            child: Text(
              'This folder is empty.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView(
          children: [
            for (final folder in entries.folders)
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder, color: Colors.amber),
                title: Text(folder),
                onTap: () => _openFolder(folder),
              ),
            for (final document in entries.documents)
              ListTile(
                dense: true,
                leading: const Icon(Icons.description_outlined),
                title: Text(document),
                selected: _selectedDocument == document,
                selectedTileColor: Colors.blue.shade50,
                onTap: widget.mode == FileExplorerMode.open
                    ? () {
                        if (_selectedDocument == document) {
                          // Second tap on an already-selected file acts
                          // like a double-click/Enter: confirm and close.
                          _confirm();
                        } else {
                          setState(() => _selectedDocument = document);
                        }
                      }
                    : null,
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilenameField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _newFilenameController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Filename',
          hintText: 'e.g. budget.xlsx',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _confirm(),
      ),
    );
  }

  Widget _buildActionBar() {
    final canConfirm = widget.mode == FileExplorerMode.open
        ? _selectedDocument != null
        : _newFilenameController.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          // AnimatedBuilder-free rebuild: the filename field's onChanged
          // isn't wired to setState (ValueListenableBuilder below covers
          // it instead) so the Create button's enabled state stays in
          // sync as the user types without rebuilding the whole dialog
          // on every keystroke.
          if (widget.mode == FileExplorerMode.create)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _newFilenameController,
              builder: (context, value, _) {
                return FilledButton(
                  onPressed:
                      value.text.trim().isNotEmpty ? _confirm : null,
                  child: const Text('Create'),
                );
              },
            )
          else
            FilledButton(
              onPressed: canConfirm ? _confirm : null,
              child: const Text('Open'),
            ),
        ],
      ),
    );
  }
}