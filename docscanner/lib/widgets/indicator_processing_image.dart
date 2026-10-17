import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class IndicatorProcessingImage extends StatelessWidget {
  const IndicatorProcessingImage({
    super.key,
    this.text,
    this.showText = true,
    this.smallText = false,
  });

  final String? text;
  final bool showText;
  final bool smallText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        if (showText) ...[
          const SizedBox(height: 16),
          Text(
            text ?? tr("loading.processingImage"),
            textAlign: TextAlign.center,
            style: smallText
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}
