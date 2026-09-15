import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class IndicatorProcessingImage extends StatelessWidget {
  const IndicatorProcessingImage({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          text ?? tr("loading.processingImage"),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
