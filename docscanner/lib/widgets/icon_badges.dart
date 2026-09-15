import 'package:flutter/material.dart';

class IconWithPlusBadge extends StatelessWidget {
  final IconData icon;

  const IconWithPlusBadge({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final double containerSize = 16.0;
    final double textScaleFactor = MediaQuery.of(context).textScaler.scale(1.0);
    final double fontSize = containerSize / textScaleFactor;

    return Stack(
      children: [
        Align(
          alignment:
              Alignment.center +
              Alignment(
                0.25 / textScaleFactor / textScaleFactor,
                0.25 / textScaleFactor / textScaleFactor,
              ),
          child: Icon(icon),
        ),
        Align(
          alignment:
              Alignment.topLeft +
              Alignment(
                -1 / textScaleFactor / textScaleFactor,
                -1 / textScaleFactor / textScaleFactor,
              ),
          child: SizedBox(
            width: containerSize + fontSize,
            height: containerSize + fontSize,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: containerSize,
                    height: containerSize,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    "+",
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class IconWithBadge extends StatelessWidget {
  final IconData icon;
  final IconData badgeIcon;
  final double mainIconSize;
  final Color iconColor;
  final Color bgColor;

  const IconWithBadge({
    super.key,
    required this.icon,
    required this.badgeIcon,
    required this.iconColor,
    required this.bgColor,
    required this.mainIconSize,
  });

  @override
  Widget build(BuildContext context) {
    final double badgeIconSize = mainIconSize / 1.25;
    final double constraintsSize = mainIconSize * 1.27;

    return SizedBox(
      width: constraintsSize,
      height: constraintsSize,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomRight + Alignment(0, 0),
            child: Icon(icon, size: mainIconSize, color: iconColor),
          ),
          Align(
            alignment: Alignment.topLeft + Alignment(0, 0),
            child: SizedBox(
              width: badgeIconSize + 1,
              height: badgeIconSize + 1,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: badgeIconSize + 1,
                      height: badgeIconSize + 1,
                      decoration: BoxDecoration(
                        color: bgColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      badgeIcon,
                      size: badgeIconSize,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
