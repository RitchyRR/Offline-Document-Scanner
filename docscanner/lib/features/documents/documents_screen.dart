import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
import '../pages/pages_popup.dart';
import '../pro/pro_purchase.dart';
import '../settings/aspect_ratio_settings.dart';
import '../settings/default_thumbnail_filter.dart';

class DocumentsHome extends StatefulWidget {
  const DocumentsHome({super.key});

  @override
  State<DocumentsHome> createState() => _DocumentsHomeState();
}

class _DocumentsHomeState extends State<DocumentsHome>
    with RouteAware, WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  List<String> _docThumbnails = [];

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
    _loadCompactDocumentsView();
    _loadAvailableAspectRatios(context);
  }

  bool wasHidden = false;
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

  @override
  void dispose() {
    _eventSubscription.cancel();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
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
  }

  List<int> _deletedDocs = [];
  late final StreamSubscription<NotifierEvent> _eventSubscription;
  Future<void> _handleGlobalEvent(NotifierEvent event) async {
    if (!mounted) return;
    switch (event) {
      case NotifierEvent.loadDocsThumbnails:
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
  bool? _compactDocumentsView;

  Future<void> _loadCompactDocumentsView() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _compactDocumentsView = prefs.getBool("compactDocumentsView") ?? true;
      });
    }
  }

  Future<void> _toggleCompactDocumentsView() async {
    if (_compactDocumentsView == null) return;
    _compactDocumentsView = !_compactDocumentsView!;
    _scrollController.reset();
    setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("compactDocumentsView", _compactDocumentsView!);
  }

  // Documents
  @override
  Widget build(BuildContext context) {
    g.translateAspectRatios(context);
    final visibleRatios = _thumbnailRatios
        .whereIndexed((index, element) => !_deletedDocs.contains(index))
        .toList();
    _displayDocsCount = _docsCount - _deletedDocs.length;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(tr("documents.title")),
        actions: [
          if (_compactDocumentsView != null)
            IconButton(
              onPressed: _toggleCompactDocumentsView,
              icon: _compactDocumentsView!
                  ? const Icon(Icons.format_list_bulleted)
                  : const Icon(Icons.list),
              tooltip: _compactDocumentsView!
                  ? tr("documents.views.spaciousView")
                  : tr("documents.views.compactView"),
            ),
          if (feedbackHelper.canShowInAppbar())
            CustomExpandingButton(
              onPressed: () async {
                await feedbackHelper.showRatingDialog(context);
                setState(() {});
              },
              icon: Icons.star_half,
              text: tr("documents.menu.feedback"),
            ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                value: "pro",
                child: Row(
                  children: [
                    SizedBox(width: 8),
                    Icon(
                      g.proUnlocked ? Icons.verified : Icons.lock,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    SizedBox(width: 10),
                    Text(
                      g.proUnlocked
                          ? tr("documents.menu.pro1")
                          : tr("documents.menu.pro2"),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: "licenses",
                child: Row(
                  children: [
                    SizedBox(width: 8),
                    Icon(
                      Icons.info,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    SizedBox(width: 10),
                    Text(
                      tr("documents.menu.licenses"),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: "ratios",
                child: Row(
                  children: [
                    SizedBox(width: 8),
                    Icon(
                      Icons.crop,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    SizedBox(width: 10),
                    Text(
                      tr("documents.menu.ratios"),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: "defaultFilter",
                child: Row(
                  children: [
                    SizedBox(width: 8),
                    Icon(
                      Icons.hide_image,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    SizedBox(width: 10),
                    Text(
                      tr("documents.menu.defaultFilter"),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                case "pro":
                  proPopup(context);
                case "licenses":
                  showLicensePage(
                    context: context,
                    applicationName: tr("appName"),
                    applicationVersion:
                        "${packageInfo.version}+${packageInfo.buildNumber}",
                  );
                  break;
                case "ratios":
                  selectAspectRatiosDialog(context);
                  break;
                case "defaultFilter":
                  showDefaultThumbnailVersionDialog(
                    context,
                    unlockPro: proPopup,
                  );
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
      body: _displayDocsCount > 0
          // Documents Cards
          ? CustomScrollbar(
              controller: _scrollController,
              pageAspectRatios: visibleRatios,
              scrollRangeStart: 0.1,
              scrollRangeEnd: 0.675,
              noTumb: true,

              child: ListView.builder(
                controller: _scrollController,
                itemCount: _displayDocsCount,
                itemBuilder: (BuildContext context, int docIndex) {
                  final displayDocIndex = docIndex + 1;
                  docIndex += _deletedDocs.where((e) => e <= docIndex).length;
                  String docName = _docNames[docIndex].isNotEmpty
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
                  final bool compactView = _compactDocumentsView ?? false;
                  final double cardHeight = compactView
                      ? 128.0
                      : 160.0 * math.sqrt2;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2.0,
                      child: SizedBox(
                        height: cardHeight,
                        child: Row(
                          children: [
                            // Document Info + Buttons (Left Side)
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Document Info
                                  Flexible(
                                    child: InkWell(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12.0),
                                      ),
                                      onTap: () => _openDocEditDialog(
                                        context,
                                        docIndex,
                                        displayDocIndex,
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.all(
                                          compactView ? 8 : 12,
                                        ),
                                        child: Builder(
                                          builder: (context) {
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  docName,
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: compactView ? 2 : 5,
                                                ),
                                                SizedBox(
                                                  height: compactView ? 4 : 6,
                                                ),
                                                displayCreationDate.isNotEmpty
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
                                                              Theme.of(context)
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
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withAlpha(150),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Button Column
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Save
                                      IconButton(
                                        visualDensity: compactView
                                            ? VisualDensity.compact
                                            : null,
                                        padding: compactView
                                            ? EdgeInsets.all(4)
                                            : null,
                                        onPressed: () => showPagesPopup(
                                          context,
                                          [],
                                          PopUpType.save,
                                          docIndex,
                                        ),
                                        icon: Icon(Icons.save),
                                        tooltip: tr("fabs.save"),
                                      ),
                                      // Share
                                      IconButton(
                                        visualDensity: compactView
                                            ? VisualDensity.compact
                                            : null,
                                        padding: compactView
                                            ? EdgeInsets.all(4)
                                            : null,
                                        onPressed: () => showPagesPopup(
                                          context,
                                          [],
                                          PopUpType.share,
                                          docIndex,
                                        ),
                                        icon: Icon(Icons.share),
                                        tooltip: tr("fabs.share"),
                                      ),
                                      // Delete
                                      IconButton(
                                        visualDensity: compactView
                                            ? VisualDensity.compact
                                            : null,
                                        padding: compactView
                                            ? EdgeInsets.all(4)
                                            : null,
                                        onPressed: () => showPagesPopup(
                                          context,
                                          [],
                                          PopUpType.delete,
                                          docIndex,
                                        ),
                                        icon: Icon(Icons.delete),
                                        tooltip: tr("fabs.delete"),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Thumbnail (Right Side)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compactView ? cardHeight : 184,
                              ), // space for creation date
                              child: AspectRatio(
                                aspectRatio: _thumbnailRatios.length > docIndex
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
                                      if (_docThumbnails.length > docIndex &&
                                          _docThumbnails[docIndex].isNotEmpty)
                                        AnimatedSwitcher(
                                          duration: Duration(milliseconds: 200),
                                          child: SizedBox.expand(
                                            child:
                                                _docThumbnails[docIndex]
                                                    .toLowerCase()
                                                    .endsWith(".pdf")
                                                ? PdfPageView(
                                                    path:
                                                        _docThumbnails[docIndex],
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
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .surfaceBright,
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
                                      if (_thumbnailRatios.length <= docIndex ||
                                          _docThumbnails[docIndex].isEmpty ||
                                          isLoading)
                                        IndicatorProcessingImage(),
                                      Positioned.fill(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () =>
                                                _openDocument(docIndex),
                                            onLongPress: () =>
                                                _openDocEditDialog(
                                                  context,
                                                  docIndex,
                                                  displayDocIndex,
                                                ),
                                            splashColor: Colors.black26,
                                            highlightColor: Colors.black26,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          : Column(
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
            ),
      // Floating Action Buttons
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
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
