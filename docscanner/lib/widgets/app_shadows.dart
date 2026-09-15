import 'package:flutter/material.dart';

BoxShadow bigBoxShadow(BuildContext context) {
  return BoxShadow(
    color: Theme.of(context).shadowColor.withAlpha(125),
    blurRadius: 8,
    spreadRadius: -2,
    offset: const Offset(0, 4),
  );
}

BoxShadow smallBoxShadow(BuildContext context) {
  return BoxShadow(
    color: Theme.of(context).shadowColor.withAlpha(100),
    blurRadius: 3,
    spreadRadius: 0,
    offset: const Offset(0, 2),
  );
}

BoxShadow tinyBoxShadow(BuildContext context) {
  return BoxShadow(
    color: Theme.of(context).shadowColor.withAlpha(90),
    blurRadius: 1,
    spreadRadius: 0,
    offset: const Offset(0, 1),
  );
}
