import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CellEditor extends StatefulWidget {
  const CellEditor({
    super.key,
    required this.initialValue,
    required this.onCommit,
    required this.onCancel,
    this.replaceInitialValue = false,
  });

  final String initialValue;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;
  final bool replaceInitialValue;

  @override
  State<CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<CellEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _finished = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: widget.initialValue,
    );

    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _focusNode.requestFocus();

      if (widget.replaceInitialValue) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      } else {
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    if (_finished) {
      return;
    }

    _finished = true;

    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_finished) {
      return;
    }

    _finished = true;

    widget.onCancel();
  }

  KeyEventResult _handleKey(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // ------------------------------------------------------------
    // ENTER → COMMIT
    // ------------------------------------------------------------

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _commit();
      return KeyEventResult.handled;
    }

    // ------------------------------------------------------------
    // ESCAPE → CANCEL
    // ------------------------------------------------------------

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Focus(
        onKeyEvent: _handleKey,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: false,
          maxLines: 1,
          textInputAction: TextInputAction.done,
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
}