import 'package:flutter/material.dart';
import 'package:frontend/core/design/app_colors.dart';

void showResultSnackBar(
  BuildContext context, {
  required String message,
  required bool success,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: success ? AppColors.success : AppColors.danger,
    ),
  );
}
