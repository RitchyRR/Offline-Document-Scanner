import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_globals.dart';
import '../../app/app_navigation.dart';
import '../../app/app_runtime.dart';
import '../../app/feedback_helper.dart';
import '../../app/files_helper.dart';
import '../../app/global_notifier.dart';
import '../../app/image_prosessing_manager.dart';
import '../../app/isolates_manager.dart' show IsolatesManager;
import '../../app/metadata_helper.dart';
import '../../widgets/app_shadows.dart';
import '../../widgets/custom_expanding_button.dart';
import '../../widgets/custom_scrollbar.dart';
import '../../widgets/icon_badges.dart';
import '../../widgets/indicator_processing_image.dart';
import '../../widgets/pdf_page_view.dart';
import 'documents_view.dart';
import '../pages/pages_popup.dart';

class DocumentsHome extends StatefulWidget {
  const DocumentsHome({super.key});

  @override
  State<DocumentsHome> createState() => _DocumentsHomeState();
}

class _DocumentsHomeState extends State<DocumentsHome>
    with RouteAware, WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<String> _docThumbnails = [];
  bool _searchMode = false;
  bool _selectMode = false;
  final List<int> _selectedDocs = [];
  bool _keyboardWasVisible = false;

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
    _eventSubscription = globalNotifier.stream.listen(_handleGlobalEvent);
    WidgetsBinding.instance.addObserver(this);
    initAsync();
    _loadDocumentsView();
    _loadAvailableAspectRatios(context);
  }

  bool wasHidden = false;

  @override
  void didChangeMetrics() {
    final keyboardVisible = WidgetsBinding.instance.platformDispatcher.views
        .any((view) => view.viewInsets.bottom > 0);
    final keyboardWasDismissed = _keyboardWasVisible && !keyboardVisible;
    _keyboardWasVisible = keyboardVisible;
    if (keyboardWasDismissed &&
        _searchMode &&
        _searchController.text.trim().isEmpty) {
      _closeSearchMode();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden) wasHidden = true;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      imageProcessingManager.deleteNonEssentialVersionsOfAllDocuments();
    }
    if (state == AppLifecycleState.resumed) {
      if (wasHidden && !isTmpExternal) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!isTmpExternal && IsolatesManager().getIsolatesCount() == 0) {
            g.filesHelper.repairAll();
          }
        });
      }
      wasHidden = false;
    }
  }

  Future<void> initAsync() async {
    await _loadDocsDisplay(onInit: true);
    _initReceiveSharingIntent();
  }

  void _openSearchMode() {
    setState(() => _searchMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchMode) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearchMode() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() => _searchMode = false);
  }

  void _selectDocument(int docIndex) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedDocs.contains(docIndex)) {
        _selectedDocs.remove(docIndex);
      } else {
        _selectedDocs.add(docIndex);
        _selectedDocs.sort();
      }
      _selectMode = _selectedDocs.isNotEmpty;
    });
  }

  void _cancelSelectMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedDocs.clear();
      _selectMode = false;
    });
  }

  Future<void> _runSelectedDocumentAction(PopUpType type) async {
    final selectedDocs = List<int>.from(_selectedDocs);
    if (selectedDocs.length == 1) {
      if (!mounted) return;
      final completed = await showPagesPopup(
        context,
        [],
        type,
        selectedDocs.single,
      );
      if (completed && mounted) {
        _cancelSelectMode();
        if (type == PopUpType.delete) await _loadDocsDisplay();
      }
      return;
    }

    if (type == PopUpType.delete) {
      if (!mounted) return;
      final confirmed = await showDocumentsPopup(
        context,
        selectedDocs,
        PopUpType.delete,
      );
      if (!confirmed || !mounted) return;
      selectedDocs.sort((a, b) => b.compareTo(a));
      for (final docIndex in selectedDocs) {
        await g.filesHelper.deleteImages(context, docIndex);
      }
      if (mounted) {
        _cancelSelectMode();
        await _loadDocsDisplay();
      }
      return;
    }

    if (!mounted) return;
    final completed = await showDocumentsPopup(context, selectedDocs, type);
    if (completed && mounted) _cancelSelectMode();
  }

  Future<void> _mergeSelectedDocuments() async {
    if (_selectedDocs.length < 2 || !mounted) return;
    final selectedDocs = List<int>.from(_selectedDocs);
    final confirmed = await showMergeDocumentsConfirmation(
      context,
      selectedDocs,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr("documents.selection.merge.processing")),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            ),
          ],
        ),
        duration: const Duration(days: 1),
      ),
    );
    try {
      await g.filesHelper.mergeDocuments(selectedDocs);
      if (mounted) {
        messenger.hideCurrentSnackBar();
        _cancelSelectMode();
        await _loadDocsDisplay();
      }
    } catch (error, stackTrace) {
      dev.log("Error, mergeSelectedDocuments: $error", stackTrace: stackTrace);
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr("documents.selection.merge.error"))),
        );
      }
    }
  }

  Future<void> _duplicateSelectedDocument() async {
    if (_selectedDocs.length != 1 || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr("documents.selection.duplicate.processing")),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            ),
          ],
        ),
        duration: const Duration(days: 1),
      ),
    );
    try {
      await g.filesHelper.duplicateDocument(_selectedDocs.single);
      if (mounted) {
        messenger.hideCurrentSnackBar();
        _cancelSelectMode();
        await _loadDocsDisplay();
      }
    } catch (error, stackTrace) {
      dev.log(
        "Error, duplicateSelectedDocument: $error",
        stackTrace: stackTrace,
      );
      messenger.hideCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr("documents.selection.duplicate.error"))),
        );
      }
    }
  }

  bool _matchesSearchQuery(String value, String query) {
    final normalizedValue = value.toLowerCase().trim();
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedValue.contains(normalizedQuery)) return true;

    final compactValue = normalizedValue.replaceAll(RegExp(r'\s+'), '');
    final compactQuery = normalizedQuery.replaceAll(RegExp(r'\s+'), '');
    if (compactValue.contains(compactQuery)) return true;

    final queryTerms = normalizedQuery.split(RegExp(r'\s+'));
    final valueTerms = normalizedValue.split(RegExp(r'\s+'));
    return queryTerms.length > 1 &&
        queryTerms.every(
          (queryTerm) =>
              valueTerms.any((valueTerm) => valueTerm.contains(queryTerm)),
        );
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPopNext() {
    _loadDocsDisplay();
    _loadDocumentsView();
  }

  List<int> _deletedDocs = [];
  int _pdfRevision = 0;
  late final StreamSubscription<NotifierEvent> _eventSubscription;
  Future<void> _handleGlobalEvent(NotifierEvent event) async {
    if (!mounted) return;
    switch (event) {
      case NotifierEvent.loadDocsThumbnails:
        _pdfRevision++;
        _loadDocsDisplay();
        break;
      case NotifierEvent.setState:
        setState(() {});
        break;
      case NotifierEvent.imagesDeleted:
        _loadDocsDisplay();
        break;
      default:
    }
  }

  Future<(int, int)> _processDocument(List<String> photoPaths) async {
    var newDoc = await g.filesHelper.createNewDocument(photoPaths.length);
    int docIndex = newDoc.$1;
    int firstPageIndex = newDoc.$2;

    Future.microtask(() async {
      // Creation Date
      final now = DateTime.now();
      await g.metadataHelper.writeDocDate(
        docIndex,
        now.toString(),
        supressWarnings: true,
      );
      await imageProcessingManager.processPages(docIndex, 0, photoPaths, false);
    });

    return (docIndex, firstPageIndex);
  }

  Future<void> _openImagePicker(ImageSource source) async {
    List<String> photoPaths;
    ScaffoldMessengerState? messenger;
    if (g.filesHelper.pickingImage) return;
    if (source == ImageSource.camera) {
      photoPaths = await _openCamera();
    } else {
      final picked = await g.filesHelper.pickImage(context, source);
      photoPaths = picked.$1;
      messenger = picked.$2;
    }
    if (photoPaths.isEmpty) {
      messenger?.hideCurrentSnackBar();
      return;
    }

    final newIndexes = await _processDocument(photoPaths);
    int docIndex = newIndexes.$1;
    int firstPageIndex = newIndexes.$2;

    // only open PagePreview for first page
    messenger?.hideCurrentSnackBar();
    _openNewPagePreview(docIndex, firstPageIndex); //photoPaths.length == 1
  }

  Future<void> _openNewPagePreview(
    int docIndex,
    int pageIndex,
    //bool isSinglePage,
  ) async {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      //if (isSinglePage) {
      //  Navigator.pushNamed(
      //    context,
      //    "/preview",
      //    arguments: {"docIndex": docIndex, "pageIndex": 0},
      //  );
      //} else {
      Navigator.pushNamed(
        context,
        "/pages",
        arguments: {"docIndex": docIndex, "initialPageIndex": pageIndex},
      );
      //}
    });
  }

  Future<List<String>> _openCamera() async {
    g.filesHelper.pickingImage = true;
    final cameraResult = await Navigator.pushNamed(context, "/camera");
    List<String> photoPaths = cameraResult != null
        ? cameraResult as List<String>
        : [];
    g.filesHelper.pickingImage = false;
    return photoPaths;
  }

  bool _receivingIntentInitilaized = false;
  void _initReceiveSharingIntent() {
    if (_receivingIntentInitilaized) return;
    _receivingIntentInitilaized = true;
    // App launched by Opening/Sharing image(s)/pdf
    WidgetsFlutterBinding.ensureInitialized();
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) async {
      if (isTmpExternal) return;
      isTmpExternal = true;
      await _handleSharedFiles(value);
      await Future.delayed(Duration(milliseconds: 1500));
      isTmpExternal = false;
    });
    // While app is already running
    ReceiveSharingIntent.instance.getMediaStream().listen((
      List<SharedMediaFile> value,
    ) async {
      if (isTmpExternal) return;
      isTmpExternal = true;
      await _handleSharedFiles(value);
      await Future.delayed(Duration(milliseconds: 1500));
      isTmpExternal = false;
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    final pdfs = files
        .where((f) => f.path.toLowerCase().endsWith(".pdf"))
        .toList();
    final images = files.where((f) => f.type == SharedMediaType.image).toList();

    // PDFs
    if (pdfs.isNotEmpty) {
      for (final pdf in pdfs) {
        try {
          final docData = await imageProcessingManager.importPdf(pdf.path);
          _openDocument(docData.$1);
        } on PdfPageTooLargeException catch (e) {
          await Fluttertoast.showToast(
            msg: tr(
              "toast.e_pdfPageTooLarge",
              namedArgs: {
                "pageNumber": "${e.pageNumber}",
                "actualSize": g.filesHelper.formatBytes(e.actualBytes),
                "maxSize": g.filesHelper.formatBytes(e.maxBytes),
              },
            ),
            toastLength: Toast.LENGTH_LONG,
          );
        }
      }
    }
    // Images
    if (images.isNotEmpty) {
      final imagePaths = images.map((e) => e.path).toList();
      final newIndexes = await _processDocument(imagePaths);
      int docIndex = newIndexes.$1;
      int firstPageIndex = newIndexes.$2;
      _openNewPagePreview(docIndex, firstPageIndex); //photoPaths.length == 1
    }
  }

  List<int> _docPageCounts = [];
  List<String> _docNames = [];
  List<String> _docDates = [];
  List<double> _thumbnailRatios = [];
  int _docsCount = 0;
  int _displayDocsCount = 0;
  int _thumbnailLoadGeneration = 0;
  Future<void> _loadDocsDisplay({bool onInit = false}) async {
    final int loadGeneration = ++_thumbnailLoadGeneration;
    bool supressWarnings = onInit;
    // Thumbnails
    _deletedDocs = await g.filesHelper.getMarkedDeletedDocs();
    final thumbs = await g.filesHelper.getDocThumbnails();
    if (!mounted || loadGeneration != _thumbnailLoadGeneration) return;
    _docThumbnails = thumbs.$1;
    _docsCount = thumbs.$2;
    _displayDocsCount = _docsCount - _deletedDocs.length;
    // Page Counts
    _docPageCounts = List.generate(_docsCount, (_) => 0);
    for (var docIndex = 0; docIndex < _docsCount; docIndex++) {
      if (_deletedDocs.contains(docIndex)) continue;
      final pageCount = await g.filesHelper.getPagesCount(docIndex);
      _docPageCounts[docIndex] = pageCount;
      // reset ad supported doc/page unlocks
      if (onInit) g.metadataHelper.writeDocUnlocked(docIndex, false);
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        if (onInit) {
          g.metadataHelper.writePageUnlocked(docIndex, pageIndex, false);
        }
      }
    }
    // Document Metadata (Names, Dates, AspectRatios)
    _docNames = List.generate(_docsCount, (_) => "");
    _docDates = List.generate(_docsCount, (_) => "");
    List<double> newRatios = List.generate(_docsCount, (_) => math.sqrt1_2);

    for (int docIndex = 0; docIndex < _docsCount; docIndex++) {
      if (_deletedDocs.contains(docIndex)) continue;
      // Metadata
      _docDates[docIndex] =
          (await g.metadataHelper.readDocDate(docIndex)) ?? "";
      String? docName = await g.metadataHelper.readDocName(docIndex);
      if (docName != null) {
        _docNames[docIndex] = docName;
      } else {
        g.metadataHelper.writeDocName(docIndex, _docNames[docIndex]);
      }
      double? ratioValue = await MetadataHelper.readPageRatioValue(
        docIndex,
        0,
        supressWarnings: supressWarnings || _docThumbnails[docIndex].isEmpty,
      );
      if (ratioValue != null) newRatios[docIndex] = 1.0 / ratioValue;
    }
    _thumbnailRatios = newRatios;
    _loadingDocs = await _loadLoadingDocs(
      _docThumbnails,
      supressWarnings: supressWarnings,
    );

    if (mounted && loadGeneration == _thumbnailLoadGeneration) {
      setState(() {});
    }
  }

  List<bool> _loadingDocs = [];
  Future<List<bool>> _loadLoadingDocs(
    List<String> thumbnailPaths, {
    bool supressWarnings = false,
  }) async {
    List<bool> thumbnailsLoading = [];
    for (var docIndex = 0; docIndex < thumbnailPaths.length; docIndex++) {
      bool thumbnailLoading = false;
      if (thumbnailPaths[docIndex].isEmpty) {
        thumbnailLoading = true;
      } else {
        final oldNames = await MetadataHelper.readOldPageFileNames(
          docIndex,
          0,
          supressWarnings: supressWarnings,
        );
        if (oldNames != null) {
          for (var oldName in oldNames) {
            if (oldName.isNotEmpty &&
                thumbnailPaths[docIndex].contains(oldName)) {
              thumbnailLoading = true;
              break;
            }
          }
        }
      }
      thumbnailsLoading.add(thumbnailLoading);
    }
    return thumbnailsLoading;
  }

  void fixMetadataLengths(int length) {
    int namesShortBy = length - _docNames.length;
    for (var i = 0; i < namesShortBy; i++) {
      _docNames.add("");
    }
    int datesShortBy = length - _docDates.length;
    for (var i = 0; i < datesShortBy; i++) {
      _docDates.add("");
    }
    int ratiosShortBy = length - _thumbnailRatios.length;
    for (var i = 0; i < ratiosShortBy; i++) {
      _thumbnailRatios.add(1.0 / math.sqrt2);
    }
  }

  Future<void> _openDocument(int docIndex) async {
    if (_searchMode && _searchController.text.trim().isEmpty) {
      _closeSearchMode();
    }
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    //if (_docPageCounts[docIndex] == 1) {
    //  WidgetsBinding.instance.addPostFrameCallback((_) {
    //    Navigator.pushNamed(
    //      context,
    //      "/preview",
    //      arguments: {"docIndex": docIndex, "pageIndex": 0},
    //    );
    //  });
    //} else {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamed(context, "/pages", arguments: {"docIndex": docIndex});
    });
    //}
  }

  void _openDocEditDialog(
    BuildContext context,
    int docIndex,
    int displayDocIndex,
  ) async {
    int correctedDocIndex =
        docIndex - _deletedDocs.where((e) => e < docIndex).length;
    Future<void> isolatesFuture = imageProcessingManager.awaitAllIsolates();
    {
      bool allowChangeDocIndex = false;
      int? selectedIndex = await showDialog<int>(
        context: context,
        builder: (context) {
          int currentIndex = correctedDocIndex;
          TextEditingController nameController = TextEditingController(
            text: _docNames[docIndex],
          );

          return AlertDialog(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 30,
                ),
                SizedBox(width: 12),
                Flexible(
                  child: Text(
                    tr(
                      "documents.card.popup.title",
                      namedArgs: {"docIndex": "$displayDocIndex"},
                    ),
                  ),
                ),
              ],
            ),
            content: StatefulBuilder(
              builder: (context, setStateDialog) {
                isolatesFuture.whenComplete(() {
                  if (mounted) setStateDialog(() => allowChangeDocIndex = true);
                });
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TextField for custom document name
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: tr("documents.card.popup.name"),
                        hintText: tr(
                          "documents.docIndex",
                          namedArgs: {"docIndex": "$displayDocIndex"},
                        ),
                      ),
                      clipBehavior: Clip.hardEdge,
                    ),
                    SizedBox(height: 16),
                    // Dropdown for changing the index
                    TextButton(
                      onPressed: !allowChangeDocIndex
                          ? () => Fluttertoast.showToast(
                              msg: tr("loading.waitingOtherDocs"),
                            )
                          : null,
                      child: DropdownButtonFormField<int>(
                        decoration: InputDecoration(
                          labelText: tr("documents.card.popup.move"),
                        ),
                        initialValue: currentIndex,
                        isExpanded: true,
                        items: List.generate(
                          _displayDocsCount,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(
                              overflow: TextOverflow.ellipsis,
                              (i == docIndex)
                                  ? (nameController.text.trim().isNotEmpty)
                                        ? nameController.text.trim()
                                        : tr(
                                            "documents.docIndex",
                                            namedArgs: {"docIndex": "${i + 1}"},
                                          )
                                  : _docNames[i].isNotEmpty
                                  ? _docNames[i]
                                  : tr(
                                      "documents.docIndex",
                                      namedArgs: {"docIndex": "${i + 1}"},
                                    ),
                            ),
                          ),
                        ),
                        onChanged: allowChangeDocIndex
                            ? (int? newValue) {
                                if (newValue != null) {
                                  setStateDialog(() => currentIndex = newValue);
                                }
                              }
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr("popup.cancel")),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Save changes and close
                  String newName = nameController.text.trim();
                  if (newName.isNotEmpty && newName != _docNames[docIndex]) {
                    setState(() {
                      _docNames[docIndex] = newName;
                    });
                    await g.metadataHelper.writeDocName(
                      docIndex,
                      _docNames[docIndex],
                    );
                  }
                  if (context.mounted) Navigator.pop(context, currentIndex);
                },
                child: Text(tr("popup.ok")),
              ),
            ],
          );
        },
      );

      // Handle the result after the popup closes
      if (selectedIndex != null && selectedIndex != docIndex) {
        await g.filesHelper.moveDocumentIndex(correctedDocIndex, selectedIndex);
        _loadDocsDisplay();
      }
    }
  }

  Future<void> _loadAvailableAspectRatios(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final savedValues = prefs.getStringList("availableAspectRatios");

    if (savedValues == null || savedValues.isEmpty) {
      // localisation
      String? country;
      try {
        final Locale deviceLocale = ui.PlatformDispatcher.instance.locale;
        country = deviceLocale.countryCode;
      } catch (e) {
        dev.log("Error, loadAvailableAspectRatios: deviceLocale not available");
      }
      const imperialCountries = {"US", "LR", "MM"}; // USA, Liberia, Myanmar
      // Default values
      final List<double> defaultValues = [1, 4 / 3, 16 / 9, 21 / 9];
      if (country != null && imperialCountries.contains(country)) {
        defaultValues.add(11 / 8.5); // Letter US
        defaultValues.add(14 / 8.5); // Legal US
      } else {
        defaultValues.add(math.sqrt2); // DIN EU
      }
      g.availableAspectRatios = g.commonAspectRatios
          .where((e) => defaultValues.contains(e.value))
          .toList();
    } else {
      g.availableAspectRatios = g.commonAspectRatios
          .where((e) => savedValues.contains(e.value.toString()))
          .toList();
    }
  }

  Future<void> _shareAppDialog(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    controller.text = tr("popup.shareApp.text");
    final url = Uri(
      scheme: "https",
      host: "play.google.com",
      path: "/store/apps/details",
      queryParameters: {"id": "com.rrapps.docscanner"},
    );
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.share,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 30,
                ),
                SizedBox(width: 12),
                Flexible(child: Text(tr("popup.shareApp.title"))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: tr("popup.shareApp.hint"),
                  ),
                  onChanged: (text) {
                    setState(() {});
                  },
                ),
                SizedBox(height: 8),
                TextButton(
                  onPressed: () => launchUrl(url),
                  child: Text(url.toString()),
                ),
              ],
            ),

            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr("popup.cancel")),
              ),
              ElevatedButton.icon(
                icon: Icon(Icons.share),
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () {
                        final message = controller.text.trim();
                        final fullMessage =
                            "$message\n\nhttps://play.google.com/store/apps/details?id=com.rrapps.docscanner";
                        SharePlus.instance.share(
                          ShareParams(text: fullMessage),
                        );
                      },
                label: Text(tr("popup.share")),
              ),
            ],
          );
        },
      ),
    );
  }

  final _scrollController = CustomScrollController();
  DocumentsView? _documentsView;

  Future<void> _loadDocumentsView() async {
    final view = await DocumentsView.load();
    if (mounted) {
      setState(() {
        _documentsView = view;
      });
    }
  }

  Widget _buildDocumentActions(
    BuildContext context,
    int docIndex, {
    required bool compactView,
    required bool standardView,
  }) {
    if (compactView) {
      return PopupMenuButton<PopUpType>(
        tooltip: tr("documents.card.actions"),
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: PopUpType.save,
            onTap: () => showPagesPopup(context, [], PopUpType.save, docIndex),
            child: Row(
              children: [
                const Icon(Icons.save),
                const SizedBox(width: 12),
                Text(tr("fabs.save")),
              ],
            ),
          ),
          PopupMenuItem(
            value: PopUpType.share,
            onTap: () => showPagesPopup(context, [], PopUpType.share, docIndex),
            child: Row(
              children: [
                const Icon(Icons.share),
                const SizedBox(width: 12),
                Text(tr("fabs.share")),
              ],
            ),
          ),
          PopupMenuItem(
            value: PopUpType.delete,
            onTap: () =>
                showPagesPopup(context, [], PopUpType.delete, docIndex),
            child: Row(
              children: [
                const Icon(Icons.delete),
                const SizedBox(width: 12),
                Text(tr("fabs.delete")),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          visualDensity: standardView ? VisualDensity.compact : null,
          padding: standardView ? const EdgeInsets.all(4) : null,
          onPressed: () =>
              showPagesPopup(context, [], PopUpType.save, docIndex),
          icon: const Icon(Icons.save),
          tooltip: tr("fabs.save"),
        ),
        IconButton(
          visualDensity: standardView ? VisualDensity.compact : null,
          padding: standardView ? const EdgeInsets.all(4) : null,
          onPressed: () =>
              showPagesPopup(context, [], PopUpType.share, docIndex),
          icon: const Icon(Icons.share),
          tooltip: tr("fabs.share"),
        ),
        IconButton(
          visualDensity: standardView ? VisualDensity.compact : null,
          padding: standardView ? const EdgeInsets.all(4) : null,
          onPressed: () =>
              showPagesPopup(context, [], PopUpType.delete, docIndex),
          icon: const Icon(Icons.delete),
          tooltip: tr("fabs.delete"),
        ),
      ],
    );
  }

  // Documents
  @override
  Widget build(BuildContext context) {
    g.translateAspectRatios(context);
    _displayDocsCount = _docsCount - _deletedDocs.length;
    final searchQuery = _searchController.text.trim().toLowerCase();
    final visibleDocuments =
        <({int docIndex, int displayDocIndex, int matchPriority})>[];
    var displayDocIndex = 0;
    for (var docIndex = 0; docIndex < _docsCount; docIndex++) {
      if (_deletedDocs.contains(docIndex)) continue;
      displayDocIndex++;
      final docName = _docNames[docIndex].isNotEmpty
          ? _docNames[docIndex]
          : tr(
              "documents.docIndex",
              namedArgs: {"docIndex": "$displayDocIndex"},
            );
      final creationDate = _docDates[docIndex];
      final displayCreationDate = creationDate.isNotEmpty
          ? _formatDateLocalized(creationDate, context)
          : creationDate;
      final pagesCount = _docPageCounts.length > docIndex
          ? _docPageCounts[docIndex]
          : -1;
      final matchPriority =
          searchQuery.isEmpty || _matchesSearchQuery(docName, searchQuery)
          ? 0
          : pagesCount >= 0 && int.tryParse(searchQuery) == pagesCount
          ? 1
          : _matchesSearchQuery(displayCreationDate, searchQuery)
          ? 2
          : null;
      if (matchPriority != null) {
        visibleDocuments.add((
          docIndex: docIndex,
          displayDocIndex: displayDocIndex,
          matchPriority: matchPriority,
        ));
      }
    }
    visibleDocuments.sort((a, b) {
      final priorityComparison = a.matchPriority.compareTo(b.matchPriority);
      return priorityComparison != 0
          ? priorityComparison
          : a.docIndex.compareTo(b.docIndex);
    });
    final filteredRatios = visibleDocuments
        .map((document) => _thumbnailRatios[document.docIndex])
        .toList();
    final scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        titleSpacing: _searchMode && !_selectMode ? 0 : null,
        leading: _selectMode
            ? IconButton(
                onPressed: _cancelSelectMode,
                tooltip: tr("documents.selection.cancel"),
                icon: const Icon(Icons.close),
              )
            : _searchMode
            ? IconButton(
                onPressed: _closeSearchMode,
                tooltip: tr("documents.closeSearch"),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: _selectMode
            ? Text(
                tr(
                  _selectedDocs.length == 1
                      ? "documents.selection.selectedOne"
                      : "documents.selection.selected",
                  namedArgs: {"selectedCount": "${_selectedDocs.length}"},
                ),
              )
            : _searchMode
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style:
                    (Theme.of(context).appBarTheme.titleTextStyle ??
                            Theme.of(context).textTheme.titleLarge)
                        ?.copyWith(fontWeight: FontWeight.normal),
                decoration: InputDecoration(
                  hintText: tr("documents.search"),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                maxLines: 1,
                onChanged: (_) => setState(() {}),
              )
            : Text(tr("documents.title")),
        actions: [
          if (!_searchMode && !_selectMode && feedbackHelper.canShowInAppbar())
            CustomExpandingButton(
              onPressed: () async {
                await feedbackHelper.showRatingDialog(context);
                setState(() {});
              },
              icon: Icons.star_half,
              text: tr("documents.menu.feedback"),
            ),
          if (!_searchMode && !_selectMode)
            IconButton(
              onPressed: _openSearchMode,
              tooltip: tr("documents.search"),
              icon: const Icon(Icons.search),
            ),
          if (!_searchMode && !_selectMode)
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: "settings",
                  child: Row(
                    children: [
                      SizedBox(width: 8),
                      Icon(
                        Icons.settings,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      SizedBox(width: 10),
                      Text(
                        tr("settings.title"),
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!feedbackHelper.isHidden())
                  PopupMenuItem(
                    value: "feedback",
                    child: Row(
                      children: [
                        SizedBox(width: 8),
                        Icon(
                          feedbackHelper.onlyMail()
                              ? Icons.mail
                              : Icons.star_half,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: 10),
                        Text(
                          tr("documents.menu.feedback"),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: "shareApp",
                  child: Row(
                    children: [
                      SizedBox(width: 8),
                      Icon(
                        Icons.share,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      SizedBox(width: 10),
                      Text(
                        tr("documents.menu.shareApp"),
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                if (packageInfo.installerStore == "com.android.shell")
                  PopupMenuItem(
                    value: "errorLog",
                    child: Row(
                      children: [
                        SizedBox(width: 8),
                        Icon(
                          Icons.save_alt,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Save Error Log",
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onSelected: (String value) {
                switch (value) {
                  case "settings":
                    Navigator.pushNamed(context, "/settings");
                    break;
                  case "feedback":
                    feedbackHelper.showRatingDialog(context);
                    break;
                  case "shareApp":
                    _shareAppDialog(context);
                    break;
                  case "errorLog":
                    g.filesHelper.exportErrorLog();
                    break;
                }
              },
            ),
        ],
      ),
      body: visibleDocuments.isNotEmpty
          // Documents Cards
          ? CustomScrollbar(
              controller: _scrollController,
              pageAspectRatios: filteredRatios,
              scrollRangeStart: 0.1,
              scrollRangeEnd: 0.675,
              noTumb: true,

              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 240),
                itemCount: visibleDocuments.length,
                itemBuilder: (BuildContext context, int visibleIndex) {
                  final document = visibleDocuments[visibleIndex];
                  final docIndex = document.docIndex;
                  final displayDocIndex = document.displayDocIndex;
                  final String docName = _docNames[docIndex].isNotEmpty
                      ? _docNames[docIndex]
                      : tr(
                          "documents.docIndex",
                          namedArgs: {"docIndex": "$displayDocIndex"},
                        );
                  final String creationDate = _docDates[docIndex];
                  String displayCreationDate = creationDate.isNotEmpty
                      ? _formatDateLocalized(creationDate, context)
                      : creationDate;
                  int pagesCount = _docPageCounts.isNotEmpty
                      ? _docPageCounts[docIndex]
                      : -1;
                  final bool isLoading =
                      _loadingDocs.length <= docIndex || _loadingDocs[docIndex];
                  final documentsView = _documentsView ?? DocumentsView.compact;
                  final bool compactView =
                      documentsView == DocumentsView.compact;
                  final bool standardView =
                      documentsView == DocumentsView.standard;
                  final double cardHeight = switch (documentsView) {
                    DocumentsView.standard => 128.0,
                    DocumentsView.spacious => 160.0 * math.sqrt2,
                    DocumentsView.compact => 88.0,
                  };
                  final double thumbnailSlotWidth =
                      documentsView == DocumentsView.spacious
                      ? 184
                      : cardHeight;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _selectMode
                          ? () => _selectDocument(docIndex)
                          : null,
                      onLongPress: () => _selectDocument(docIndex),
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: compactView ? EdgeInsets.zero : null,
                        elevation: compactView ? 0 : 2.0,
                        color: compactView ? Colors.transparent : null,
                        child: SizedBox(
                          height: cardHeight,
                          child: Row(
                            children: [
                              // Document Info + Buttons (Left Side)
                              Expanded(
                                child: Card(
                                  margin: EdgeInsets.only(
                                    right: compactView ? 8 : 0,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: compactView ? 2 : 0,
                                  color: compactView
                                      ? null
                                      : Colors.transparent,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Document Info
                                      if (compactView)
                                        Flexible(
                                          child: InkWell(
                                            borderRadius:
                                                const BorderRadius.all(
                                                  Radius.circular(12.0),
                                                ),
                                            onTap: _selectMode
                                                ? () =>
                                                      _selectDocument(docIndex)
                                                : () => _openDocEditDialog(
                                                    context,
                                                    docIndex,
                                                    displayDocIndex,
                                                  ),
                                            onLongPress: () =>
                                                _selectDocument(docIndex),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    docName,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    [
                                                      tr(
                                                        pagesCount == 1
                                                            ? "documents.card.compactPageCount"
                                                            : "documents.card.compactPagesCount",
                                                        namedArgs: {
                                                          "pagesCount":
                                                              "$pagesCount",
                                                        },
                                                      ),
                                                      if (displayCreationDate
                                                          .isNotEmpty)
                                                        displayCreationDate,
                                                    ].join(" • "),
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withAlpha(150),
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        Flexible(
                                          child: InkWell(
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(12.0),
                                            ),
                                            onTap: _selectMode
                                                ? () =>
                                                      _selectDocument(docIndex)
                                                : () => _openDocEditDialog(
                                                    context,
                                                    docIndex,
                                                    displayDocIndex,
                                                  ),
                                            onLongPress: () =>
                                                _selectDocument(docIndex),
                                            child: Padding(
                                              padding: EdgeInsets.all(
                                                standardView ? 8 : 12,
                                              ),
                                              child: Builder(
                                                builder: (context) {
                                                  return Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        docName,
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: standardView
                                                            ? 2
                                                            : 5,
                                                      ),
                                                      SizedBox(
                                                        height: standardView
                                                            ? 4
                                                            : 6,
                                                      ),
                                                      displayCreationDate
                                                              .isNotEmpty
                                                          ? Text(
                                                              tr(
                                                                "documents.card.date",
                                                                namedArgs: {
                                                                  "creationDate":
                                                                      displayCreationDate,
                                                                },
                                                              ),
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurface
                                                                        .withAlpha(
                                                                          150,
                                                                        ),
                                                              ),
                                                            )
                                                          : SizedBox(),
                                                      SizedBox(
                                                        height:
                                                            displayCreationDate
                                                                .isNotEmpty
                                                            ? 4
                                                            : 0,
                                                      ),
                                                      Text(
                                                        tr(
                                                          "documents.card.pagesCount",
                                                          namedArgs: {
                                                            "pagesCount":
                                                                "$pagesCount",
                                                          },
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurface
                                                                  .withAlpha(
                                                                    150,
                                                                  ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      // Keep actions left of the thumbnail in a fixed position.
                                      if (!_selectMode)
                                        GestureDetector(
                                          onLongPress: () =>
                                              _selectDocument(docIndex),
                                          child: _buildDocumentActions(
                                            context,
                                            docIndex,
                                            compactView: compactView,
                                            standardView: standardView,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // Thumbnail (Right Side)
                              SizedBox(
                                width: compactView ? thumbnailSlotWidth : null,
                                child: Align(
                                  alignment: compactView
                                      ? Alignment.center
                                      : Alignment.centerRight,
                                  widthFactor: compactView ? null : 1,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: thumbnailSlotWidth,
                                    ),
                                    child: AspectRatio(
                                      aspectRatio:
                                          _thumbnailRatios.length > docIndex
                                          ? _thumbnailRatios[docIndex]
                                          : math.sqrt1_2,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          boxShadow: [bigBoxShadow(context)],
                                        ),
                                        child: Stack(
                                          fit: StackFit.passthrough,
                                          children: [
                                            // BG
                                            Material(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surfaceBright,
                                            ),
                                            // Thumbnail
                                            if (_docThumbnails.length >
                                                    docIndex &&
                                                _docThumbnails[docIndex]
                                                    .isNotEmpty)
                                              AnimatedSwitcher(
                                                duration: Duration(
                                                  milliseconds: 200,
                                                ),
                                                child: SizedBox.expand(
                                                  child:
                                                      _docThumbnails[docIndex]
                                                          .toLowerCase()
                                                          .endsWith(".pdf")
                                                      ? PdfPageView(
                                                          path:
                                                              _docThumbnails[docIndex],
                                                          cacheRevision:
                                                              _pdfRevision,
                                                        )
                                                      : Image.file(
                                                          File(
                                                            _docThumbnails[docIndex],
                                                          ),
                                                          fit: BoxFit.cover,
                                                          key: ValueKey(
                                                            _docThumbnails[docIndex],
                                                          ),
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) {
                                                                return Material(
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.surfaceBright,
                                                                  child: const Icon(
                                                                    Icons
                                                                        .broken_image,
                                                                  ),
                                                                );
                                                              },
                                                        ),
                                                ),
                                              ),
                                            // Loading Indicator
                                            if (isLoading)
                                              Positioned.fill(
                                                child: Material(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHigh
                                                      .withAlpha(150),
                                                ),
                                              ),
                                            if (_thumbnailRatios.length <=
                                                    docIndex ||
                                                _docThumbnails[docIndex]
                                                    .isEmpty ||
                                                isLoading)
                                              IndicatorProcessingImage(),
                                            if (_selectMode &&
                                                _selectedDocs.contains(
                                                  docIndex,
                                                ))
                                              Positioned.fill(
                                                child: Material(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withAlpha(150),
                                                ),
                                              ),
                                            Positioned.fill(
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: _selectMode
                                                      ? () => _selectDocument(
                                                          docIndex,
                                                        )
                                                      : () => _openDocument(
                                                          docIndex,
                                                        ),
                                                  onLongPress: () =>
                                                      _selectDocument(docIndex),
                                                  splashColor: Colors.black26,
                                                  highlightColor:
                                                      Colors.black26,
                                                ),
                                              ),
                                            ),
                                            if (_selectMode &&
                                                _selectedDocs.contains(
                                                  docIndex,
                                                ))
                                              Positioned.fill(
                                                child: Center(
                                                  child: CircleAvatar(
                                                    radius: 14,
                                                    backgroundColor: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    child: Icon(
                                                      Icons.check,
                                                      size: 18,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onPrimary,
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          : _displayDocsCount == 0
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Center(
                  child: Text(
                    textAlign: TextAlign.center,
                    tr("documents.addDoc"),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 32, 0, 95),
                    child: Image.asset(
                      "assets/arrow.png",
                      height: 360,
                      color: Theme.of(context).splashColor, // optional tint
                      fit: BoxFit.contain, // or BoxFit.cover, etc.
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Text(
                tr("documents.noSearchResults"),
                textAlign: TextAlign.center,
              ),
            ),
      // Floating Action Buttons
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _selectMode
            ? Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_selectedDocs.length == 1) ...[
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: FloatingActionButton(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        heroTag: "selectionDuplicateDocument",
                        onPressed: _duplicateSelectedDocument,
                        tooltip: tr("documents.selection.duplicate.tooltip"),
                        child: const Icon(Icons.file_copy),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_selectedDocs.length >= 2) ...[
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: FloatingActionButton(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        heroTag: "selectionMergeDocuments",
                        onPressed: _mergeSelectedDocuments,
                        tooltip: tr("documents.selection.merge.confirm"),
                        child: const Icon(Icons.unfold_less),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: FloatingActionButton(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      heroTag: "selectionDeleteDocument",
                      onPressed: () =>
                          _runSelectedDocumentAction(PopUpType.delete),
                      tooltip: tr("fabs.delete"),
                      child: const Icon(Icons.delete),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: FloatingActionButton(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      heroTag: "selectionSaveDocument",
                      onPressed: () =>
                          _runSelectedDocumentAction(PopUpType.save),
                      tooltip: tr("fabs.save"),
                      child: const Icon(Icons.save),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FloatingActionButton(
                    heroTag: "selectionShareDocument",
                    onPressed: () =>
                        _runSelectedDocumentAction(PopUpType.share),
                    tooltip: tr("fabs.share"),
                    child: const Icon(Icons.share),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: FloatingActionButton(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      heroTag: "pickImagesDoc",
                      onPressed: () {
                        _openImagePicker(ImageSource.gallery);
                      },
                      tooltip: tr("fabs.images"),
                      child: IconWithPlusBadge(icon: Icons.photo_library),
                    ),
                  ),
                  SizedBox(height: 18.0),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: FloatingActionButton(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      heroTag: "pickPdfDoc",
                      onPressed: () async {
                        final indexPairsList = await g.filesHelper.pickPdfToDoc(
                          context,
                        );
                        if (indexPairsList.isNotEmpty && context.mounted) {
                          _openDocument(indexPairsList.first.$1!);
                        }
                      },
                      tooltip: tr("fabs.pdfs"),
                      child: IconWithPlusBadge(icon: Icons.picture_as_pdf),
                    ),
                  ),
                  SizedBox(height: 18.0),
                  if (_picker.supportsImageSource(ImageSource.camera))
                    FloatingActionButton(
                      heroTag: "takePhotoDoc",
                      onPressed: () {
                        _openImagePicker(ImageSource.camera);
                      },
                      tooltip: tr("fabs.camera"),
                      child: const Icon(Icons.camera_alt),
                    ),
                ],
              ),
      ),
    );
    return PopScope(
      canPop: !_searchMode && !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectMode) {
          _cancelSelectMode();
        } else if (!didPop && _searchMode) {
          _closeSearchMode();
        }
      },
      child: scaffold,
    );
  }
}

String _formatDateLocalized(String dateString, BuildContext context) {
  final DateTime dateTime;
  try {
    dateTime = DateTime.parse(dateString);
  } catch (e) {
    dev.log("Warning, formatDateLocalized: '$dateString' wrong format");
    return dateString;
  }
  final String deviceLocaleString;
  try {
    final Locale deviceLocale = ui.PlatformDispatcher.instance.locale;
    deviceLocaleString = deviceLocale.toString();
  } catch (e) {
    dev.log("Error, formatDateLocalized: deviceLocale not available");
    return dateString;
  }
  final DateFormat localizedDateFormat = DateFormat.yMd(deviceLocaleString);
  return localizedDateFormat.format(dateTime);
}
