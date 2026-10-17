import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class ThumbnailWithBadge extends StatefulWidget {
  final XFile? image;
  final int count;
  final VoidCallback? onTap;

  const ThumbnailWithBadge({
    super.key,
    required this.image,
    required this.count,
    this.onTap,
  });

  @override
  State<ThumbnailWithBadge> createState() => _ThumbnailWithBadgeState();
}

class _ThumbnailWithBadgeState extends State<ThumbnailWithBadge> {
  String? _shownPath;

  @override
  void initState() {
    super.initState();
    _shownPath = widget.image?.path;
  }

  @override
  void didUpdateWidget(covariant ThumbnailWithBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newPath = widget.image?.path;
    if (newPath == _shownPath) return;
    if (newPath == null) {
      setState(() => _shownPath = null);
      return;
    }
    // Erst wechseln, wenn das neue Bild geladen ist – bis dahin bleibt das alte sichtbar
    precacheImage(FileImage(File(newPath)), context)
        .then((_) {
          if (mounted && widget.image?.path == newPath) {
            setState(() => _shownPath = newPath);
          }
        })
        .catchError((_) {});
  }

  Widget _buildCircle(String? path) {
    return Container(
      key: ValueKey<String?>(path),
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        image: path != null
            ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover)
            : null,
        color: Colors.white30,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = 16.0;
    final containerSize =
        MediaQuery.of(context).textScaler.scale(fontSize) * 1.5;
    return InkWell(
      onTap: widget.onTap,
      customBorder: const CircleBorder(),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          SizedBox(
            width: 55,
            height: 55,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipOval(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    // Neues Bild kommt von unten, altes geht nach oben weg
                    transitionBuilder: (child, animation) {
                      final isIncoming =
                          child.key == ValueKey<String?>(_shownPath);
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: isIncoming
                              ? const Offset(0, 1)
                              : const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      );
                    },
                    child: _buildCircle(_shownPath),
                  ),
                ),
                // Fester Rahmen, bewegt sich nicht mit den Thumbnails
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _shownPath != null
                            ? Colors.white
                            : Colors.white54,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.count > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: containerSize,
                height: containerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                alignment: Alignment.center,
                child: Text(
                  "${widget.count}",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
