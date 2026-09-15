import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_globals.dart';

Future<void> selectAspectRatiosDialog(BuildContext context) async {
  // bool List for selected Ratios
  List<bool> selectedStates = g.commonAspectRatios
      .map(
        (ratioInfo) => g.availableAspectRatios.any(
          (availableRatioInfo) => ratioInfo.value == availableRatioInfo.value,
        ),
      )
      .toList();

  bool? selectionConfirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.crop,
              color: Theme.of(context).colorScheme.onSurface,
              size: 30,
            ),
            SizedBox(width: 12),
            Flexible(child: Text(tr("popup.aspectRatios.title"))),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr("popup.aspectRatios.text")),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: g.commonAspectRatios.length,
                    itemBuilder: (context, index) {
                      final aspect = g.commonAspectRatios[index];
                      return CheckboxListTile(
                        title: Text(aspect.name),
                        subtitle: Text(aspect.description),
                        value: selectedStates[index],
                        onChanged: (bool? value) {
                          selectedStates[index] = value ?? false;
                          (context as Element)
                              .markNeedsBuild(); // force UI refresh
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: Text(tr("popup.cancel")),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ElevatedButton(
            child: Text(tr("popup.update")),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );

  // Save only if confirmed
  if (selectionConfirmed == true) {
    g.availableAspectRatios = [
      for (int i = 0; i < g.commonAspectRatios.length; i++)
        if (selectedStates[i]) g.commonAspectRatios[i],
    ];
    await _saveAvailableAspectRatios();
  }
}

Future<void> _saveAvailableAspectRatios() async {
  final prefs = await SharedPreferences.getInstance();
  final values = g.availableAspectRatios
      .map((e) => e.value.toString())
      .toList();
  await prefs.setStringList("availableAspectRatios", values);
}
