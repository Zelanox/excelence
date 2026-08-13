import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyboardHandler extends StatefulWidget {
  const KeyboardHandler({
    super.key,
    required this.focusNode,
    required this.onKeyEvent,
    required this.child,
    this.onTextInput,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final Widget child;

  /// Called when actual text is entered through the keyboard.
  final ValueChanged<String>? onTextInput;

  @override
  State<KeyboardHandler> createState() => _KeyboardHandlerState();
}

class _KeyboardHandlerState extends State<KeyboardHandler> {
  late final TextEditingController _textController;
  late final FocusNode _textFocusNode;

  @override
  void initState() {
    super.initState();

    _textController = TextEditingController();
    _textFocusNode = FocusNode();

    _textController.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    _textFocusNode.dispose();

    super.dispose();
  }

  void _handleTextChanged() {
    if (_textController.text.isEmpty) {
      return;
    }

    final text = _textController.text;

    // Clear immediately so the same character can be entered again.
    _textController.clear();

    widget.onTextInput?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Focus(
          autofocus: true,
          focusNode: widget.focusNode,
          onKeyEvent: (_, event) => widget.onKeyEvent(event),
          child: widget.child,
        ),

        // Hidden text input used to receive real text input.
        Positioned(
          left: -1000,
          top: -1000,
          width: 1,
          height: 1,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _textController,
              focusNode: _textFocusNode,
              maxLines: 1,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}