import 'package:flutter/material.dart';
import 'package:frontend/core/design/app_colors.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.dns_outlined, size: 48, color: AppColors.primary),
            SizedBox(height: 18),
            Text(
              'NeoTelecom',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 18),
            SizedBox(width: 220, child: LinearProgressIndicator(minHeight: 4)),
          ],
        ),
      ),
    );
  }
}
