import 'package:flutter/material.dart';

class MixpanelButton extends StatelessWidget {
  MixpanelButton({required this.onPressed, required this.text});
  final GestureTapCallback onPressed;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        primary: Color(0xff4f44e0), // background
        onPrimary: Colors.white, // foreground
      ),
      onPressed: onPressed,
      child: Text(text),
    );
  }
}
