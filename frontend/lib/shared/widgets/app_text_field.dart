import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.controller,
    required this.label,
    this.helperText,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.enableSuggestions,
    this.autocorrect,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool? enableSuggestions;
  final bool? autocorrect;
  final TextInputAction? textInputAction;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: autofillHints,
      enableSuggestions: enableSuggestions ?? !obscureText,
      autocorrect: autocorrect ?? !obscureText,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({
    required this.visible,
    required this.onPressed,
    super.key,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: visible ? 'Скрыть' : 'Показать',
      onPressed: onPressed,
      icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility),
    );
  }
}
