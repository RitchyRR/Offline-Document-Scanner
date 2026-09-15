import 'dart:async';
import 'dart:developer' as dev;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/app_navigation.dart';
import 'app_shadows.dart';

class CustomExpandingButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String text;
  final Color? collapsedColor;

  const CustomExpandingButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.text,
    this.collapsedColor,
  });

  @override
  State<CustomExpandingButton> createState() => _CustomExpandingButtonState();
}

class _CustomExpandingButtonState extends State<CustomExpandingButton>
    with SingleTickerProviderStateMixin, RouteAware {
  static const animDuration = Duration(milliseconds: 350);

  bool _expanded = false;
  Timer? _collapseTimer;

  static const double _collapsedWidth = 40;
  static const double _buttonHeight = 40;

  @override
  void setState(ui.VoidCallback fn) {
    if (!mounted) {
      dev.log("Warning, setStateMounted not mounted at: ${StackTrace.current}");
      return;
    }
    super.setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(seconds: 2));
      if (mounted) {
        _expandButtonTemporarily();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 1500));
      if (mounted) {
        _expandButtonTemporarily();
      }
    });
  }

  void _expandButtonTemporarily() {
    setState(() {
      _expanded = true;
    });

    _collapseTimer = Timer(
      animDuration + const Duration(seconds: 4) + animDuration,
      () {
        if (mounted) {
          setState(() {
            _expanded = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = _expanded
        ? colorScheme.primaryContainer
        : colorScheme.primaryContainer.withAlpha(0);
    final textColor = _expanded
        ? colorScheme.onPrimaryContainer
        : widget.collapsedColor ?? colorScheme.onPrimaryContainer;
    final textWidth = _calculateTextWidth(widget.text);

    return Padding(
      padding: const EdgeInsets.all(4),
      child: AnimatedContainer(
        duration: animDuration,
        width: _expanded ? _collapsedWidth * 1.3 + textWidth : _collapsedWidth,
        height: _buttonHeight,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(32),
          boxShadow: _expanded ? [tinyBoxShadow(context)] : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(32),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: widget.onPressed,
            onLongPress: _expandButtonTemporarily,
            child: SizedBox.expand(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 8),
                    Icon(widget.icon, color: textColor),
                    if (_expanded)
                      Expanded(
                        child: AnimatedOpacity(
                          duration: animDuration,
                          opacity: _expanded ? 1.0 : 0.0,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              widget.text,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _calculateTextWidth(
    String text, {
    TextStyle style = const TextStyle(),
  }) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout();

    return textPainter.width * 1.2;
  }
}
