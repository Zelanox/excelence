import 'package:flutter/material.dart';

import '../../spreadsheet/models/document_name.dart';
import '../../spreadsheet/models/file_action_result.dart';

/// Asks for a document name (Save as, Rename). A name that is not
/// acceptable, or that the server refuses, is explained inside the dialog so
/// it can be corrected without starting over. Closes only on success or
/// Cancel.
class DocumentNameDialog extends StatefulWidget {
  const DocumentNameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.current,
    required this.onSubmit,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  /// The open document's name; typing it again is refused.
  final String current;

  /// Does the work with the typed text. The dialog stays open and shows the
  /// message when the result is not ok.
  final Future<FileActionResult> Function(String input) onSubmit;

  /// Returns the successful result, or null if cancelled.
  static Future<FileActionResult?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String initial,
    required String current,
    required Future<FileActionResult> Function(String input) onSubmit,
  }) {
    return showDialog<FileActionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentNameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initial: initial,
        current: current,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<DocumentNameDialog> createState() => _DocumentNameDialogState();
}

class _DocumentNameDialogState extends State<DocumentNameDialog> {
  late final TextEditingController _text;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _text = TextEditingController(text: widget.initial);
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }

    final check = checkDocumentName(_text.text, current: widget.current);

    if (!check.ok) {
      setState(() => _error = check.error);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await widget.onSubmit(_text.text);

    if (!mounted) {
      return;
    }

    if (result.ok) {
      Navigator.of(context).pop(result);
      return;
    }

    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Name',
                helperText: '.xlsx is added automatically',
                errorText: _error,
                errorMaxLines: 4,
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              const Text('Working...'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
