import 'package:flutter/material.dart';

class CornerCell extends StatelessWidget {
  const CornerCell({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: const Text("◢"),
    );
  }
}