import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BottomInfoSheet extends StatelessWidget {
  const BottomInfoSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.panelBackground, // Dark semi-transparent was requested, this uses matching dark background
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.transparentWhite15,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          
          // Row 1: Grid Icon + Scanning text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.grid_3x3, // Hash icon for grid visualization
                color: AppTheme.primaryWhite,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Scanning 8×8 grid...',
                style: TextStyle(
                  color: AppTheme.primaryWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Row 2: Muted instructions
          const Text(
            'Point the camera at any waste object.\nDetection works across the entire frame.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.transparentWhite40,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
