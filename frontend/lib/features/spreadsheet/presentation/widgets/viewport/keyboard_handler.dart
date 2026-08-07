import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyboardHandler extends StatelessWidget {
  const KeyboardHandler({
    super.key,
    required this.focusNode,
    required this.onKeyEvent,
    required this.child,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      focusNode: focusNode,
      onKeyEvent: (_, event) => onKeyEvent(event),
      child: child,
    );
  }
}