import 'package:shared_preferences/shared_preferences.dart';

enum DocumentsView {
  standard,
  spacious,
  compact;

  static const _preferenceKey = "documentsView";
  static const _legacyPreferenceKey = "compactDocumentsView";

  static Future<DocumentsView> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedView = prefs.getString(_preferenceKey);
    if (savedView != null) {
      return DocumentsView.values.firstWhere(
        (view) => view.name == savedView,
        orElse: () => DocumentsView.compact,
      );
    }

    final legacyCompactView = prefs.getBool(_legacyPreferenceKey);
    final view = switch (legacyCompactView) {
      true => DocumentsView.standard,
      false => DocumentsView.spacious,
      null => DocumentsView.compact,
    };
    await prefs.setString(_preferenceKey, view.name);
    return view;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, name);
  }
}
