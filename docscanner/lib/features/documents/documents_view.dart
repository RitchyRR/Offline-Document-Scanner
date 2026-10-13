import 'package:shared_preferences/shared_preferences.dart';

enum DocumentsView {
  compact,
  medium,
  spacious;

  static const _preferenceKey = "documentsView";
  static const _legacyPreferenceKey = "compactDocumentsView";

  static Future<DocumentsView> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(
      _legacyPreferenceKey,
    ); // TODO: Remove this line once legacy preference is no longer needed
    final savedView = prefs.getString(_preferenceKey);
    final view = DocumentsView.values.firstWhere(
      (view) => view.name == savedView,
      orElse: () => DocumentsView.compact,
    );
    if (savedView == null) await view.save();
    return view;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, name);
  }
}
