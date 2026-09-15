import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class ThumbnailWithBadge extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final fontSize = 16.0;
    final containerSize =
        MediaQuery.of(context).textScaler.scale(fontSize) * 1.5;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: image != null ? Colors.white : Colors.white54,
                width: 2,
              ),
              image: image != null
                  ? DecorationImage(
                      image: FileImage(File(image!.path)),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: Colors.white30,
            ),
          ),
          if (count > 0)
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
                  "$count",
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
