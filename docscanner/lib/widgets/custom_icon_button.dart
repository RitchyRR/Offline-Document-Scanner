import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_shadows.dart';

class CustomIconButton extends StatelessWidget {
  const CustomIconButton({
    super.key,
    required this.onTap,
    this.width = 36.0,
    this.height = 36.0,
    this.buttonColor,
    this.icon = Icons.check,
    this.iconColor,
    this.isFlat = false,
    this.isHidden = false,
    this.isDisabled = false,
    required this.tooltip,
    this.child = const SizedBox(),
  });

  final VoidCallback? onTap;
  final double width;
  final double height;
  final Color? buttonColor;
  final IconData icon;
  final Color? iconColor;
  final bool isFlat;
  final bool isHidden;
  final bool isDisabled;
  final String? tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = math.min(width, height) / 2;
    return isHidden
        ? const Stack()
        : Stack(
            children: [
              Container(
                width: width,
                height: height,
                decoration: isFlat
                    ? null
                    : BoxDecoration(
                        color: isDisabled
                            ? Theme.of(context).disabledColor
                            : buttonColor ??
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: isDisabled
                            ? null
                            : [smallBoxShadow(context)],
                      ),
              ),
              SizedBox(
                width: width,
                height: height,
                child: Tooltip(
                  message: tooltip ?? "",
                  waitDuration: const Duration(milliseconds: 400),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(radius),
                      onTap: isDisabled ? null : onTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            color: isDisabled
                                ? Theme.of(context).disabledColor
                                : iconColor ??
                                      Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                          ),
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
  }
}
