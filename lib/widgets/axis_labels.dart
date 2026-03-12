import 'package:flutter/material.dart';

class YAxisLabels extends StatelessWidget {
  final double cellHeight;
  final bool right;

  const YAxisLabels({
    super.key,
    required this.cellHeight,
    this.right = false,
  });

  @override
  Widget build(BuildContext context) {
    // Y range: 2 to -2 (top to bottom) -> 5 labels total
    // The height of this column will be matching the camera preview height exactly.
    // Thus, labels need to be positioned at y = 0, cellHeight, 2*cellHeight, 3*cellHeight, 4*cellHeight
    
    return SizedBox(
      width: 24, // Fixed width for Y axis label area
      child: Stack(
        children: List.generate(5, (index) {
          final int value = 2 - index; // 2, 1, 0, -1, -2
          
          // Skip 0 on one axis to avoid clutter (we'll skip on Y if requested, or keep both. 
          // "Only label integers, skip 0 on one axis to avoid clutter". Let's skip it on Y)
          if (value == 0 && !right) return const SizedBox.shrink(); // Hide 0 on Y axis (left side)
          
          // Right side shows 'X' at the midpoint
          Widget labelWidget;
          if (right && value == 0) {
            labelWidget = Text(
              'X', // Swap axis or midpoint indicator as requested: "mirror of left, show the letter "X" at the midpoint"
              style: TextStyle(
                color: const Color.fromRGBO(255, 255, 255, 0.5),
                fontSize: 11,
              ),
            );
          } else if (right) {
            // "mirror of left"
             labelWidget = Text(
              value == 0 ? '' : value.toString(),
              style: TextStyle(
                color: const Color.fromRGBO(255, 255, 255, 0.5),
                fontSize: 11,
              ),
            );
          } else {
            labelWidget = Text(
              value.toString(),
              style: TextStyle(
                color: const Color.fromRGBO(255, 255, 255, 0.5),
                fontSize: 11,
              ),
            );
          }

          // Position the label centered vertically on the grid line
          return Positioned(
            top: (index * cellHeight) - 7, // -half of font size roughly to center text on line
            left: 0,
            right: 0,
            child: Center(
              child: labelWidget,
            ),
          );
        }),
      ),
    );
  }
}

class XAxisLabels extends StatelessWidget {
  final double cellWidth;

  const XAxisLabels({
    super.key,
    required this.cellWidth,
  });

  @override
  Widget build(BuildContext context) {
    // X range: -4 to 4 -> 9 labels
    return SizedBox(
      height: 20, // Fixed height for X axis label area
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(9, (index) {
          final int value = -4 + index; // -4, -3, -2, -1, 0, 1, 2, 3, 4
          
          return Positioned(
            left: (index * cellWidth) - 10, // approximate half width of text
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: 20,
              child: Center(
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    color: const Color.fromRGBO(255, 255, 255, 0.5),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
