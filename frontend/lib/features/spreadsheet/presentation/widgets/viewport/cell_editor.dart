import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CellEditor extends StatefulWidget {
  const CellEditor({
    super.key,
    required this.initialValue,
    required this.onCommit,
    required this.onCancel,
    this.referenceInsertion,
  });

  final String initialValue;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;
  final ValueNotifier<String?>? referenceInsertion;

  @override
  State<CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<CellEditor> {
  late final TextEditingController _controller;

  // Receives keyboard events that bubble up from the TextField.
  late final FocusNode _keyboardFocusNode;

  // Owns the actual text input focus.
  late final FocusNode _textFieldFocusNode;

  bool _finished = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: widget.initialValue,
    );
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );

    widget.referenceInsertion?.addListener(_insertReference);

    _keyboardFocusNode = FocusNode(
      debugLabel: 'CellEditorKeyboardFocus',
    );

    _textFieldFocusNode = FocusNode(
      debugLabel: 'CellEditorTextFieldFocus',
    );
    _textFieldFocusNode.addListener(_handleTextFieldFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      // The TextField must own the actual input focus.
      _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.referenceInsertion?.removeListener(_insertReference);
    _textFieldFocusNode.removeListener(_handleTextFieldFocusChange);
    _controller.dispose();
    _keyboardFocusNode.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  void _handleTextFieldFocusChange() {
    if (!_textFieldFocusNode.hasFocus) {
      return;
    }

    _collapseSelectionAtEnd();
  }

  void _insertReference() {
    final reference = widget.referenceInsertion?.value;
    if (reference == null || reference.isEmpty) {
      return;
    }

    final selection = _controller.selection;
    final start = selection.start < 0
        ? _controller.text.length
        : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    final editorText =
        _controller.text.replaceRange(start, end, reference);

    debugPrint(
      '[FormulaReference.insert] reference="$reference" '
      'beforeText="${_controller.text}" oldSelection=$start:$end',
    );

    _controller.value = _controller.value.copyWith(
      text: editorText,
      selection: TextSelection.collapsed(
        offset: start + reference.length,
      ),
      composing: TextRange.empty,
    );
    debugPrint(
      '[FormulaReference.inserted] reference="$reference" '
      'afterText="$editorText" '
      'selection=${start + reference.length}:${start + reference.length}',
    );
    widget.referenceInsertion?.value = null;
  }

  // ============================================================
  // EDITING
  // ============================================================

  void _commit() {
    if (_finished) {
      return;
    }

    _finished = true;

    debugPrint('[CellEditor.commit] text="${_controller.text}"');

    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_finished) {
      return;
    }

    _finished = true;

    widget.onCancel();
  }

  // ============================================================
  // KEYBOARD
  // ============================================================

  KeyEventResult _handleKey(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // ENTER → commit
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _commit();

      return KeyEventResult.handled;
    }

    // ESCAPE → cancel
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();

      return KeyEventResult.handled;
    }

    // Everything else belongs to the TextField.
    return KeyEventResult.ignored;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Focus(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKey,
        child: TextField(
          controller: _controller,

          // This is the important change.
          focusNode: _textFieldFocusNode,

          autofocus: false,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.text,
          onTap: _collapseSelectionAtEnd,

          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: Colors.blue,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Colors.blue,
                width: 2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Colors.blue,
                width: 2,
              ),
            ),
          ),

          onSubmitted: (_) {
            _commit();
          },
        ),
      ),
    );
  }

  void _collapseSelectionAtEnd() {
    final end = _controller.text.length;
    _controller.selection = TextSelection.collapsed(offset: end);
  }
}