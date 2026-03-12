import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TopBar extends StatefulWidget {
  final VoidCallback onBinSetupPressed;
  final VoidCallback onSwitchCameraPressed;

  const TopBar({
    super.key,
    required this.onBinSetupPressed,
    required this.onSwitchCameraPressed,
  });

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      color: AppTheme.background,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: Scanning Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.panelBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _pulseAnimation,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.scanningGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'SCANNING',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // Right side: Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bin Setup Button
              TextButton.icon(
                onPressed: widget.onBinSetupPressed,
                icon: const Icon(Icons.tune, size: 18, color: Colors.white),
                label: const Text(
                  'Bin Setup',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: AppTheme.panelBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Switch Camera Button
              IconButton(
                onPressed: widget.onSwitchCameraPressed,
                icon: const Icon(Icons.sync_alt, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.panelBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
