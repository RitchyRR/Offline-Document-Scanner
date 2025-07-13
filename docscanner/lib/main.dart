// my packages:
import 'app_globals.dart';
import 'files_helper.dart';
import 'metadata_helper.dart';
import 'image_prosessing_manager.dart';
import 'feedback_helper.dart';
// design:
import 'package:collection/collection.dart';
import 'package:docscanner/isolates_manager.dart' show IsolatesManager;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart'
    show MasonryGridView;
// monetization:
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// camera:
import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:permission_handler/permission_handler.dart';
// localisation:
import 'package:easy_localization/easy_localization.dart';
// dart:
import 'dart:io';
import 'dart:async'; // Timer
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'dart:ui' as ui;
// other:
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

final AdsHelper adsHelper = AdsHelper();
final FeedbackHelper feedbackHelper = FeedbackHelper();
final ImageProcessingManager imageProcessingManager = ImageProcessingManager();

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalNotifier globalNotifier = GlobalNotifier();
bool isTmpExternal = false;
late PackageInfo packageInfo;

class GlobalNotifier {
  final _controller = StreamController<NotifierEvent>.broadcast();
  Stream<NotifierEvent> get stream => _controller.stream;

  void triggerEvent(NotifierEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  CameraPlatform.instance = AndroidCameraCameraX();
  MobileAds.instance.initialize();
  //// Play Test Ads
  //MobileAds.instance.updateRequestConfiguration(
  //  RequestConfiguration(testDeviceIds: ["09BF6CED0A634AD6921EF7E4280CFAFC"]),
  //);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    //DeviceOrientation.portraitDown,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Errors -> log file
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    ErrorLogger.logError(details.exceptionAsString(), details.stack);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLogger.logError(error.toString(), stack);
    return true;
  };

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale("en"), Locale("de")],
      fallbackLocale: const Locale("en"),
      path: 'assets/lang',

      child: Provider<GlobalNotifier>.value(
        value: globalNotifier,
        child: MyApp(),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Future<(ColorScheme, ColorScheme)> generateAdaptiveColorSchemes() async {
    final corePalette = await DynamicColorPlugin.getCorePalette();
    // Fallback
    if (corePalette == null) {
      return (
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      );
    }

    final lightScheme = ColorScheme.fromSeed(
      seedColor: Color(corePalette.primary.get(40)),
      brightness: Brightness.light,
    );

    final darkScheme = ColorScheme.fromSeed(
      seedColor: Color(corePalette.primary.get(40)),
      brightness: Brightness.dark,
    );

    // Adjust specific elements for better contrast
    return (lightScheme, darkScheme);
  }

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
    initAsync();
  }

  Future<void> initAsync() async {
    packageInfo = await PackageInfo.fromPlatform();
    Future.microtask(() {
      if (mounted) {
        g.filesHelper.calculateScreenWidth(context);
      } else {
        dev.log("Warning, _MyAppState, initAsync(): not mounted");
      }
    });
    // Check if PRO unlocked
    final sStorage = FlutterSecureStorage();
    String? proUnlockedString;
    Object? error;
    try {
      proUnlockedString = await sStorage.read(key: "proUnlocked");
    } catch (e) {
      // Handle secure storage failure gracefully
      dev.log("SecureStorage read failed: $e");
      await sStorage.deleteAll();
      proUnlockedString = null;
      error = e;
    }
    g.proUnlocked = proUnlockedString == "true";
    setState(() {});
    // Check if PRO unlocked online
    initStoreInfo();
    if (error != null) {
      throw StateError("Error, initAsync, FlutterSecureStorage: $error");
    }
    g.filesHelper.repairDirectoryStructure();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(ColorScheme, ColorScheme)>(
      future: generateAdaptiveColorSchemes(),
      builder: (context, snapshot) {
        ColorScheme? lightTheme;
        ColorScheme? darkTheme;
        if (!snapshot.hasData) {
          lightTheme = ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          );
          darkTheme = ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          );
        } else {
          (lightTheme, darkTheme) = snapshot.data!;
        }

        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          navigatorKey: navigatorKey, // to pop until homepage from anywhere
          navigatorObservers: [routeObserver],
          title: "Offline Document Scanner",
          initialRoute: "/",
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case "/":
                return MaterialPageRoute(builder: (_) => DocumentsHome());

              case "/pages":
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder: (_) => Pages(
                    docIndex: args["docIndex"],
                    initialPageIndex: args["initialPageIndex"],
                  ),
                );

              case "/preview":
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder: (_) => PagePreview(
                    docIndex: args["docIndex"],
                    pageIndex: args["pageIndex"],
                  ),
                );

              case "/camera":
                return MaterialPageRoute(
                  builder: (context) => Theme(
                    data: Theme.of(context).copyWith(
                      brightness: Brightness.dark,
                    ), //for tooltips and splash effects
                    child: CameraScreen(),
                  ),
                );

              case "/warp":
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder: (_) => Warp(
                    pagePreviewState: args["pagePreviewState"],
                    docIndex: args["docIndex"],
                    pageIndex: args["pageIndex"],
                    imagePath: args["imagePath"],
                    cornerPoints: args["cornerPoints"],
                    rotation: args["rotation"],
                  ),
                );

              default:
                return MaterialPageRoute(builder: (_) => DocumentsHome());
            }
          },
          builder: FToastBuilder(),
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                // Set the predictive back transitions for Android.
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              },
            ),
            colorScheme: lightTheme,
            useMaterial3: true,
            //cardTheme: CardThemeData(color: lightTheme.surfaceContainerHigh),
            popupMenuTheme: PopupMenuThemeData(
              color: lightTheme.primaryContainer,
            ),
          ),
          darkTheme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                // Set the predictive back transitions for Android.
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              },
            ),
            colorScheme: darkTheme,
            useMaterial3: true,
            cardTheme: CardThemeData(color: darkTheme.surfaceContainerHigh),
            popupMenuTheme: PopupMenuThemeData(
              color: darkTheme.primaryContainer,
            ),
          ),
          themeMode: ThemeMode.system, // device controls theme
          home: const DocumentsHome(),
          onUnknownRoute: (_) =>
              MaterialPageRoute(builder: (_) => DocumentsHome()),
        );
      },
    );
  }
}

Future<void> loadDefaultThumbnailVersion() async {
  // Set Default Thumbnail Version
  final prefs = await SharedPreferences.getInstance();
  final String? defaultThumbnailString = prefs.getString(
    "defaultThumnailVersion",
  );
  int? defaultThumbnailIndex;
  if (defaultThumbnailString != null) {
    defaultThumbnailIndex = versionNamesInternal.indexOf(
      defaultThumbnailString,
    );
  }
  g.setDefaultIndex(defaultThumbnailIndex);
  prefs.setString(
    "defaultThumnailVersion",
    versionNamesInternal[g.defaultIndex],
  );
}

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
    _loadAvailableAspectRatios(context);
  }

  bool wasHidden = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden) wasHidden = true;
    if (state == AppLifecycleState.resumed) {
      if (wasHidden && !isTmpExternal) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!isTmpExternal && IsolatesManager().getIsolatesCount() == 0) {
            g.filesHelper.repairDirectoryStructure();
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
        _deletedDocs = await g.filesHelper.getMarkedDeletedDocs();
        setState(() {});
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
      g.metadataHelper.writeDocDate(
        docIndex,
        now.toString(),
        supressWarnings: true,
      );
      await Future.delayed(Duration(milliseconds: 50));
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
    _openNewPagePreview(docIndex, firstPageIndex);
  }

  Future<void> _openNewPagePreview(int docIndex, int pageIndex) async {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamed(
        context,
        "/pages",
        arguments: {"docIndex": docIndex, "initialPageIndex": pageIndex},
      );
    });
  }

  Future<List<String>> _openCamera() async {
    g.filesHelper.pickingImage = true;
    final result = await Navigator.pushNamed(context, "/camera");
    List<String> photoPaths = [];
    if (result is List<XFile>) {
      for (var xfile in result) {
        photoPaths.add(xfile.path);
      }
    }
    g.filesHelper.pickingImage = false;
    return photoPaths;
  }

  bool _receivingIntentInitilaized = false;
  _initReceiveSharingIntent() {
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
        final docData = await imageProcessingManager.importPdf(pdf.path);
        _openDocument(docData.$1);
      }
    }
    // Images
    if (images.isNotEmpty) {
      final imagePaths = images.map((e) => e.path).toList();
      final newIndexes = await _processDocument(imagePaths);
      int docIndex = newIndexes.$1;
      int firstPageIndex = newIndexes.$2;
      _openNewPagePreview(docIndex, firstPageIndex);
    }
  }

  List<int> _docPageCounts = [];
  List<String> _docNames = [];
  List<String> _docDates = [];
  List<double> _thumbnailRatios = [];
  int _docsCount = 0;
  Future<void> _loadDocsDisplay({bool onInit = false}) async {
    bool supressWarnings = onInit;
    // Thumbnails
    var thumbs = await g.filesHelper.getDocThumbnails();
    List<String> thumbnailPaths = thumbs.$1;
    _docsCount = thumbs.$2;
    // Page Counts
    _docPageCounts = [];
    for (var docIndex = 0; docIndex < _docsCount; docIndex++) {
      _docPageCounts.add(await g.filesHelper.getPagesCount(docIndex));
      // reset ad supported doc/page unlocks
      if (onInit) g.metadataHelper.writeDocUnlocked(docIndex, false);
      for (
        var pageIndex = 0;
        pageIndex < _docPageCounts[docIndex];
        pageIndex++
      ) {
        if (onInit) {
          g.metadataHelper.writePageUnlocked(docIndex, pageIndex, false);
        }
      }
    }
    // Document Metadata (Names, Dates, AspectRatios)
    _docNames = List.generate(_docsCount, (_) => "");
    _docDates = List.generate(_docsCount, (_) => "");
    List<double> newThumbnailRatios = List.generate(
      _docsCount,
      (_) => 1.0 / math.sqrt2,
    ); // first collect here, because random setState()s will otherwise show wrong ratios, while still awaiting all ratios

    for (int docIndex = 0; docIndex < _docsCount; docIndex++) {
      _docDates[docIndex] =
          (await g.metadataHelper.readDocDate(docIndex)) ?? "";
      String? docName = await g.metadataHelper.readDocName(docIndex);
      if (docName != null) {
        _docNames[docIndex] = docName;
      } else {
        g.metadataHelper.writeDocName(docIndex, _docNames[docIndex]);
      }
      double ratioValue =
          await MetadataHelper.readPageRatioValue(
            docIndex,
            0,
            supressWarnings:
                supressWarnings || thumbnailPaths[docIndex].isEmpty,
          ) ??
          math.sqrt2;
      newThumbnailRatios[docIndex] = 1.0 / ratioValue;
    }
    _thumbnailRatios = newThumbnailRatios;
    _deletedDocs = await g.filesHelper.getMarkedDeletedDocs();
    _loadingDocs = await _loadLoadingDocs(thumbnailPaths);

    // Refresh Display
    if (mounted) {
      setState(() {
        _docThumbnails = thumbnailPaths;
      });
    }
  }

  List<bool> _loadingDocs = [];
  Future<List<bool>> _loadLoadingDocs(List<String> thumbnailPaths) async {
    List<bool> thumbnailsLoading = [];
    for (var docIndex = 0; docIndex < thumbnailPaths.length; docIndex++) {
      bool thumbnailLoading = false;
      if (thumbnailPaths[docIndex].isEmpty) {
        thumbnailLoading = true;
      } else {
        final oldNames = await MetadataHelper.readOldPageFileNames(docIndex, 0);
        if (oldNames != null) {
          for (var oldName in oldNames) {
            if (oldName.isNotEmpty &&
                thumbnailPaths[docIndex].contains(oldName)) {
              thumbnailLoading = true;
              break;
            }
          }
        } else {
          thumbnailLoading = true;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamed(context, "/pages", arguments: {"docIndex": docIndex});
    });
  }

  void _openDocEditDialog(
    BuildContext context,
    int docIndex,
    int displayDocIndex,
  ) async {
    Future<void> isolatesFuture = imageProcessingManager.awaitAllIsolates();
    {
      bool allowChangeDocIndex = false;
      int? selectedIndex = await showDialog<int>(
        context: context,
        builder: (context) {
          int currentIndex = docIndex;
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
              builder: (context, setState) {
                isolatesFuture.whenComplete(() {
                  setState(() => allowChangeDocIndex = true);
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
                        value: currentIndex,
                        isExpanded: true,
                        items: List.generate(
                          _docThumbnails.length,
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
                                  setState(() => currentIndex = newValue);
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
                onPressed: () {
                  // Save changes and close
                  setState(() {
                    _docNames[docIndex] = nameController.text.trim();
                  });
                  g.metadataHelper.writeDocName(docIndex, _docNames[docIndex]);
                  Navigator.pop(context, currentIndex);
                },
                child: Text(tr("popup.ok")),
              ),
            ],
          );
        },
      );

      // Handle the result after the popup closes
      if (selectedIndex != null && selectedIndex != docIndex) {
        await g.filesHelper.changeDocumentIndex(docIndex, selectedIndex);
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
      if (imperialCountries.contains(country)) {
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
  // Documents
  @override
  Widget build(BuildContext context) {
    g.translateAspectRatios(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(tr("documents.title")),
        actions: [
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
                  _changeDefaultThumbnailVersionPopup(context);
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
      body: _docThumbnails.isNotEmpty && _thumbnailRatios.isNotEmpty
          // Documents Cards
          ? CustomScrollbar(
              controller: _scrollController,
              pageAspectRatios: _thumbnailRatios
                  .whereIndexed(
                    (index, element) => !_deletedDocs.contains(index),
                  )
                  .toList(),
              scrollRangeStart: 0.1,
              scrollRangeEnd: 0.675,
              noTumb: true,

              child: ListView.builder(
                controller: _scrollController,
                itemCount: _docsCount,
                itemBuilder: (BuildContext context, int docIndex) {
                  if (_deletedDocs.contains(docIndex)) return SizedBox();
                  final displayDocIndex =
                      1 +
                      docIndex -
                      _deletedDocs
                          .where((element) => element < docIndex)
                          .length;
                  String docName = _docNames[docIndex].isNotEmpty
                      ? _docNames[docIndex]
                      : tr(
                          "documents.docIndex",
                          namedArgs: {"docIndex": "$displayDocIndex"},
                        );
                  final String creationDate = _docDates[docIndex];
                  String displayCreationDate = creationDate.isNotEmpty
                      ? formatDateLocalized(creationDate, context)
                      : creationDate;
                  int pagesCount = _docPageCounts.isNotEmpty
                      ? _docPageCounts[docIndex]
                      : -1;
                  final bool isLoading =
                      _loadingDocs.length <= docIndex || _loadingDocs[docIndex];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2.0,
                      child: SizedBox(
                        height: 160.0 * math.sqrt2,
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
                                        padding: EdgeInsets.all(12),
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
                                                  maxLines: 5,
                                                ),
                                                SizedBox(height: 6),
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
                                        onPressed: () => _pagesPopup(
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
                                        onPressed: () => _pagesPopup(
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
                                        onPressed: () => _pagesPopup(
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
                                maxWidth: 184,
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
                                      if (_thumbnailRatios.length > docIndex &&
                                          _docThumbnails[docIndex].isNotEmpty)
                                        AnimatedSwitcher(
                                          duration: Duration(milliseconds: 200),
                                          child: SizedBox.expand(
                                            child: Image.file(
                                              File(_docThumbnails[docIndex]),
                                              fit: BoxFit.cover,
                                              key: ValueKey(
                                                _docThumbnails[docIndex],
                                              ),
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return Material(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .surfaceBright,
                                                      child: const Icon(
                                                        Icons.broken_image,
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
                  final indexPairsList = await g.filesHelper.pickPdfToDoc();
                  int pdfsCount = indexPairsList.length;
                  if (pdfsCount != 0 && context.mounted) {
                    final messenger = ScaffoldMessenger.of(context);
                    final snackBar = SnackBar(
                      content: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(tr("loading.importingPdf")),
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(days: 1),
                    );
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(snackBar);

                    // Hide snackbar when page is loaded
                    StreamSubscription<NotifierEvent>?
                    eventSubscriptionSnackbar;
                    hideSnackbarOnPageReload(NotifierEvent event) {
                      if (event == NotifierEvent.loadPagesThumbnails) {
                        messenger.hideCurrentSnackBar();
                        eventSubscriptionSnackbar?.cancel();
                        _openDocument(indexPairsList.first.$1!);
                      }
                    }

                    eventSubscriptionSnackbar = globalNotifier.stream.listen(
                      hideSnackbarOnPageReload,
                    );
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

class IconWithPlusBadge extends StatelessWidget {
  final IconData icon;

  const IconWithPlusBadge({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final double containerSize = 16.0;
    final double textScaleFactor = MediaQuery.of(context).textScaler.scale(1.0);
    final double fontSize = containerSize / textScaleFactor;

    return Stack(
      children: [
        Align(
          alignment:
              Alignment.center +
              Alignment(
                0.25 / textScaleFactor / textScaleFactor,
                0.25 / textScaleFactor / textScaleFactor,
              ),
          child: Icon(icon),
        ),
        Align(
          alignment:
              Alignment.topLeft +
              Alignment(
                -1 / textScaleFactor / textScaleFactor,
                -1 / textScaleFactor / textScaleFactor,
              ),
          child: SizedBox(
            width: containerSize + fontSize,
            height: containerSize + fontSize,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: containerSize,
                    height: containerSize,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    "+",
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class IconWithBadge extends StatelessWidget {
  final IconData icon;
  final IconData badgeIcon;
  final double mainIconSize;
  final Color iconColor;
  final Color bgColor;

  const IconWithBadge({
    super.key,
    required this.icon,
    required this.badgeIcon,
    required this.iconColor,
    required this.bgColor,
    required this.mainIconSize,
  });

  @override
  Widget build(BuildContext context) {
    final double badgeIconSize = mainIconSize / 1.25;
    final double constraintsSize = mainIconSize * 1.27;

    return SizedBox(
      width: constraintsSize,
      height: constraintsSize,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomRight + Alignment(0, 0),
            child: Icon(icon, size: mainIconSize, color: iconColor),
          ),
          Align(
            alignment: Alignment.topLeft + Alignment(0, 0),
            child: SizedBox(
              width: badgeIconSize + 1,
              height: badgeIconSize + 1,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: badgeIconSize + 1,
                      height: badgeIconSize + 1,
                      decoration: BoxDecoration(
                        color: bgColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      badgeIcon,
                      size: badgeIconSize,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String formatDateLocalized(String dateString, BuildContext context) {
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
    await saveAvailableAspectRatios();
  }
}

Future<void> saveAvailableAspectRatios() async {
  final prefs = await SharedPreferences.getInstance();
  final values = g.availableAspectRatios
      .map((e) => e.value.toString())
      .toList();
  await prefs.setStringList("availableAspectRatios", values);
}

class CustomExpandingButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String text;
  final Color? collapsedColor;

  const CustomExpandingButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.text,
    this.collapsedColor,
  });

  @override
  State<CustomExpandingButton> createState() => _CustomExpandingButtonState();
}

class _CustomExpandingButtonState extends State<CustomExpandingButton>
    with SingleTickerProviderStateMixin, RouteAware {
  static const animDuration = Duration(milliseconds: 350);

  bool _expanded = false;
  Timer? _collapseTimer;

  static const double _collapsedWidth = 40;
  static const double _buttonHeight = 40;

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(seconds: 2));
      if (mounted) {
        _expandButtonTemporarily();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 1500));
      if (mounted) {
        _expandButtonTemporarily();
      }
    });
  }

  void _expandButtonTemporarily() {
    setState(() {
      _expanded = true;
    });

    _collapseTimer = Timer(
      animDuration + const Duration(seconds: 4) + animDuration,
      () {
        if (mounted) {
          setState(() {
            _expanded = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = _expanded
        ? colorScheme.primaryContainer
        : colorScheme.primaryContainer.withAlpha(0);
    final textColor = _expanded
        ? colorScheme.onPrimaryContainer
        : widget.collapsedColor ?? colorScheme.onPrimaryContainer;
    final textWidth = _calculateTextWidth(widget.text);

    return Padding(
      padding: const EdgeInsets.all(4),
      child: AnimatedContainer(
        duration: animDuration,
        width: _expanded ? _collapsedWidth * 1.3 + textWidth : _collapsedWidth,
        height: _buttonHeight,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(32),
          boxShadow: _expanded ? [tinyBoxShadow(context)] : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(32),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: widget.onPressed,
            onLongPress: _expandButtonTemporarily,
            child: SizedBox.expand(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 8),
                    Icon(widget.icon, color: textColor),
                    if (_expanded)
                      Expanded(
                        child: AnimatedOpacity(
                          duration: animDuration,
                          opacity: _expanded ? 1.0 : 0.0,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              widget.text,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w500,
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
        ),
      ),
    );
  }

  double _calculateTextWidth(
    String text, {
    TextStyle style = const TextStyle(),
  }) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout();

    return textPainter.width * 1.2;
  }
}

final InAppPurchase iap = InAppPurchase.instance;
final List<ProductDetails> products = [];
Future<void> initStoreInfo() async {
  final bool available = await iap.isAvailable();
  if (!available) {
    dev.log("Warning, initStoreInfo: In-App-Purchases not available");
    return;
  }
  listenToPurchaseUpdates();

  const Set<String> productNames = {"pro_upgrade"};
  final ProductDetailsResponse response = await iap.queryProductDetails(
    productNames,
  );

  if (response.notFoundIDs.isNotEmpty) {
    dev.log(
      "Warning, initStoreInfo: Product IDs not forund: ${response.notFoundIDs}",
    );
  }

  if (!available || response.notFoundIDs.contains("pro_upgrade")) {
    await deactivateProAfterWeekOffline();
  }

  products.addAll(response.productDetails);
  iap.restorePurchases(); // activate listenToPurchaseUpdates() // does not work for license testing
}

Future<void> deactivateProAfterWeekOffline() async {
  final sStorage = FlutterSecureStorage();

  final bool isSaved = "true" == await sStorage.read(key: "proUnlocked");
  final String? savedDate = await sStorage.read(key: "proUnlockedDate");

  if (isSaved && savedDate != null) {
    final unlockTime = DateTime.tryParse(savedDate);
    final now = DateTime.now();

    if (unlockTime != null && now.difference(unlockTime).inDays < 7) {
      setPro(true); // still within grace period
    } else {
      setPro(false); // expired or unreadable
    }
  } else {
    setPro(false); // no record
  }
}

StreamSubscription<List<PurchaseDetails>>? subscription;
void listenToPurchaseUpdates() {
  subscription = iap.purchaseStream.listen(
    (purchases) async {
      if (!await feedbackHelper.isAppValid()) setPro(false);
      for (var purchase in purchases) {
        switch (purchase.productID) {
          case "pro_upgrade":
            switch (purchase.status) {
              case PurchaseStatus.purchased:
              case PurchaseStatus.restored:
                if (purchase.pendingCompletePurchase) {
                  await iap.completePurchase(purchase);
                }
                if (purchase.verificationData.source == "google_play") {
                  setPro(true);
                }
                break;
              case PurchaseStatus.error:
                if (purchase.error != null) {
                  if (purchase.error!.message ==
                          "BillingResponse.itemAlreadyOwned" &&
                      purchase.verificationData.source == "google_play") {
                    setPro(true);
                  } else {
                    setPro(false);
                  }
                }
              case PurchaseStatus.pending:
                break;
              case PurchaseStatus.canceled:
                setPro(false);
                break;
            }
            break;
          default:
            switch (purchase.status) {
              case PurchaseStatus.error:
                if (purchase.error != null) {
                  if (purchase.error!.message ==
                          "BillingResponse.itemAlreadyOwned" &&
                      purchase.verificationData.source == "google_play") {
                    setPro(true);
                  }
                }
                break;
              default:
                break;
            }
            break;
        }
      }
    },
    onDone: () => subscription?.cancel(),
    onError: (error) {
      dev.log("purchaseStream error: $error");
    },
  );
}

Future<bool> buyPro() async {
  ProductDetails proUpgrade;
  try {
    proUpgrade = products[0];
  } catch (e) {
    dev.log("Warning, buyPro: proUpgrade not available: $e");
    return false;
  }
  final PurchaseParam purchaseParam = PurchaseParam(productDetails: proUpgrade);
  if (!await iap.buyNonConsumable(purchaseParam: purchaseParam)) {
    dev.log("Warning, buyPro: Request not sent successfully.");
    return false;
  }
  return true;
}

Future<String?> getProPrice() async {
  ProductDetails proUpgrade;
  try {
    proUpgrade = products[0];
  } catch (e) {
    dev.log("Warning, getProPrice: proUpgrade not available: $e");
    return null;
  }
  return proUpgrade.price;
}

Future<bool> proPopup(BuildContext context) async {
  String? proPrice = await getProPrice();
  if (!context.mounted) return false;
  bool? selectBuyPro = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              g.proUnlocked ? Icons.verified : Icons.lock,
              color: Theme.of(context).colorScheme.onSurface,
              size: 30,
            ),
            SizedBox(width: 12),
            Flexible(
              child: Text(
                g.proUnlocked
                    ? tr("documents.menu.pro1")
                    : tr("documents.menu.pro2"),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  " •  ",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                Expanded(child: Text(tr("popup.pro.bp1"))),
              ],
            ),
            SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  " •  ",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                Expanded(child: Text(tr("popup.pro.bp2"))),
              ],
            ),
            SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  " •  ",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                Expanded(child: Text(tr("popup.pro.bp3"))),
              ],
            ),

            g.proUnlocked
                ? Text(tr("popup.pro.thanksText"))
                : Center(
                    child: SizedBox(
                      width: 200,
                      child: Text(
                        textAlign: TextAlign.center,
                        "\n${proPrice ?? ""}\n\n${tr("popup.pro.priceText")}",
                      ),
                    ),
                  ),
          ],
        ),
        actions: [
          g.proUnlocked
              ? ElevatedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    tr("popup.ok"),
                    style: TextStyle(color: Colors.green),
                  ),
                )
              : TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr("popup.cancel")),
                ),
          g.proUnlocked
              ? SizedBox()
              : ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    tr("popup.purchase"),
                    style: TextStyle(color: Colors.green),
                  ),
                ),
        ],
      );
    },
  );
  if (selectBuyPro == true) {
    if (await buyPro()) {
      await Future.delayed(Duration(milliseconds: 400));
      if (context.mounted && g.proUnlocked) {
        _changeDefaultThumbnailVersionPopup(context);
      }
      return true;
    }
  }
  return false;
}

setPro(final bool proUnlockedIn) async {
  if (proUnlockedIn && !await feedbackHelper.isAppValid()) {
    setPro(false);
    return;
  }

  bool showMessages = true;
  if (g.proUnlocked == proUnlockedIn) showMessages = false;
  g.proUnlocked = proUnlockedIn;

  final sStorage = FlutterSecureStorage();
  sStorage.write(
    key: "proUnlocked",
    value: proUnlockedIn == true ? "true" : "false",
  );

  if (proUnlockedIn) {
    final now = DateTime.now().toIso8601String();
    sStorage.write(key: "proUnlockedDate", value: now);
  }

  if (showMessages) {
    Fluttertoast.showToast(
      msg: proUnlockedIn ? tr("toast.proUnlocked") : tr("toast.proDisabled"),
    );
  }
  globalNotifier.triggerEvent(NotifierEvent.setState);
  await loadDefaultThumbnailVersion();
}

Future<bool> _unlockDocumentWithAd(BuildContext context) async {
  final bool adWatched = await adsHelper.showRewardAd();
  if (adWatched) {
    Fluttertoast.showToast(msg: tr("toast.tmp_combiPfd"));
  }
  return adWatched;
}

Future<bool> _unlockPageWithAd(BuildContext context) async {
  final bool adWatched = await adsHelper.showRewardAd();
  if (adWatched) {
    Fluttertoast.showToast(msg: tr("toast.tmp_proFilter"));
  }
  return adWatched;
}

class ImagesScrollPreview extends StatelessWidget {
  const ImagesScrollPreview({
    super.key,
    required this.imagePaths,
    required this.loadingImages,
    required this.imageRatios,
  });

  final List<String> imagePaths;
  final List<bool> loadingImages;
  final List<double> imageRatios;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        int index = -1;
        return Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: imagePaths.map((imagePath) {
                index++;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    8.0,
                    4.0,
                    8.0,
                    12.0,
                  ), // Spacing between images
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [smallBoxShadow(context)],
                    ),
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: 160.0 * math.sqrt2,
                        maxWidth: 160.0,
                      ),
                      child: AspectRatio(
                        aspectRatio: imageRatios.length > index
                            ? 1 / imageRatios[index]
                            : math.sqrt1_2,
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
                            if (imagePath.isNotEmpty)
                              AnimatedSwitcher(
                                duration: Duration(milliseconds: 200),
                                child: SizedBox.expand(
                                  child: Image.file(
                                    File(imagePath),
                                    fit: BoxFit.cover,
                                    key: ValueKey(imagePath),
                                    errorBuilder: (context, error, stackTrace) {
                                      return Material(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceBright,
                                        child: const Icon(Icons.broken_image),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            // Loading Indicator
                            if (loadingImages[index])
                              Positioned.fill(
                                child: Material(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh
                                      .withAlpha(150),
                                ),
                              ),
                            if (loadingImages.length <= index ||
                                imagePath.isEmpty ||
                                loadingImages[index])
                              IndicatorProcessingImage(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class Pages extends StatefulWidget {
  const Pages({super.key, required this.docIndex, this.initialPageIndex});

  final int docIndex;
  final int? initialPageIndex;

  @override
  State<Pages> createState() => _PagesState();
}

class _PagesState extends State<Pages> with RouteAware {
  final ImagePicker _picker = ImagePicker();
  List<String> _pageThumbnails = [];
  List<double> _thumbnailRatios = [];
  int _pagesCount = 0;

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
    _loadPagesThumbnails(onInit: true, supressWarnings: true);
    _initPushToPreview();
    _loadSelectAllButtonUsed();
    _loadGridView();
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  List<int> _deletedPages = [];
  late final StreamSubscription<NotifierEvent> _eventSubscription;
  Future<void> _handleGlobalEvent(NotifierEvent event) async {
    if (!mounted) return;
    switch (event) {
      case NotifierEvent.loadPagesThumbnails:
        _loadPagesThumbnails();
        break;
      case NotifierEvent.imagesDeleted:
        _deletedPages = await g.filesHelper.getMarkedDeletedPages(
          widget.docIndex,
        );
        setState(() {});
        break;
      case NotifierEvent.setState:
        setState(() {});
        break;
      default:
    }
  }

  void _initPushToPreview() {
    if (widget.initialPageIndex != null) {
      Future.microtask(() {
        _openPagePreview(widget.initialPageIndex!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  // didPopNext() triggers before PopScope is finished, use signals instead if possible
  //@override
  //Future<void> didPopNext() async {}

  Future<void> _loadPagesThumbnails({
    bool onInit = false,
    bool supressWarnings = false,
  }) async {
    var thumbs = await g.filesHelper.getPagesThumbnails(widget.docIndex);
    _pagesCount = thumbs.$2;
    List<String> thumbnailPaths = thumbs.$1;

    bool newThumbnails = false;
    if (_pagesCount != _pageThumbnails.length) {
      newThumbnails = true;
    }
    List<double> newThumbnailRatios = List.generate(
      _pagesCount,
      (_) => 1.0 / math.sqrt2,
    ); // first collect here, because random setState()s will otherwise show wrong ratios, while still awaiting all ratios
    for (var pageIndex = 0; pageIndex < _pagesCount; pageIndex++) {
      if (!newThumbnails &&
          (_pageThumbnails.length <= pageIndex ||
              thumbnailPaths[pageIndex] != _pageThumbnails[pageIndex])) {
        newThumbnails = true;
      }
      bool supressWarnings_ = supressWarnings;
      if (thumbnailPaths[pageIndex].isEmpty) supressWarnings_ = true;
      double ratioValue =
          await MetadataHelper.readPageRatioValue(
            widget.docIndex,
            pageIndex,
            supressWarnings: supressWarnings_,
          ) ??
          math.sqrt2;
      newThumbnailRatios[pageIndex] = 1.0 / ratioValue;
    }
    _thumbnailRatios = newThumbnailRatios;
    _deletedPages = await g.filesHelper.getMarkedDeletedPages(widget.docIndex);
    _loadingPages = await _loadLoadingPages(widget.docIndex, thumbnailPaths);

    if (thumbnailPaths.isEmpty) {
      if (!onInit && mounted && context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      return;
    } else if (newThumbnails) {
      if (mounted) {
        setState(() {
          _pageThumbnails = thumbnailPaths;
        });
      }
    }
  }

  List<bool> _loadingPages = [];
  Future<List<bool>> _loadLoadingPages(
    int docIndex,
    List<String> thumbnailPaths,
  ) async {
    List<bool> thumbnailsLoading = [];
    for (int pageIndex = 0; pageIndex < thumbnailPaths.length; pageIndex++) {
      bool thumbnailLoading = false;
      if (thumbnailPaths[pageIndex].isEmpty) {
        thumbnailLoading = true;
      } else {
        final oldNames = await MetadataHelper.readOldPageFileNames(
          docIndex,
          pageIndex,
        );
        if (oldNames != null) {
          for (var oldName in oldNames) {
            if (oldName.isNotEmpty &&
                thumbnailPaths[pageIndex].contains(oldName)) {
              thumbnailLoading = true;
              break;
            }
          }
        } else {
          thumbnailLoading = true;
        }
      }
      thumbnailsLoading.add(thumbnailLoading);
    }
    return thumbnailsLoading;
  }

  Future<void> _openPagePreview(int pageIndex) async {
    Navigator.pushNamed(
      context,
      "/preview",
      arguments: {"docIndex": widget.docIndex, "pageIndex": pageIndex},
    );
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

    int firstPageIndex = await _processNewPages(
      photoPaths,
      photosAlreadyInPages: false,
    );

    // Only open PagePreview for first page
    messenger?.hideCurrentSnackBar();
    _openPagePreview(firstPageIndex);
  }

  Future<int> _processNewPages(
    List<String> photoPaths, {
    required bool photosAlreadyInPages,
  }) async {
    int firstPageIndex = await g.filesHelper.reserveNewPagesInDocment(
      widget.docIndex,
      photoPaths.length,
    );
    Future.microtask(() async {
      await g.metadataHelper.writeDocUnlocked(widget.docIndex, false);
      await imageProcessingManager.processPages(
        widget.docIndex,
        firstPageIndex,
        photoPaths,
        photosAlreadyInPages,
      );
    });

    return firstPageIndex;
  }

  Future<List<String>> _openCamera() async {
    g.filesHelper.pickingImage = true;
    final result = await Navigator.pushNamed(context, "/camera");
    List<String> photoPaths = [];
    if (result is List<XFile>) {
      for (var xfile in result) {
        photoPaths.add(xfile.path);
      }
    }
    g.filesHelper.pickingImage = false;
    return photoPaths;
  }

  bool _selectMode = false;
  List<int> _selectedPages = [];

  _selectPage(int index) {
    if (_selectedPages.contains(index)) {
      _selectedPages.remove(index);
    } else {
      _selectedPages.add(index);
    }
    if (_selectedPages.isEmpty) {
      _selectMode = false;
    } else {
      _selectedPages.sort();
      _selectMode = true;
    }
    Future.microtask(() {
      setState(() {});
    });
  }

  bool selectAllButtonUsed = true;
  _loadSelectAllButtonUsed() async {
    final prefs = await SharedPreferences.getInstance();
    selectAllButtonUsed = prefs.getBool("selectAllButtonUsed") ?? false;
    // reset if long ago
    if (selectAllButtonUsed) {
      final String? dateString = prefs.getString("selectAllButtonUsedDate");
      if (dateString != null) {
        final now = DateTime.now();
        final date = DateTime.tryParse(dateString);
        if (date != null && now.difference(date).inDays > 45) {
          dev.log("_getSelectAllButtonUsed: reset to CustomExpandingButton");
          _setSelectAllButtonUsed(false);
        }
      }
    }
  }

  _setSelectAllButtonUsed(bool set) async {
    if (set == selectAllButtonUsed) return;
    selectAllButtonUsed = set;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("selectAllButtonUsed", set);
    if (set) {
      String now = DateTime.now().toIso8601String();
      prefs.setString("selectAllButtonUsedDate", now);
    }
  }

  bool? _gridView;
  _loadGridView() async {
    if (_gridView != null) return;
    final prefs = await SharedPreferences.getInstance();
    _gridView = prefs.getBool("gridView") ?? false;
    setState(() {});
  }

  _toggleGridView() async {
    if (_gridView == null) return;
    _gridView = !_gridView!;
    _scrollController.reset();
    setState(() {});
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("gridView", _gridView!);
  }

  _selectAll() async {
    _setSelectAllButtonUsed(true);

    final lengthBefore = _selectedPages.length;

    _selectedPages = List.generate(
      _pageThumbnails.length,
      (int index) => index,
      growable: true,
    );
    _selectedPages.removeWhere((element) => _deletedPages.contains(element));

    if (lengthBefore != _selectedPages.length && _selectedPages.isNotEmpty) {
      HapticFeedback.lightImpact();
      _selectMode = true;
      Future.microtask(() {
        if (mounted) setState(() {});
      });
    }
  }

  _cancelSelectMode() {
    HapticFeedback.lightImpact();
    _selectedPages = [];
    _selectMode = false;
    Future.microtask(() {
      setState(() {});
    });
  }

  final _scrollController = CustomScrollController();
  // Pages
  @override
  Widget build(BuildContext context) {
    //final bool isTopOfNavigationStack =
    //    ModalRoute.of(context)?.isCurrent ?? false;
    final displayPagesCount = _pagesCount - _deletedPages.length;
    return PopScope(
      canPop: !_selectMode,
      onPopInvokedWithResult: (didPop, _) async {
        if (_selectMode) {
          _cancelSelectMode();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: !_selectMode
            ? AppBar(
                // Regular
                title: Text(
                  tr(
                    "pages.title",
                    namedArgs: {"docIndex": "${widget.docIndex + 1}"},
                  ),
                ),
                actions: [
                  // Grid View Toggle
                  if (_gridView != null)
                    IconButton(
                      onPressed: () => _toggleGridView(),
                      icon: _gridView!
                          ? Icon(Icons.view_agenda_sharp)
                          : Icon(Icons.dashboard_sharp),
                      tooltip: (_gridView!
                          ? tr("pages.views.listView")
                          : tr("pages.views.gridView")),
                    ),
                  // Select All Button
                  selectAllButtonUsed
                      ? IconButton(
                          onPressed: () => _selectAll(),
                          icon: Icon(Icons.select_all),
                          tooltip: tr("pages.select.selectAll"),
                        )
                      : CustomExpandingButton(
                          onPressed: () => _selectAll(),
                          icon: Icons.select_all,
                          text: tr("pages.select.selectAll"),
                          collapsedColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                ],
              )
            : AppBar(
                // Selecting
                title: Text(
                  tr(
                    "pages.select.selected",
                    namedArgs: {"selectedCount": "${_selectedPages.length}"},
                  ),
                ),
                leading: IconButton(
                  onPressed: () => _cancelSelectMode(),
                  icon: Icon(Icons.close),
                  tooltip: tr("pages.select.cancelSelection"),
                ),
                actions: [
                  IconButton(
                    onPressed: () => _selectAll(),
                    icon: Icon(Icons.select_all),
                    tooltip: tr("pages.select.selectAll"),
                  ),
                ],
              ),
        body:
            _pageThumbnails
                .isNotEmpty // && isTopOfNavigationStack
            // Pages
            ? CustomScrollbar(
                controller: _scrollController,
                pageAspectRatios: _thumbnailRatios
                    .whereIndexed(
                      (index, element) => !_deletedPages.contains(index),
                    )
                    .toList(),
                scrollRangeStart: 0.1,
                scrollRangeEnd: 0.675,

                child: _gridView == null
                    ? SizedBox()
                    : !_gridView!
                    ? ListView.builder(
                        padding: EdgeInsets.fromLTRB(15, 6, 15, 24),
                        controller: _scrollController,
                        cacheExtent: 1000,
                        itemCount: _pagesCount,
                        itemBuilder: (BuildContext context, int pageIndex) {
                          if (_deletedPages.contains(pageIndex)) {
                            return SizedBox();
                          }
                          final displayPageIndex =
                              1 +
                              pageIndex -
                              _deletedPages
                                  .where((element) => element < pageIndex)
                                  .length;
                          final String thumbnailPath =
                              _pageThumbnails[pageIndex];
                          final double thumbnailRatio =
                              _thumbnailRatios[pageIndex];
                          if (thumbnailRatio == 0.0) {
                            throw StateError("thumbnailRatio == 0.0");
                          }
                          final File pageThumbnail = File(thumbnailPath);
                          final bool isLoading =
                              _loadingPages.length <= pageIndex ||
                              _loadingPages[pageIndex];
                          return Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: AspectRatio(
                              aspectRatio: thumbnailRatio,
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
                                    if (thumbnailPath.isNotEmpty)
                                      AnimatedSwitcher(
                                        duration: Duration(milliseconds: 200),
                                        child: SizedBox.expand(
                                          child: Image.file(
                                            pageThumbnail,
                                            fit: BoxFit.cover,
                                            key: ValueKey(thumbnailPath),
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Material(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.surfaceBright,
                                                    child: const Icon(
                                                      Icons.broken_image,
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
                                    if (thumbnailPath.isEmpty || isLoading)
                                      IndicatorProcessingImage(),
                                    // InkWell
                                    Positioned.fill(
                                      child: Material(
                                        color:
                                            (_selectMode &&
                                                _selectedPages.contains(
                                                  pageIndex,
                                                ))
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withAlpha(150)
                                            : Colors.transparent,
                                        child: InkWell(
                                          onTap: !_selectMode
                                              ? () =>
                                                    _openPagePreview(pageIndex)
                                              : () {
                                                  HapticFeedback.lightImpact();
                                                  _selectPage(pageIndex);
                                                },
                                          onLongPress: () {
                                            _selectPage(pageIndex);
                                          },
                                          splashColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withAlpha(150),
                                          highlightColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withAlpha(150),
                                        ),
                                      ),
                                    ),
                                    // Page Index Indicator
                                    Positioned(
                                      top: 18,
                                      left: 12,
                                      child: GestureDetector(
                                        // Move Page Index Dialog
                                        onTap: _selectMode
                                            ? () => _selectPage(pageIndex)
                                            : () => _openPageEditDialog(
                                                context,
                                                pageIndex,
                                                displayPageIndex,
                                              ),
                                        onLongPress: () =>
                                            _selectPage(pageIndex),
                                        child: Container(
                                          padding: EdgeInsets.fromLTRB(
                                            12,
                                            6,
                                            (_selectMode &&
                                                    _selectedPages.contains(
                                                      pageIndex,
                                                    ))
                                                ? 6
                                                : 12,
                                            6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surfaceBright,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            boxShadow: [
                                              smallBoxShadow(context),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                "$displayPageIndex/$displayPagesCount",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              SizedBox(
                                                width:
                                                    (_selectMode &&
                                                        _selectedPages.contains(
                                                          pageIndex,
                                                        ))
                                                    ? 8
                                                    : 0,
                                              ),
                                              (_selectMode &&
                                                      _selectedPages.contains(
                                                        pageIndex,
                                                      ))
                                                  ? Icon(Icons.check, size: 20)
                                                  : SizedBox(),
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
                      )
                    // Grid View
                    : MasonryGridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        padding: EdgeInsets.fromLTRB(15, 6, 15, 36),
                        controller: _scrollController,
                        cacheExtent: 1000,
                        itemCount: _pagesCount,
                        itemBuilder: (BuildContext context, int pageIndex) {
                          if (_deletedPages.contains(pageIndex)) {
                            return SizedBox();
                          }
                          final displayPageIndex =
                              1 +
                              pageIndex -
                              _deletedPages
                                  .where((element) => element < pageIndex)
                                  .length;
                          String thumbnailPath = _pageThumbnails[pageIndex];
                          double thumbnailRatio = _thumbnailRatios[pageIndex];
                          if (thumbnailRatio == 0.0) {
                            throw StateError("thumbnailRatio == 0.0");
                          }
                          File pageThumbnail = File(thumbnailPath);
                          final bool isLoading =
                              _loadingPages.length <= pageIndex ||
                              _loadingPages[pageIndex];
                          return AspectRatio(
                            aspectRatio: thumbnailRatio,
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
                                  if (thumbnailPath.isNotEmpty)
                                    AnimatedSwitcher(
                                      duration: Duration(milliseconds: 200),
                                      child: SizedBox.expand(
                                        child: Image.file(
                                          pageThumbnail,
                                          fit: BoxFit.cover,
                                          key: ValueKey(thumbnailPath),
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Material(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.surfaceBright,
                                                  child: const Icon(
                                                    Icons.broken_image,
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
                                  if (thumbnailPath.isEmpty || isLoading)
                                    IndicatorProcessingImage(),
                                  // InkWell
                                  Positioned.fill(
                                    child: Material(
                                      color:
                                          (_selectMode &&
                                              _selectedPages.contains(
                                                pageIndex,
                                              ))
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withAlpha(150)
                                          : Colors.transparent,
                                      child: InkWell(
                                        onTap: !_selectMode
                                            ? () => _openPagePreview(pageIndex)
                                            : () {
                                                HapticFeedback.lightImpact();
                                                _selectPage(pageIndex);
                                              },
                                        onLongPress: () {
                                          _selectPage(pageIndex);
                                        },
                                        splashColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withAlpha(150),
                                        highlightColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withAlpha(150),
                                      ),
                                    ),
                                  ),
                                  // Page Index Indicator
                                  Positioned(
                                    top: 9,
                                    left: 6,
                                    child: GestureDetector(
                                      // Move Page Index Dialog
                                      onTap: _selectMode
                                          ? () => _selectPage(pageIndex)
                                          : () => _openPageEditDialog(
                                              context,
                                              pageIndex,
                                              displayPageIndex,
                                            ),
                                      onLongPress: () => _selectPage(pageIndex),
                                      child: Container(
                                        padding: EdgeInsets.fromLTRB(
                                          12,
                                          6,
                                          (_selectMode &&
                                                  _selectedPages.contains(
                                                    pageIndex,
                                                  ))
                                              ? 6
                                              : 12,
                                          6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceBright,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [smallBoxShadow(context)],
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              "$displayPageIndex/$displayPagesCount",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(
                                              width:
                                                  (_selectMode &&
                                                      _selectedPages.contains(
                                                        pageIndex,
                                                      ))
                                                  ? 8
                                                  : 0,
                                            ),
                                            (_selectMode &&
                                                    _selectedPages.contains(
                                                      pageIndex,
                                                    ))
                                                ? Icon(Icons.check, size: 20)
                                                : SizedBox(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              )
            : const SizedBox(),
        // Floating Action Buttons
        floatingActionButton: Padding(
          padding: const EdgeInsets.all(20.0),
          child: !_selectMode
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    // Add Images
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: FloatingActionButton(
                        heroTag: "pickImagesPage",
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () {
                          _openImagePicker(ImageSource.gallery);
                        },
                        tooltip: tr("fabs.images"),
                        child: IconWithPlusBadge(icon: Icons.photo_library),
                      ),
                    ),
                    SizedBox(height: 18.0),
                    // Add PDF
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: FloatingActionButton(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        heroTag: "pickPdfPage",
                        onPressed: () async {
                          final indexPairsList = await g.filesHelper
                              .pickPdfToDoc(addToDocWithIndex: widget.docIndex);
                          int pdfsCount = indexPairsList.length;
                          if (pdfsCount != 0 && context.mounted) {
                            final messenger = ScaffoldMessenger.of(context);
                            final snackBar = SnackBar(
                              content: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(tr("loading.importingPdf")),
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                    ),
                                  ),
                                ],
                              ),
                              duration: const Duration(days: 1),
                            );
                            messenger.showSnackBar(snackBar);

                            // Hide snackbar when page is loaded
                            StreamSubscription<NotifierEvent>?
                            eventSubscriptionSnackbar;
                            hideSnackbarOnPageReload(NotifierEvent event) {
                              if (event == NotifierEvent.loadPagesThumbnails) {
                                messenger.hideCurrentSnackBar();
                                eventSubscriptionSnackbar?.cancel();
                              }
                            }

                            eventSubscriptionSnackbar = globalNotifier.stream
                                .listen(hideSnackbarOnPageReload);
                          }
                        },
                        tooltip: tr("fabs.pdfs"),
                        child: IconWithPlusBadge(icon: Icons.picture_as_pdf),
                      ),
                    ),
                    SizedBox(height: 18.0),
                    // Take and add Photos
                    if (_picker.supportsImageSource(ImageSource.camera))
                      FloatingActionButton(
                        heroTag: "takePhotoPage",
                        onPressed: () {
                          _openImagePicker(ImageSource.camera);
                        },
                        tooltip: tr("fabs.camera"),
                        child: const Icon(Icons.camera_alt),
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
                        heroTag: "selectionChangeThumbnail",
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () async {
                          //if (
                          await _changeThumbnailVersionsPopup(
                            context,
                            _selectedPages,
                            widget.docIndex,
                          );
                          //) {
                          //  _cancelSelectMode();
                          //}
                        },
                        tooltip: tr("fabs.thumbnail"),
                        child: IconWithBadge(
                          icon: Icons.image,
                          badgeIcon: Icons.change_circle,
                          mainIconSize: 24,
                          iconColor: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          bgColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                        ),
                      ),
                    ),
                    SizedBox(height: 18.0),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: FloatingActionButton(
                        heroTag: "selectionDeletePage",
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () async {
                          bool deletionConfirmed = await _pagesPopup(
                            context,
                            _selectedPages,
                            PopUpType.delete,
                            widget.docIndex,
                          );
                          if (deletionConfirmed) {
                            _cancelSelectMode();
                          }
                        },
                        tooltip: tr("fabs.delete"),
                        child: const Icon(Icons.delete),
                      ),
                    ),
                    SizedBox(height: 18.0),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: FloatingActionButton(
                        heroTag: "selectionSavePage",
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () async {
                          if (await _pagesPopup(
                                context,
                                _selectedPages,
                                PopUpType.save,
                                widget.docIndex,
                              ) &&
                              mounted) {
                            _cancelSelectMode();
                          }
                        },
                        tooltip: tr("fabs.save"),
                        child: const Icon(Icons.save),
                      ),
                    ),
                    SizedBox(height: 18.0),
                    if (_picker.supportsImageSource(ImageSource.camera))
                      FloatingActionButton(
                        heroTag: "selectionSharePage",
                        onPressed: () async {
                          _pagesPopup(
                            context,
                            _selectedPages,
                            PopUpType.share,
                            widget.docIndex,
                          );
                        },
                        tooltip: tr("fabs.share"),
                        child: const Icon(Icons.share),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  void _openPageEditDialog(
    BuildContext context,
    int pageIndex,
    displayPageIndex,
  ) async {
    bool allowChangePageIndex = false;
    Future<void> future = imageProcessingManager.awaitAllIsolatesOfDocument(
      widget.docIndex,
    );
    int? selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        int currentIndex = pageIndex;
        return StatefulBuilder(
          builder: (context, setState) {
            future.whenComplete(() {
              if (!allowChangePageIndex) {
                setState(() => allowChangePageIndex = true);
              }
            });
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
                        'pages.pageIndex',
                        namedArgs: {'pageIndex': '$displayPageIndex'},
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Move Page to new Index - Dropdown
                  TextButton(
                    onPressed: !allowChangePageIndex
                        ? () => Fluttertoast.showToast(
                            msg: tr("loading.waitingOtherPages"),
                          )
                        : null,
                    child: DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: tr("pages.popup.move"),
                      ),
                      value: currentIndex,
                      isExpanded: true,
                      items: List.generate(
                        _pageThumbnails.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(
                            overflow: TextOverflow.ellipsis,
                            tr(
                              "pages.pageIndex",
                              namedArgs: {"pageIndex": "${i + 1}"},
                            ),
                          ),
                        ),
                      ),
                      onChanged: allowChangePageIndex
                          ? (int? newValue) {
                              if (newValue != null) {
                                setState(() => currentIndex = newValue);
                              }
                            }
                          : null,
                    ),
                  ),

                  SizedBox(height: 24),
                  // Reverse Order - Button
                  ElevatedButton.icon(
                    onPressed: allowChangePageIndex
                        ? () async {
                            await g.filesHelper.reversePagesOrder(
                              widget.docIndex,
                            );
                            if (context.mounted) Navigator.pop(context);
                            _loadPagesThumbnails();
                          }
                        : () => Fluttertoast.showToast(
                            msg: tr("loading.waitingPages"),
                          ),
                    label: Text(
                      tr("pages.popup.reverseOrder"),
                      style: TextStyle(
                        color: allowChangePageIndex
                            ? null
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                    icon: Icon(
                      Icons.swap_vert,
                      color: allowChangePageIndex
                          ? null
                          : Theme.of(context).disabledColor,
                    ),
                    style: ButtonStyle(
                      backgroundColor: allowChangePageIndex
                          ? null
                          : WidgetStateProperty.all(
                              Theme.of(context).disabledColor,
                            ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(tr("popup.cancel")),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, currentIndex);
                  },
                  child: Text(tr("popup.ok")),
                ),
              ],
            );
          },
        );
      },
    );

    // Handle Results after Dialog closes
    if (selectedIndex != null && selectedIndex != pageIndex) {
      await g.filesHelper.changePageIndex(
        widget.docIndex,
        pageIndex,
        selectedIndex,
      );
      _loadPagesThumbnails();
    }
  }

  Future<bool> _changeThumbnailVersionsPopup(
    BuildContext context,
    List<int> pageIndexes,
    int docIndex,
  ) async {
    int? selectedIndex;
    bool allowed = true;
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconWithBadge(
                    icon: Icons.image,
                    badgeIcon: Icons.change_circle,
                    mainIconSize: 30,
                    iconColor: Theme.of(context).colorScheme.onSurface,
                    bgColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                  SizedBox(width: 12),
                  Flexible(child: Text(tr("popup.changeThumbnails.title"))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(
                  versionNames.length - 1,
                  (index) => RadioListTile<int>(
                    title: Row(
                      children: [
                        Text(versionNames[index + 1]),
                        !g.proUnlocked && g.proFilterIndexes.contains(index + 1)
                            ? Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(Icons.lock),
                              )
                            : SizedBox(),
                      ],
                    ),
                    value: index + 1,
                    groupValue: selectedIndex,
                    onChanged: (int? value) {
                      if (value != null) {
                        if (!g.proUnlocked &&
                            g.proFilterIndexes.contains(index + 1)) {
                          allowed = false;
                        } else {
                          allowed = true;
                        }
                        setStateDialog(() {
                          selectedIndex = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false), // Cancel
                  child: Text(tr("popup.cancel")),
                ),
                allowed
                    ? ElevatedButton(
                        onPressed: selectedIndex != null
                            ? () {
                                Navigator.pop(context, true);
                              }
                            : null,
                        child: Text(tr("popup.ok")),
                      )
                    : ElevatedButton.icon(
                        icon: Icon(Icons.lock),
                        onPressed: () async {
                          await proPopup(context);
                          setStateDialog(() {});
                        },
                        label: Text(tr("popup.unlock")),
                      ),
              ],
            );
          },
        );
      },
    );

    List<Future> changeThumbnailFutures = [];
    if (confirmed == true && allowed && selectedIndex != null) {
      for (var pageIndex in pageIndexes) {
        final bool pageUnlocked = await g.metadataHelper.readPageUnlocked(
          docIndex,
          pageIndex,
          supressWarnings: true,
        );
        changeThumbnailFutures.add(
          !_loadingPages[pageIndex]
              // set new Thumbnail
              ? imageProcessingManager.setNewThumbnail(
                  docIndex,
                  pageIndex,
                  selectedIndex!,
                  tmpPro: pageUnlocked,
                )
              // still processing -> just set thumbnailIndex
              : MetadataHelper.writePageThumbnailIndex(
                  docIndex,
                  pageIndex,
                  selectedIndex!,
                  tmpPro: pageUnlocked,
                  supressWarnings: true,
                ),
        );
      }
      if (context.mounted) {
        _changingThumbnailsSnackbar(context, changeThumbnailFutures);
      }
      return true;
    }
    return false;
  }
}

class CustomScrollController extends ScrollController {
  VoidCallback? resetCallback;

  void reset() {
    resetCallback?.call();
  }
}

class CustomScrollbar extends StatefulWidget {
  final Widget child;
  final CustomScrollController controller;
  final List<double> pageAspectRatios;
  final Color? backgroundColor;
  final Color? textColor;
  final Duration thumbVisibilityDuration;
  final Duration thumbVisibilityFadeDuration;
  final double scrollRangeStart; // 0.0 to 1.0
  final double scrollRangeEnd; // 0.0 to 1.0
  final bool noTumb;

  const CustomScrollbar({
    super.key,
    required this.child,
    required this.controller,
    required this.pageAspectRatios,
    this.backgroundColor,
    this.textColor,
    this.thumbVisibilityDuration = const Duration(milliseconds: 1000),
    this.thumbVisibilityFadeDuration = const Duration(milliseconds: 200),
    this.scrollRangeStart = 0.0,
    this.scrollRangeEnd = 1.0,
    this.noTumb = false,
  });

  @override
  State<CustomScrollbar> createState() => _CustomScrollbarState();
}

class _CustomScrollbarState extends State<CustomScrollbar>
    with TickerProviderStateMixin {
  double _thumbTop = 0.0;
  bool _isThumbVisible = false;
  bool _isDragging = false;
  Timer? _hideTimer;
  int _lastPage = 0;
  static const double _thumbSize = 56;

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
    widget.controller.addListener(_scrollListener);
    _fadeController = AnimationController(
      vsync: this,
      duration: widget.thumbVisibilityFadeDuration,
    );
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(_fadeController);
    _railSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _railSlideAnimation =
        Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(1.5, 0), // slide off to the right
        ).animate(
          CurvedAnimation(
            parent: _railSlideController,
            curve: Curves.easeInOut,
          ),
        );
    _setRatios();
    widget.controller.resetCallback = () {
      if (mounted) {
        widget.controller.jumpTo(0);
      }
    };
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollListener);
    _hideTimer?.cancel();
    _fadeController.dispose();
    _railSlideController.dispose();
    super.dispose();
  }

  double _maxScroll = 0.0;
  _setMaxScroll({bool jump = false}) async {
    if (!widget.controller.hasClients ||
        !widget.controller.position.hasContentDimensions) {
      return;
    }
    double newMaxScroll = widget.controller.position.maxScrollExtent;
    double curretnPos = widget.controller.offset;

    if (newMaxScroll != 0.0) {
      if (jump) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          _maxScroll = newMaxScroll;
        });
      } else if (_maxScroll == 0) {
        // Instantly set initially
        _maxScroll = newMaxScroll;
      } else if (curretnPos >= newMaxScroll) {
        // Instantly scroll to end
        _maxScroll = newMaxScroll;
      } else if (newMaxScroll != _maxScroll) {
        double diffRatio = newMaxScroll / _maxScroll;
        diffRatio = diffRatio < 1 ? 1 / diffRatio : diffRatio;
        if (diffRatio > 2.0) {
          // Instantly set if very different
          _maxScroll = newMaxScroll;
        } else {
          // Slowly update _maxScroll
          double diff = newMaxScroll - _maxScroll;
          _maxScroll += diff.isNegative ? -1.0 : 1.0;
        }
      }
    }
  }

  List<double> _ratios = [];
  _setRatios() {
    final List<double> priorRatios = List<double>.from(_ratios);
    if (widget.pageAspectRatios.isEmpty) return;
    _ratios = List<double>.generate(
      widget.pageAspectRatios.length,
      (index) => 1.0 / widget.pageAspectRatios[index],
    );
    _ratios[0] /= 2;
    _ratios[_ratios.length - 1] /= 2;
    setState(() {});
    if (_ratios.sum != priorRatios.sum) {
      _setMaxScroll(jump: true);
    }
  }

  void _scrollListener() {
    if (_isDragging) {
      return;
    }

    _setMaxScroll();

    _showThumbTemporarily();
    _updateThumbPosition();
    _maybeTriggerHaptics();
  }

  void _updateThumbPosition() {
    if (!widget.controller.hasClients ||
        !widget.controller.position.hasContentDimensions) {
      return;
    }

    final viewportHeight = widget.controller.position.viewportDimension;

    final scrollFraction = _maxScroll == 0
        ? 0
        : (widget.controller.offset / _maxScroll).clamp(0.0, 1.0);
    final thumbTravelHeight =
        viewportHeight * (widget.scrollRangeEnd - widget.scrollRangeStart);

    setState(() {
      _thumbTop =
          viewportHeight * widget.scrollRangeStart +
          (thumbTravelHeight - _thumbSize) * scrollFraction;
    });
  }

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _railSlideController;
  late Animation<Offset> _railSlideAnimation;
  void _showThumbTemporarily() {
    if (widget.noTumb) return;
    _hideTimer?.cancel();

    if (!_isThumbVisible) {
      setState(() {
        _isThumbVisible = true;
      });
    }

    _railSlideController.reset(); // Bring rail back into view
    _fadeController.reset(); // Make thumb is fully visible before fade

    _hideTimer = Timer(widget.thumbVisibilityDuration, () async {
      if (!_isDragging && mounted) {
        List<Future> animations = [];
        animations.add(_fadeController.forward());
        animations.add(_railSlideController.forward());
        await Future.wait(animations);
        if (mounted) {
          setState(() {
            _isThumbVisible = false;
            _isDragging = false;
          });
          _fadeController.reset();
        }
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    _hideTimer?.cancel();

    setState(() {
      _isDragging = true;
      _isThumbVisible = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double containerHeight) {
    _setMaxScroll();

    // move thumb
    final minTop = containerHeight * widget.scrollRangeStart;
    final maxTop = containerHeight * widget.scrollRangeEnd - _thumbSize;
    _thumbTop = (details.globalPosition.dy - minTop - _thumbSize).clamp(
      minTop,
      maxTop,
    );
    setState(() {});

    // move page
    final scrollAreaHeight = maxTop - minTop;
    final scrollFraction = (_thumbTop - minTop) / scrollAreaHeight;

    final newScrollOffset = scrollFraction * _maxScroll;
    if (_isDragging) {
      widget.controller.jumpTo(newScrollOffset);
    }

    _maybeTriggerHaptics();
  }

  void _onDragEnd(DragEndDetails? details) {
    // details null if drag was cancelled
    setState(() {
      _isDragging = false;
    });
    _showThumbTemporarily();
  }

  int _getCurrentPage() {
    if (!widget.controller.hasClients || _ratios.isEmpty) {
      return 0;
    }

    final offset = widget.controller.offset;

    final total = _ratios.fold<double>(0.0, (a, b) => a + b);
    final cumulative = <double>[];
    double sum = 0.0;
    for (var ratio in _ratios) {
      sum += ratio;
      cumulative.add(sum);
    }

    final scrolledFraction = _maxScroll == 0 ? 0 : offset / _maxScroll;
    final scrollPosition = total * scrolledFraction;

    for (int i = 0; i < cumulative.length; i++) {
      if (scrollPosition < cumulative[i]) {
        return i;
      }
    }

    return _ratios.length - 1;
  }

  bool _atTopOrBottom = true;
  void _maybeTriggerHaptics() {
    final page = _getCurrentPage();
    if (!widget.noTumb && _isDragging && page != _lastPage) {
      HapticFeedback.selectionClick();
      _lastPage = page;
    }

    if ((widget.controller.offset <=
            widget.controller.position.minScrollExtent ||
        widget.controller.offset >= _maxScroll)) {
      if (!_atTopOrBottom) {
        if (_isDragging) {
          HapticFeedback.lightImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      }
      _atTopOrBottom = true;
    } else {
      _atTopOrBottom = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        widget.backgroundColor ??
        Theme.of(context).colorScheme.secondaryContainer;
    final textColor =
        widget.textColor ?? Theme.of(context).colorScheme.onSecondaryContainer;

    final railWidth = 12.0;
    final railColor = Theme.of(context).colorScheme.onPrimaryContainer;

    _setRatios();

    return LayoutBuilder(
      builder: (_, constraints) {
        return Stack(
          children: [
            widget.child,
            if (_isThumbVisible && widget.controller.hasClients)
              Positioned(
                right: -railWidth / 2,
                top:
                    constraints.maxHeight * widget.scrollRangeStart +
                    railWidth / 2,
                bottom:
                    constraints.maxHeight * (1.0 - widget.scrollRangeEnd) +
                    railWidth / 2,
                child: SlideTransition(
                  position: _railSlideAnimation,
                  child: Container(
                    width: railWidth,
                    decoration: BoxDecoration(
                      color: railColor,
                      borderRadius: BorderRadius.circular(railWidth / 2),
                      boxShadow: [tinyBoxShadow(context)],
                    ),
                  ),
                ),
              ),
            // Thumb
            if (_isThumbVisible && widget.controller.hasClients)
              Positioned(
                right: -16,
                top: _thumbTop.clamp(
                  constraints.maxHeight * widget.scrollRangeStart,
                  constraints.maxHeight * widget.scrollRangeEnd - _thumbSize,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: GestureDetector(
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: (d) =>
                        _onDragUpdate(d, constraints.maxHeight),
                    onVerticalDragEnd: (details) => _onDragEnd(details),
                    onVerticalDragCancel: () => _onDragEnd(null),
                    // Thumb Design
                    child: Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [tinyBoxShadow(context)],
                          ),
                          child: Text(
                            "${_getCurrentPage() + 1}/${_ratios.length}",
                            style: TextStyle(fontSize: 12, color: textColor),
                          ),
                        ),
                        Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            shape: BoxShape.circle,
                            boxShadow: [tinyBoxShadow(context)],
                          ),
                          child: Icon(Icons.drag_indicator, color: textColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class PagePreview extends StatefulWidget {
  const PagePreview({
    super.key,
    required this.docIndex,
    required this.pageIndex,
  });
  final int docIndex;
  final int pageIndex;

  @override
  State<PagePreview> createState() => PagePreviewState();
}

class PagePreviewState extends State<PagePreview> {
  // Widget
  int _selectedVersion = 0;
  int _selectedThumbnail = g.defaultIndex;
  final List<String> _versionPaths = List.generate(
    versionNames.length,
    (_) => "",
  );
  final List<bool> _versionLoading = List.generate(
    versionNames.length,
    (_) => true,
  );
  final List<Future<String>> _rotatedPhotoPaths = List.generate(
    3,
    (_) => Future<String>.value(""),
  );
  String _photoPath = "";
  // Reprocessing Parameters
  double? _ratioValue;
  double? _guiRatioValue;
  int? _orientationIndex;
  int? _guiOrientationIndex;
  int _totalRotation = 0;
  // Corner Points
  List<List<int>>? _cornerPoints;
  int _imagePixelWidth = 0;
  int _imagePixelHeight = 0;
  bool _hideOverlayReprocessing = false;
  bool _overlayZoomed = false;
  double? _unZoomedScale;
  // Status
  bool _isRotating = false;
  bool _metadataBlocked = true;
  // PageView
  final PageController _pageController = PageController();
  final PhotoViewController _photoViewController = PhotoViewController();
  double _photoScale = 0.0;
  double _evenPhotoScale = 0.0;
  double _oddPhotoScale = 0.0;
  // Thumbnail Bar
  final ScrollController _thumbnailScrollController = ScrollController();
  final double _thumbnailBarSize = 50;
  final double _thumbnailBarSizeSelected = 70;
  final double _thumbnailBarBoder = 3;
  final double _thumbnailBarBoderThumbnail = 5;
  final double _thumbnailBarPadding = 12;
  double _barWidth = 0.0;
  // Unlock page
  bool _pageUnlocked = false;
  // Imported PDF Mode
  bool _importedPdfMode = false;

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
    FilesHelper.deleteCachedRoatedImages();
    _initAsync();

    _photoViewController.outputStateStream.listen((
      PhotoViewControllerValue value,
    ) {
      setState(() {
        _photoScale = value.scale ?? _photoScale;
      });
    });
  }

  Future<void> _initAsync() async {
    _importedPdfMode = await MetadataHelper.readPageImportedPdf(
      widget.docIndex,
      widget.pageIndex,
    );
    if (_importedPdfMode && mounted) setState(() {});
    await _loadOldVersionFileNames();
    _pollImagesAndMetadata();
    _pageUnlocked = await g.metadataHelper.readPageUnlocked(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: true,
    );
    // if processing on init
    if (_versionPaths.any((element) => element.isEmpty)) {
      // Feedback Popup
      bool showRatingPopupWhileProcessing = feedbackHelper
          .canShowProcessingPopup();
      if (showRatingPopupWhileProcessing) {
        // ignore: use_build_context_synchronously
        feedbackHelper.showRatingDialog(context);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unZoomedScale = _photoViewController.scale;
    });
  }

  Future<void> _loadOldVersionFileNames() async {
    // set _versionPaths to old names, so that polling realizes that they are old
    List<String>? oldVersionFileNames =
        await MetadataHelper.readOldPageFileNames(
          widget.docIndex,
          widget.pageIndex,
          supressWarnings: true,
        );
    if (oldVersionFileNames == null) return;
    if (oldVersionFileNames.every((element) => element.isEmpty)) return;
    List<String> versionPaths;
    (versionPaths, _, _) = await g.filesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    );
    for (var (i, oldName) in oldVersionFileNames.indexed) {
      if (oldName.isNotEmpty && versionPaths[i].contains(oldName)) {
        _versionPaths[i] = versionPaths[i];
      }
    }
    _photoPath = _versionPaths.first;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _photoViewController.dispose();
    _thumbnailScrollController.dispose();
    _eventSubscription.cancel();
    FilesHelper.deleteCachedRoatedImages();
    super.dispose();
  }

  late final StreamSubscription<NotifierEvent> _eventSubscription;
  Future<void> _handleGlobalEvent(NotifierEvent event) async {
    if (!mounted) return;
    switch (event) {
      case NotifierEvent.setState:
        _pageUnlocked = await g.metadataHelper.readPageUnlocked(
          widget.docIndex,
          widget.pageIndex,
        );
        setState(() {});
        break;
      case NotifierEvent.imagesDeleted:
        if (!File(_photoPath).existsSync() && Navigator.canPop(context)) {
          _allowPop = true;
          Navigator.pop(context);
        }
        break;
      default:
    }
  }

  void _pollImagesAndMetadata() {
    _pollMetadata();
    _pollImages();
  }

  void _pollMetadata() {
    // Poll Metadtata
    _pollWhile(
      pollWhileCondition: () {
        return _ratioValue == null ||
            (!_importedPdfMode && _cornerPoints == null);
      },
      onTick: () async {
        await _loadPageMetadata(supressWarnings: true);
      },
      onComplete: () async {
        await _loadPageMetadata(supressWarnings: true);
        _unZoomedScale = _photoViewController.scale;
      },
    );
  }

  int _processingIndex = 0;
  void _pollImages() {
    // Poll Images
    final int thisProcessingIndex = _processingIndex;
    int completedCount = 0;
    bool photoWasRotated = _totalRotation != 0;
    for (int i = 0; i < _versionPaths.length; i++) {
      String polledPath = "";
      _versionLoading[i] = true;
      _pollWhile(
        pollWhileCondition: () {
          return thisProcessingIndex == _processingIndex &&
              !((polledPath.isNotEmpty && _versionPaths[i].isEmpty) ||
                  (polledPath.isNotEmpty &&
                      File(polledPath).existsSync() &&
                      (i == 0
                          ? polledPath != _photoPath && _totalRotation == 0 ||
                                !photoWasRotated
                          : polledPath != _versionPaths[i])));
        },
        onTick: () async {
          polledPath = await g.filesHelper.getVersionPath(
            widget.docIndex,
            widget.pageIndex,
            i,
            supressWarnings: true,
          );
        },
        onComplete: () {
          if (thisProcessingIndex != _processingIndex || !mounted) return;
          if (i == 0) {
            _versionPaths[i] = _photoPath = polledPath;
            FilesHelper.deleteCachedRoatedImages();
            _refreshCornersOverlay(supressWarnings: true);
          } else {
            _versionPaths[i] = polledPath;
          }
          _versionLoading[i] = false;
          if (++completedCount >= _versionPaths.length) {
            _processingIndex = 0;
          }
          if (mounted) setState(() {});
        },
      );
    }
    setState(() {
      _versionLoading;
    });
  }

  void _pollWhile({
    required bool Function() pollWhileCondition,
    required FutureOr<void> Function() onTick,
    FutureOr<void> Function()? onComplete,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    do {
      await onTick();
      await Future.delayed(delay);
    } while (mounted && pollWhileCondition());
    if (onComplete != null) {
      await onComplete();
    }
  }

  Future<void> _loadPageMetadata({bool supressWarnings = false}) async {
    _selectedThumbnail =
        await MetadataHelper.readPageThumbnailIndex(
          widget.docIndex,
          widget.pageIndex,
          supressWarnings: supressWarnings,
        ) ??
        _selectedThumbnail;
    _guiRatioValue = _ratioValue = await MetadataHelper.readPageRatioValue(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: supressWarnings,
    );
    _importedPdfMode = await MetadataHelper.readPageImportedPdf(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: supressWarnings,
    );
    if (_ratioValue != null) {
      _guiOrientationIndex = _orientationIndex = (_ratioValue! > 1.0) ? 0 : 1;
    }
    if (mounted) {
      setState(() {});
    }
    await _refreshCornersOverlay(supressWarnings: supressWarnings);
    if (mounted) {
      if ((_cornerPoints != null || _importedPdfMode) &&
          _guiRatioValue != null) {
        _hideOverlayReprocessing = false;
        _unZoomedScale = null;
        _metadataBlocked = false;
      }
      setState(() {});
    }
  }

  Future<void> _refreshCornersOverlay({bool supressWarnings = false}) async {
    // Corners
    _cornerPoints = await MetadataHelper.readPageCornerPoints(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: supressWarnings,
    );
    // Image pixel size
    final imageFile = File(_versionPaths[0]);
    if (_versionPaths[0].isEmpty || !imageFile.existsSync()) return;
    final ui.Image image = await decodeImageFromList(
      imageFile.readAsBytesSync(),
    );
    _imagePixelWidth = image.width;
    _imagePixelHeight = image.height;
    if (mounted) setState(() {});
  }

  void _reprocessingSetup() async {
    _processingIndex++;
    _hideOverlayReprocessing = true;
    _metadataBlocked = true;
    _ratioValue = null; // don't reset _new values, for uninterrupted display
    _orientationIndex = null;
    setState(() {});
  }

  void _reprocessingCleanup() {
    _evenPhotoScale = 0.0;
    _oddPhotoScale = 0.0;
    _refreshCornersOverlay();
    _pollImagesAndMetadata();
    _totalRotation = 0;
    setState(() {});
  }

  Future<void> _openWarpManuallyPage() async {
    Navigator.pushNamed(
      context,
      "/warp",
      arguments: {
        "pagePreviewState": this,
        "docIndex": widget.docIndex,
        "pageIndex": widget.pageIndex,
        "imagePath": _versionPaths.first,
        "cornerPoints": _cornerPoints,
        "rotation": _totalRotation,
      },
    );
  }

  Future<void> _popOnProFilterPopup(BuildContext context) async {
    //final bool? selectedUnlock = await
    showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock,
                color: Theme.of(context).colorScheme.onSurface,
                size: 30,
              ),
              SizedBox(width: 12),
              Flexible(child: Text(tr("pagePreview.backPopup.title"))),
            ],
          ),
          content: Text(tr("pagePreview.backPopup.text")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final bool purchased = await proPopup(context);
                if (context.mounted && purchased) {
                  Navigator.pop(context, purchased);
                }
              },
              icon: Icon(Icons.lock),
              label: Text(tr("popup.unlock")),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final bool adWatched = await _unlockPageWithAd(context);
                if (adWatched) {
                  _pageUnlocked = true;
                  g.metadataHelper.writePageUnlocked(
                    widget.docIndex,
                    widget.pageIndex,
                    true,
                  );
                  if (context.mounted) {
                    setState(() {});
                    Navigator.pop(context, true);
                  }
                }
              },
              icon: Icon(Icons.play_arrow),
              label: Text(tr("popup.watchAd")),
            ),
          ],
        );
      },
    );
    // Pop after Ad watched:
    //if (selectedUnlock == true) {
    //  // PostFrameCallback necessary for allowPop to register
    //  WidgetsBinding.instance.addPostFrameCallback((_) async {
    //    if (context.mounted) Navigator.maybePop(context);
    //  });
    //}
  }

  void _scrollToThumbnail(int index) {
    final int itemCount = _versionPaths.length;
    final double itemWidth =
        (_barWidth - MediaQuery.of(context).size.width) / (itemCount - 1);
    final double targetScrollOffset = (itemWidth * index);

    _thumbnailScrollController.animateTo(
      targetScrollOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // Page Preview
  bool _allowPop = true;
  @override
  Widget build(BuildContext context) {
    _barWidth =
        (_thumbnailBarPadding * 2) * _versionPaths.length +
        (_thumbnailBarSize + _thumbnailBarBoder * 2) *
            (_versionPaths.length - 1) +
        (_thumbnailBarSizeSelected + _thumbnailBarBoderThumbnail * 2);
    // Flags
    bool noReprocessingChanges =
        ((_guiRatioValue == null || (_ratioValue == _guiRatioValue)) &&
        (_orientationIndex == null ||
            (_orientationIndex == _guiOrientationIndex)) &&
        _totalRotation == 0);
    bool enableFAB0 =
        _versionPaths.first.isNotEmpty &&
        !_versionLoading[_selectedVersion] &&
        !_isRotating;
    bool enableFABs = _selectedVersion == 0
        ? (enableFAB0 && noReprocessingChanges)
        : _versionPaths[_selectedVersion].isNotEmpty &&
              !_versionLoading[_selectedVersion];
    _allowPop =
        g.proUnlocked ||
        !g.proFilterIndexes.contains(_selectedThumbnail) ||
        _pageUnlocked;

    return PopScope(
      canPop: _allowPop && noReprocessingChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!noReprocessingChanges) {
          // Exit edit mode
          _guiRatioValue = _ratioValue;
          _guiOrientationIndex = _orientationIndex;
          _totalRotation = 0;
          _versionPaths[0] = _photoPath;
          setState(() {});
        } else if (!_allowPop) {
          // Prevent pop when PRO filter is selected
          HapticFeedback.heavyImpact();
          _popOnProFilterPopup(context);
        } else {
          // New thumbnail
          if (_processingIndex == 0) {
            // If done processing
            imageProcessingManager.setNewThumbnail(
              widget.docIndex,
              widget.pageIndex,
              _selectedThumbnail,
              tmpPro: _pageUnlocked,
            );
          } else {
            // While still processing
            await MetadataHelper.writePageThumbnailIndex(
              widget.docIndex,
              widget.pageIndex,
              _selectedThumbnail,
              tmpPro: _pageUnlocked,
              supressWarnings: true,
            );
            globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
          }
          if (!didPop && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        // Top Bar
        appBar: AppBar(
          leading: noReprocessingChanges
              ? null
              : IconButton(
                  tooltip: tr("camera.viewer.back"),
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.maybePop(context),
                ),
          title: Text(
            tr(
              "pagePreview.pageIndex",
              namedArgs: {"pageIndex": "${widget.pageIndex + 1}"},
            ),
          ),
        ),
        body: Stack(
          children: [
            // Bg Shadow
            Align(
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: 1.0 / (_ratioValue ?? math.sqrt2),
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withAlpha(25),
                        blurRadius: 50,
                        spreadRadius: -20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Images (Page Versions)
            PhotoViewGallery.builder(
              pageController: _pageController,
              scrollPhysics: const PageScrollPhysics(),
              itemCount: _importedPdfMode || !noReprocessingChanges
                  ? 1
                  : _versionPaths.length,
              builder: (context, index) {
                // Loading indicator
                if (_versionPaths[index].isEmpty) {
                  return PhotoViewGalleryPageOptions.customChild(
                    child: IndicatorProcessingImage(),
                  );
                }
                // Photo
                if (index == 0) {
                  return PhotoViewGalleryPageOptions.customChild(
                    child: GestureDetector(
                      onLongPress:
                          !_importedPdfMode &&
                              !_overlayZoomed &&
                              !_hideOverlayReprocessing &&
                              enableFAB0 &&
                              !_metadataBlocked
                          ? () => _openWarpManuallyPage()
                          : null,
                      //onVerticalDragStart:
                      //    !pdfMode &&
                      //        !_overlayZoomed &&
                      //        !_hideOverlayReprocessing &&
                      //        enableFAB0 &&
                      //        !_metadataBlocked
                      //    ? (_) => _openWarpManuallyPage()
                      //    : null,
                      //onTap:
                      //    !pdfMode &&
                      //        !_overlayZoomed &&
                      //        !_hideOverlayReprocessing &&
                      //        enableFAB0 &&
                      //        !_metadataBlocked
                      //    ? () => _openWarpManuallyPage()
                      //    : null,
                      child: Stack(
                        children: [
                          PhotoView(
                            controller: _photoViewController,
                            imageProvider: FileImage(File(_versionPaths[0])),
                            filterQuality: FilterQuality.high,
                            minScale: PhotoViewComputedScale.contained,
                            maxScale: 1.0,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.broken_image,
                                color: Theme.of(context).disabledColor,
                              );
                            },
                            backgroundDecoration: BoxDecoration(
                              color: Colors.transparent,
                            ),
                            scaleStateChangedCallback: (scaleState) async {
                              // if zoomed in / out: hide overlay
                              if (scaleState == PhotoViewScaleState.initial ||
                                  scaleState == PhotoViewScaleState.covering &&
                                      _photoViewController.scale != 1.0) {
                                _unZoomedScale ??= _photoViewController.scale;
                              }
                              _overlayZoomed =
                                  _photoViewController.scale != _unZoomedScale;
                              setState(() {});
                              if (_unZoomedScale == null) return;
                              WidgetsBinding.instance.addPostFrameCallback((
                                _,
                              ) async {
                                if (!mounted) return;
                                // one frame delay to recheck when zooming in
                                _overlayZoomed =
                                    _photoViewController.scale !=
                                    _unZoomedScale;
                                setState(() {});
                                if (!_overlayZoomed) return;
                                // delay to update after zoom animation
                                // (inconsistenttly triggers sometimes after animation, sometimes before)
                                while (_overlayZoomed && mounted) {
                                  await Future.delayed(
                                    Duration(milliseconds: 300),
                                  );
                                  if (!mounted) return;
                                  _overlayZoomed =
                                      _photoViewController.scale !=
                                      _unZoomedScale;
                                }
                                setState(() {});
                              });
                            },
                          ),

                          // Corner Points
                          _displayCornersOverlay(context),
                        ],
                      ),
                    ),
                  );
                }
                // Processed Images
                return PhotoViewGalleryPageOptions(
                  imageProvider: FileImage(File(_versionPaths[index])),
                  filterQuality: FilterQuality.high,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: 1.0,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.broken_image,
                      color: Theme.of(context).disabledColor,
                    );
                  },
                );
              },
              backgroundDecoration: BoxDecoration(color: Colors.transparent),
              onPageChanged: (index) {
                if (index != 0) _selectedThumbnail = index;
                _selectedVersion = index;
                setState(() {});
                _scrollToThumbnail(index);
              },
            ),
            // Reprocessing Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Align(
                alignment: _selectedVersion == 0
                    ? Alignment.topCenter
                    : Alignment.topLeft,

                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [smallBoxShadow(context)],
                  ),
                  child: _selectedVersion == 0
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            spacing: 4,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                spacing: 6,
                                children: [
                                  if (_importedPdfMode) _pdfBadge(context),
                                  if (!_importedPdfMode)
                                    _aspectRatioDropDown(context),
                                  if (!_importedPdfMode)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: _orientationDropDown(context),
                                    ),
                                  _rotateButton(
                                    context,
                                    -90,
                                    Icons.rotate_left,
                                    tr("pagePreview.editBar.rotateL"),
                                  ),
                                  _rotateButton(
                                    context,
                                    90,
                                    Icons.rotate_right,
                                    tr("pagePreview.editBar.rotateR"),
                                  ),
                                ],
                              ),
                              _confirmReProcessingButton(
                                context,
                                noReprocessingChanges,
                              ),
                            ],
                          ),
                        )
                      : _toEditingButton(context),
                ),
              ),
            ),
          ],
        ),
        // Floating Action Buttons
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _selectedVersion == 0 && !_importedPdfMode
                ? Padding(
                    padding: EdgeInsets.only(
                      bottom: noReprocessingChanges ? 18 : 140,
                    ),
                    child: SizedBox(
                      width: noReprocessingChanges ? 40 : null,
                      height: noReprocessingChanges ? 40 : null,
                      child: FloatingActionButton(
                        heroTag: "adjustCorners",
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            noReprocessingChanges ? 12 : 16,
                          ),
                        ),
                        onPressed: enableFAB0 && !_metadataBlocked
                            ? () => _openWarpManuallyPage()
                            : null,
                        tooltip: enableFAB0 && !_metadataBlocked
                            ? tr("fabs.warp")
                            : tr("loading.waitingImage"),
                        backgroundColor: enableFAB0 && !_metadataBlocked
                            ? null
                            : Theme.of(context).disabledColor,
                        elevation: enableFAB0 && !_metadataBlocked ? null : 0.0,
                        child: Transform.scale(
                          scaleY: 0.8,
                          scaleX: 0.85,
                          filterQuality: FilterQuality.high,
                          child: Transform.translate(
                            offset: Offset(0, -1.8),
                            filterQuality: FilterQuality.high,
                            child: Transform(
                              alignment: Alignment.topCenter,
                              transform:
                                  (Matrix4.identity()..setEntry(3, 2, 0.0256)) *
                                  Matrix4.rotationX(-0.7),
                              filterQuality: FilterQuality.high,
                              child: Icon(
                                Icons.crop_free,
                                color: enableFAB0 && !_metadataBlocked
                                    ? null
                                    : Theme.of(context).disabledColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : SizedBox(),
            if (noReprocessingChanges)
              Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: FloatingActionButton(
                    heroTag: "savePageVersion",
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onPressed: enableFABs
                        ? () => _pagesPopup(
                            context,
                            [widget.pageIndex],
                            PopUpType.save,
                            widget.docIndex,
                            versionIndex: _selectedVersion,
                          )
                        : null,
                    tooltip: enableFABs
                        ? tr("fabs.save")
                        : tr("loading.waitingImage"),
                    backgroundColor: enableFABs
                        ? null
                        : Theme.of(context).disabledColor,
                    elevation: enableFABs ? null : 0.0,
                    child: Icon(
                      Icons.save,
                      color: enableFABs
                          ? null
                          : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
              ),
            if (noReprocessingChanges)
              Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: FloatingActionButton(
                  heroTag: "sharePageVersion",
                  onPressed: enableFABs
                      ? () => _pagesPopup(
                          context,
                          [widget.pageIndex],
                          PopUpType.share,
                          widget.docIndex,
                          versionIndex: _selectedVersion,
                        )
                      : null,
                  tooltip: enableFABs
                      ? tr("fabs.share")
                      : tr("loading.waitingImage"),
                  backgroundColor: enableFABs
                      ? null
                      : Theme.of(context).disabledColor,
                  elevation: enableFABs ? null : 0.0,
                  child: Icon(
                    Icons.share,
                    color: enableFABs ? null : Theme.of(context).disabledColor,
                  ),
                ),
              ),
          ],
        ),
        // Thumbnail Bar
        bottomNavigationBar: _importedPdfMode || !noReprocessingChanges
            ? null
            : SafeArea(
                child: Container(
                  height: 120,
                  alignment: Alignment.topCenter,
                  child: ScrollConfiguration(
                    behavior: NoStretchScrollBehavior(),
                    child: ListView.builder(
                      controller: _thumbnailScrollController,
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      shrinkWrap: true,
                      itemCount: _versionPaths.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            if (index != 0) _selectedThumbnail = index;
                            _selectedVersion = index;
                            setState(() {});
                            _pageController.jumpToPage(index);
                          },
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        _selectedThumbnail == index
                                            ? 13.75
                                            : 11.5,
                                      ),
                                      border: Border.all(
                                        color:
                                            _selectedThumbnail == index ||
                                                _selectedVersion == index
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.secondaryFixed
                                            : Colors.white54,
                                        width: _selectedThumbnail == index
                                            ? _thumbnailBarBoderThumbnail
                                            : _thumbnailBarBoder,
                                      ),
                                      boxShadow: [bigBoxShadow(context)],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8.5),
                                      child: SizedBox(
                                        width: _selectedVersion == index
                                            ? _thumbnailBarSizeSelected
                                            : _thumbnailBarSize,
                                        height: _selectedVersion == index
                                            ? _thumbnailBarSizeSelected
                                            : _thumbnailBarSize,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            _versionPaths[index].isNotEmpty
                                                ? Image.file(
                                                    File(_versionPaths[index]),
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return Padding(
                                                            padding: EdgeInsets.all(
                                                              _thumbnailBarPadding,
                                                            ),
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image,
                                                              color: Theme.of(
                                                                context,
                                                              ).disabledColor,
                                                            ),
                                                          );
                                                        },
                                                  )
                                                : SizedBox(),
                                            if (_versionLoading[index])
                                              Container(
                                                alignment: Alignment.center,
                                                color: Theme.of(
                                                  context,
                                                ).disabledColor,
                                                child: Padding(
                                                  padding: EdgeInsets.all(
                                                    _thumbnailBarPadding,
                                                  ),
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Locked Badge
                                  (g.proUnlocked ||
                                          !g.proFilterIndexes.contains(index) ||
                                          _pageUnlocked)
                                      ? SizedBox()
                                      : Positioned(
                                          top: 0,
                                          right: 0,
                                          child: CustomIconButton(
                                            tooltip: "",
                                            onTap: null,
                                            icon: Icons.lock,
                                          ),
                                        ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                versionNames[index],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.visible,
                                ),
                                softWrap: false,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Padding _toEditingButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: CustomIconButton(
        tooltip: tr("pagePreview.editBar.redirect"),
        onTap: () {
          setState(() => _selectedVersion = 0);
          _pageController.jumpToPage(0);
        },
        isFlat: true,
        icon: Icons.keyboard_arrow_left,
        iconColor: Theme.of(context).colorScheme.onSurface,
        buttonColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        constraints: BoxConstraints(maxHeight: 48, maxWidth: 80),
        child: Icon(Icons.edit, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  CustomIconButton _rotateButton(
    BuildContext context,
    int rotation,
    IconData icon,
    String tooltip,
  ) {
    return CustomIconButton(
      constraints: BoxConstraints(maxHeight: 42, maxWidth: 42),
      isDisabled: _versionPaths.first.isEmpty || _metadataBlocked,
      onTap: () async {
        _totalRotation = (_totalRotation + rotation) % 360;
        int quarterTurns = _totalRotation ~/ 90;
        //_photoViewController.rotation = math.pi / 2 * quarterTurns;

        setState(() {
          _isRotating = true;
          _guiOrientationIndex =
              ((_guiOrientationIndex ?? 0) - 1) * (-1); // toggle
          _guiRatioValue = 1.0 / _guiRatioValue!;
        });
        if (_totalRotation == 0) {
          setState(() {
            _versionPaths[0] = _photoPath;
            _isRotating = false;
          });
        } else {
          _rotatedPhotoPaths[quarterTurns - 1] =
              FilesHelper.rotateImageInTmpDir(_photoPath, _totalRotation);
          _rotatedPhotoPaths[quarterTurns - 1].whenComplete(() async {
            // if image matches current rotation
            if (_totalRotation ~/ 90 == quarterTurns) {
              _versionPaths[0] = await _rotatedPhotoPaths[quarterTurns - 1];
              if (mounted) {
                _isRotating = false;
                setState(() {});
              }
            }
          });
        }
      },
      isFlat: true,
      //isDisabled: _rotationOngoing,
      icon: icon,
      iconColor: Theme.of(context).colorScheme.onSurface,
      buttonColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      tooltip: tooltip,
    );
  }

  CustomIconButton _confirmReProcessingButton(
    BuildContext context,
    bool noReprocessingChanges,
  ) {
    return CustomIconButton(
      constraints: BoxConstraints(maxHeight: 30, maxWidth: 30),
      buttonColor: Theme.of(context).colorScheme.primaryContainer,
      icon: Icons.check,
      iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
      isDisabled:
          _metadataBlocked ||
          _isRotating ||
          _versionPaths.isEmpty ||
          _versionPaths.first.isEmpty ||
          !File(_versionPaths.first).existsSync(),
      isHidden: noReprocessingChanges,
      tooltip: tr("pagePreview.editBar.confirm"),
      onTap: () async {
        reprocessPhoto();
      },
    );
  }

  Future<void> reprocessPhoto({List<List<int>>? newCornerPointsIn}) async {
    _reprocessingSetup();

    bool onlyRotation = true;
    bool customCorners = false;

    // Read Matadata
    var metadata = await g.metadataHelper.readPageProcessingMetadata(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: _importedPdfMode,
    );
    double? ratioValue = metadata.$1;

    await imageProcessingManager.killIsolatesOfPage(
      widget.docIndex,
      widget.pageIndex,
    );
    // Get all current paths after killing for correct polling
    final currentPaths = (await g.filesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    )).$1;
    _photoPath = currentPaths[0];
    if (_totalRotation == 0) _versionPaths[0] = _photoPath;
    _versionPaths.setRange(
      1,
      _versionPaths.length,
      (await g.filesHelper.getImagePathsForPage(
        widget.docIndex,
        widget.pageIndex,
      )).$1.getRange(1, _versionPaths.length),
    );

    // Use new / rotate old corner points
    List<List<int>>? newCornerPoints;
    if (newCornerPointsIn == null) {
      newCornerPoints = metadata.$2;
      if (newCornerPoints != null) {
        newCornerPoints = rotateCornerPoints(newCornerPoints);
      }
    } else {
      newCornerPoints = List.from(newCornerPointsIn);
      onlyRotation = false;
      customCorners = true;
    }

    await MetadataHelper.writePageProcessingMetadata(
      widget.docIndex,
      widget.pageIndex,
      customCorners ? null : _guiRatioValue,
      newCornerPoints,
    );

    // Compare old and new metadata -> only rotation?
    if (onlyRotation &&
        _guiRatioValue != null &&
        ratioValue != _guiRatioValue &&
        ratioValue != 1.0 / _guiRatioValue!) {
      onlyRotation = false;
    }
    int quarterTurns = (_totalRotation ~/ 90) % 4;
    if (onlyRotation &&
            quarterTurns.isEven &&
            _orientationIndex != _guiOrientationIndex ||
        quarterTurns.isOdd && _orientationIndex == _guiOrientationIndex) {
      onlyRotation = false;
    }
    // Can't rotate if during processing, because rotatePage needas all images of the page
    if (onlyRotation && _processingIndex != 0) {
      onlyRotation = false;
    }

    if (onlyRotation &&
        (_importedPdfMode ||
            _versionPaths.every((path) => File(path).existsSync()))) {
      if (newCornerPoints != null) {
        await MetadataHelper.writePageCornerPoints(
          widget.docIndex,
          widget.pageIndex,
          newCornerPoints,
        );
      }
      imageProcessingManager.rotatePage(
        widget.docIndex,
        widget.pageIndex,
        _versionPaths,
        _totalRotation,
        _selectedThumbnail,
      );
    } else {
      imageProcessingManager.reprocessPage(
        widget.docIndex,
        widget.pageIndex,
        _versionPaths[0], // potentially rotated image
        customCorners ? null : _guiRatioValue,
        newCornerPoints,
        _totalRotation,
      );
    }
    _reprocessingCleanup();
  }

  List<List<int>> rotateCornerPoints(List<List<int>> cornerPoints) {
    if (_totalRotation == 0) return cornerPoints;
    int quarterTurns = (_totalRotation ~/ 90) % 4;

    // Apply rotation logic to each point
    List<List<int>> rotated = cornerPoints.map((p) {
      int row = p[0];
      int col = p[1];

      switch (quarterTurns) {
        case 1: // 90°
          return [col, _imagePixelHeight - row];
        case 2: // 180°
          return [_imagePixelHeight - row, _imagePixelWidth - col];
        case 3: // 270°
          return [_imagePixelWidth - col, row];
        default: // 0°
          return [row, col];
      }
    }).toList();

    // Rotate the list order to keep top-left point first
    for (var i = 0; i < quarterTurns; i++) {
      rotated = [rotated[1], rotated[3], rotated[0], rotated[2]];
    }

    return rotated;
  }

  Container _pdfBadge(BuildContext context) {
    const double height = 30;
    const double radius = 20;

    return Container(
      constraints: const BoxConstraints(maxHeight: height, minHeight: height),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: Tooltip(
        message: tr("pagePreview.editBar.pdf"),
        waitDuration: Duration(milliseconds: 400),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: () => _enableEditingForImportedPdfPagePopup(context),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "PDF",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _enableEditingForImportedPdfPagePopup(BuildContext context) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
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
              Flexible(child: Text(tr("pagePreview.editBar.pdfPopup.title"))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text(tr("pagePreview.editBar.pdfPopup.text"))],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(tr("pagePreview.editBar.pdfPopup.confirm")),
            ),
          ],
        );
      },
    );

    // Handle Results after Dialog closes
    if (confirmed == true) {
      await MetadataHelper.writePageImportedPdf(
        widget.docIndex,
        widget.pageIndex,
        false,
      );
      _importedPdfMode = false;
      setState(() {});
      await MetadataHelper.writePageThumbnailIndex(
        widget.docIndex,
        widget.pageIndex,
        g.defaultIndex,
      );
      reprocessPhoto();
    }
  }

  Container _aspectRatioDropDown(BuildContext context) {
    const double height = 30;
    int? initialIndex = g.availableAspectRatios.indexWhere(
      (element) =>
          _guiRatioValue != null &&
          (element.value == _guiRatioValue ||
              element.value == 1.0 / _guiRatioValue!),
    );
    initialIndex = initialIndex != -1 ? initialIndex : null;
    return Container(
      constraints: const BoxConstraints(maxHeight: height, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          isDense: true,
          isExpanded: false,
          alignment: Alignment.center,
          icon:
              SizedBox.shrink(), //Icon(Icons.arrow_drop_down, color: Colors.black),
          value: initialIndex,
          items: List.generate(
            g.availableAspectRatios.length + 1,
            (i) => DropdownMenuItem(
              alignment: Alignment.center,
              value: i,
              child: Text(
                i == g.availableAspectRatios.length
                    ? "+"
                    : g.availableAspectRatios[i].name,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          onChanged: _versionPaths.first.isEmpty || _metadataBlocked
              ? null
              : (int? newValue) async {
                  if (newValue == g.availableAspectRatios.length) {
                    await selectAspectRatiosDialog(context);
                    setState(() {});
                  } else if (newValue != null && newValue != _guiRatioValue) {
                    setState(() {
                      final newPortraitValue =
                          g.availableAspectRatios[newValue].value;
                      _guiRatioValue = (_guiOrientationIndex ?? 0) == 0
                          ? newPortraitValue
                          : 1 / newPortraitValue;
                    });
                  }
                },
        ),
      ),
    );
  }

  Container _orientationDropDown(BuildContext context) {
    const double height = 30;
    List<String> orientationsList = [
      tr("pagePreview.editBar.portrait"),
      tr("pagePreview.editBar.landscape"),
    ];
    return Container(
      constraints: const BoxConstraints(maxHeight: height, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          isDense: true,
          isExpanded: false,
          alignment: Alignment.center,
          icon:
              SizedBox.shrink(), //Icon((_orientation ?? 0 == 0)? Icons.crop_portrait: Icons.crop_landscape,),
          value: _guiOrientationIndex,
          items: List.generate(
            orientationsList.length,
            (i) => DropdownMenuItem(
              alignment: Alignment.center,
              value: i,
              child: Text(
                orientationsList[i],
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          onChanged: _versionPaths.first.isEmpty || _metadataBlocked
              ? null
              : (int? newValue) {
                  if (newValue != null && newValue != _guiOrientationIndex) {
                    _guiOrientationIndex = newValue;
                    if (_guiRatioValue! > 1.0 && _guiOrientationIndex != 0 ||
                        _guiRatioValue! < 1.0 && _guiOrientationIndex != 1) {
                      _guiRatioValue = 1.0 / _guiRatioValue!;
                    }
                    setState(() {});
                  }
                },
        ),
      ),
    );
  }

  Widget _displayCornersOverlay(BuildContext context) {
    if (_importedPdfMode ||
        (_cornerPoints == null || _cornerPoints!.isEmpty) ||
        _photoScale == 0.0 ||
        _isRotating ||
        _hideOverlayReprocessing ||
        _overlayZoomed ||
        _imagePixelHeight == 0 ||
        _imagePixelWidth == 0) {
      return SizedBox();
    }
    int quarterTurns = _totalRotation ~/ 90;

    double displayHeight;
    double displayWidth;
    if (quarterTurns.isEven) {
      if (_evenPhotoScale == 0.0 && _photoScale != _oddPhotoScale) {
        _evenPhotoScale = _photoScale;
      } else if (_evenPhotoScale != 0.0) {
        _photoScale = _evenPhotoScale;
      }
      displayHeight = _imagePixelHeight * _photoScale;
      displayWidth = _imagePixelWidth * _photoScale;
    } else {
      if (_oddPhotoScale == 0.0 && _photoScale != _evenPhotoScale) {
        _oddPhotoScale = _photoScale;
      } else if (_oddPhotoScale != 0.0) {
        _photoScale = _oddPhotoScale;
      }
      displayHeight = _imagePixelWidth * _photoScale;
      displayWidth = _imagePixelHeight * _photoScale;
    }

    // Apply rotation to corner points visually
    List<Offset> scaledPoints = _cornerPoints!.map((point) {
      double x = point[1] * _photoScale;
      double y = point[0] * _photoScale;
      return Offset(x, y);
    }).toList();

    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: Stack(
              children: [
                /// Corner
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 6.0,
                    color: Colors.black.withAlpha(70),
                    offset: 0.1025,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 8.0,
                    color: Colors.black.withAlpha(20),
                    offset: 0.105,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 10.0,
                    color: Colors.black.withAlpha(10),
                    offset: 0.1075,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 4.0,
                    color: Theme.of(context).colorScheme.primaryFixed,
                    offset: 0.1,
                    normalizedOffset: false,
                  ),
                ),
                // Middle Section
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 3.0,
                    color: Colors.black.withAlpha(70),
                    offset: 0.605,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 4.5,
                    color: Colors.black.withAlpha(20),
                    offset: 0.61,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 6.0,
                    color: Colors.black.withAlpha(10),
                    offset: 0.615,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 1.5,
                    color: Theme.of(context).colorScheme.primaryFixed,
                    offset: 0.6,
                    normalizedOffset: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NoStretchScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Don't show any overscroll indicators (no stretch/glow)
    return child;
  }
}

class SelectableListView extends StatefulWidget {
  final int initialSelected;
  final Function(int index)? onSelectionChanged;

  const SelectableListView({
    super.key,
    this.initialSelected = 0,
    this.onSelectionChanged,
  });

  @override
  State<SelectableListView> createState() => _SelectableListViewState();
}

class _SelectableListViewState extends State<SelectableListView> {
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialSelected;
    // Ensure initial item is visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToIndex(_selectedIndex);
    });
  }

  void _scrollToIndex(int index) {
    const double itemWidth = 100.0; // Customize for your item width
    _scrollController.animateTo(
      index * itemWidth,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void selectIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _scrollToIndex(index);
    widget.onSelectionChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: 20,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedIndex;
          return GestureDetector(
            onTap: () => selectIndex(index),
            child: Container(
              width: 100,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.transparent,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text('Item $index'),
            ),
          );
        },
      ),
    );
  }
}

//class _FrameLinePainter extends CustomPainter {
//  final List<Offset> points;
//  final color;
//  final strokeWidth;
//
//  _FrameLinePainter({
//    required this.points,
//    this.color = Colors.black45,
//    this.strokeWidth = 7.0,
//  });
//
//  @override
//  void paint(Canvas canvas, Size size) {
//    if (points.length < 2) return;
//
//    final paintEdges = Paint()
//      ..color = color
//      ..strokeWidth = strokeWidth
//      ..style = PaintingStyle.stroke
//      ..isAntiAlias = true;
//
//    var order = [0, 2, 3, 1];
//    List<Offset> orderedPoints = order.map((i) => points[i]).toList();
//
//    // Edges
//    final path = Path();
//    path.moveTo(points[0].dx, points[0].dy);
//    for (int i = 1; i < orderedPoints.length; i++) {
//      path.lineTo(orderedPoints[i].dx, orderedPoints[i].dy);
//    }
//    path.close();
//    canvas.drawPath(path, paintEdges);
//  }
//
//  @override
//  bool shouldRepaint(covariant _FrameLinePainter oldDelegate) =>
//      oldDelegate.points != points;
//}

class _CornerLinePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final double offset;
  final bool normalizedOffset;

  _CornerLinePainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.offset,
    required this.normalizedOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paintCorners = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var order = [0, 2, 3, 1];
    List<Offset> orderedPoints = order.map((i) => points[i]).toList();

    // Corners and middle of edges
    for (int i = 0; i < orderedPoints.length; i++) {
      Offset p1 = orderedPoints[i];
      Offset p2 = orderedPoints[(i + 1) % orderedPoints.length];
      Offset p0 = orderedPoints[(i - 1) % orderedPoints.length];
      Offset delta0 = p2 - p1;
      Offset delta2 = p0 - p1;
      Offset deltaN0 = delta0 / delta0.distance;
      Offset deltaN2 = delta2 / delta2.distance;
      Offset offset0 = p1 + (normalizedOffset ? deltaN0 : delta0) * offset;
      Offset offset2 = p1 + (normalizedOffset ? deltaN2 : delta2) * offset;

      final path = Path();
      path.moveTo(offset0.dx, offset0.dy);
      path.lineTo(p1.dx, p1.dy);
      path.lineTo(offset2.dx, offset2.dy);
      canvas.drawPath(path, paintCorners);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerLinePainter oldDelegate) =>
      oldDelegate.points != points;
}

class _MiddleLinePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final double offset;
  final bool normalizedOffset;

  _MiddleLinePainter({
    required this.points,
    this.color = Colors.black38,
    this.strokeWidth = 7.0,
    this.offset = 17.0,
    this.normalizedOffset = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paintCorners = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var order = [0, 2, 3, 1];
    List<Offset> orderedPoints = order.map((i) => points[i]).toList();

    // Corners and middle of edges
    for (int i = 0; i < orderedPoints.length; i++) {
      Offset p1 = orderedPoints[i];
      Offset p2 = orderedPoints[(i + 1) % orderedPoints.length];
      Offset delta = p2 - p1;
      Offset deltaN = delta / delta.distance;
      p1 -= deltaN * strokeWidth / 2;
      p2 += deltaN * strokeWidth / 2;
      Offset middleOffset1 = p1 + (normalizedOffset ? deltaN : delta) * offset;
      Offset middleOffset2 = p2 - (normalizedOffset ? deltaN : delta) * offset;
      canvas.drawLine(middleOffset1, middleOffset2, paintCorners);
    }
  }

  @override
  bool shouldRepaint(covariant _MiddleLinePainter oldDelegate) =>
      oldDelegate.points != points;
}

class IndicatorProcessingImage extends StatelessWidget {
  const IndicatorProcessingImage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(tr("loading.processingImage"), textAlign: TextAlign.center),
      ],
    );
  }
}

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

class CustomIconButton extends StatelessWidget {
  final VoidCallback? onTap;
  final BoxConstraints constraints;
  final Color? buttonColor;
  final IconData icon;
  final Color? iconColor;
  final bool isFlat;
  final bool isHidden;
  final bool isDisabled;
  final String? tooltip;
  final Widget child;

  const CustomIconButton({
    super.key,
    required this.onTap,
    this.constraints = const BoxConstraints(maxHeight: 36, maxWidth: 36),
    this.buttonColor,
    this.icon = Icons.check,
    this.iconColor,
    this.isFlat = false,
    this.isHidden = false,
    this.isDisabled = false,
    required this.tooltip,
    this.child = const SizedBox(),
  });

  @override
  Widget build(BuildContext context) {
    final double radius =
        math.min(constraints.maxHeight, constraints.maxWidth) / 2;
    return isHidden
        ? Stack()
        : Stack(
            children: [
              Container(
                constraints: constraints,
                decoration: isFlat
                    ? null
                    : BoxDecoration(
                        color: isDisabled
                            ? Theme.of(context).disabledColor
                            : buttonColor ??
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: isDisabled
                            ? null
                            : [smallBoxShadow(context)],
                      ),
              ),
              SizedBox(
                height: constraints.maxHeight,
                width: constraints.maxWidth,
                child: Tooltip(
                  message: tooltip ?? "",
                  waitDuration: Duration(milliseconds: 400),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(radius),
                      onTap: isDisabled ? null : onTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            color: isDisabled
                                ? Theme.of(context).disabledColor
                                : iconColor ??
                                      Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                          ),
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
  }
}

class Warp extends StatefulWidget {
  final PagePreviewState pagePreviewState;
  final int docIndex;
  final int pageIndex;
  final String imagePath;
  final List<List<int>> cornerPoints;
  final int rotation;

  const Warp({
    super.key,
    required this.pagePreviewState,
    required this.docIndex,
    required this.pageIndex,
    required this.imagePath,
    required this.cornerPoints,
    required this.rotation,
  });

  @override
  State<Warp> createState() => _WarpState();
}

class _WarpState extends State<Warp> {
  List<Offset> _initialScaledPoints = [];
  List<Offset> _scaledPoints = [];
  double _screenWidth = 0;
  double _screenHeight = 0;
  double _displayHeigth = 0;
  double _pointsScale = 1.0;
  int _imagePixelWidth = 0;
  int _imagePixelHeight = 0;
  int? _currentCorner;
  Offset _touchOffset = Offset(0, 0);
  bool _panning = false;
  double _imageScale = 0;

  ui.Image? _magnifierImage;
  bool _magnifierImageLoading = true;
  static const double _magnifierSize = 200;

  final List<PositionTimestamp> _positionHistory = [];
  static const int _historyDurationMs = 400;

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
    _initAsync();
    _initMagnifier();
  }

  void _initAsync() async {
    ui.Image image = await decodeImageFromList(
      File(widget.imagePath).readAsBytesSync(),
    );
    _imagePixelWidth = image.width;
    _imagePixelHeight = image.height;
    if (mounted) {
      _screenWidth = MediaQuery.of(context).size.width;
      _screenHeight = MediaQuery.of(context).size.height - 430;
    }
    _pointsScale = _screenWidth / _imagePixelWidth;
    _displayHeigth = _imagePixelHeight * _pointsScale;

    var rotatedPoints = widget.pagePreviewState.rotateCornerPoints(
      widget.cornerPoints,
    );

    _scaledPoints = rotatedPoints.map((point) {
      double x = point[1] * _pointsScale;
      double y = point[0] * _pointsScale;
      return Offset(x, y);
    }).toList();
    _initialScaledPoints = List<Offset>.from(_scaledPoints);

    _scaleImage(init: true);
  }

  void _scaleImage({bool init = false}) {
    double scaleDownY = 0.0;
    for (var point in _scaledPoints) {
      double pointScaleDownY = point.dy - _screenHeight;
      if (pointScaleDownY > scaleDownY) {
        scaleDownY = pointScaleDownY;
      }
    }
    double scaleDownX = 0.0;
    for (var point in _scaledPoints) {
      double pointScaleDownX1 = point.dx - (_screenWidth - _magnifierSize / 4);
      double pointScaleDownX2 = (_magnifierSize / 4) - point.dx;
      double pointScaleDownX = math.max(pointScaleDownX1, pointScaleDownX2);
      if (pointScaleDownX > scaleDownX) {
        scaleDownX = pointScaleDownX;
      }
    }
    double imageScaleY = (_displayHeigth - scaleDownY) / _displayHeigth;
    double imageScaleX = (_screenWidth - scaleDownX) / _screenWidth;
    double newImageScale = math.min(imageScaleY, imageScaleX);
    if (init) {
      _imageScale = newImageScale;
    } else {
      if (mounted) {
        double scaleDiff = newImageScale - _imageScale;
        if (!scaleDiff.isNegative || scaleDiff < 0.1) {
          _imageScale += scaleDiff / 40.0;
          setState(() {});
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initMagnifier() async {
    final file = File(widget.imagePath);
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    if (mounted) {
      _magnifierImage = frameInfo.image;
      _magnifierImageLoading = false;
      setState(() {});
    }
  }

  Future<bool> _leaveConfirmationDialog() async {
    if (_initialScaledPoints[0] == _scaledPoints[0] &&
        _initialScaledPoints[1] == _scaledPoints[1] &&
        _initialScaledPoints[2] == _scaledPoints[2] &&
        _initialScaledPoints[3] == _scaledPoints[3] &&
        !_panningDelayed) {
      return true;
    }
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cancel,
                color: Theme.of(context).colorScheme.onSurface,
                size: 30,
              ),
              SizedBox(width: 12),
              Flexible(child: Text(tr("warp.discardPopup.title"))),
            ],
          ),
          content: Text(tr("warp.discardPopup.text")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                tr("warp.discardPopup.discard"),
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
    return confirmDelete == true;
  }

  final GlobalKey _imageAreaKey = GlobalKey();
  bool _allowPop = true;
  bool _panningDelayed = false;
  final double _circleSize = 40;

  // Warp
  @override
  Widget build(BuildContext context) {
    Rect cropRect =
        _scaledPoints.isNotEmpty &&
            _currentCorner != null &&
            _imageScale != 0 &&
            _screenWidth != 0 &&
            _imagePixelWidth != 0
        ? Rect.fromCenter(
            center: Offset(
              _scaledPoints[_currentCorner!].dx / _pointsScale,
              _scaledPoints[_currentCorner!].dy / _pointsScale,
            ),
            width: _circleSize / _imageScale / _screenWidth * _imagePixelWidth,
            height: _circleSize / _imageScale / _screenWidth * _imagePixelWidth,
          )
        : Rect.zero;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_allowPop) {
          HapticFeedback.heavyImpact();
          if (await _leaveConfirmationDialog()) {
            if (mounted && context.mounted) {
              Navigator.pop(context);
            }
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(tr("warp.title")),
          actions: [
            CustomIconButton(
              onTap: () => _saveCorners(),
              icon: Icons.check,
              tooltip: tr("warp.confirm"),
            ),
            SizedBox(width: 12),
          ],
        ),
        body: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 24.0,
          maxHeight: double.infinity,
          child: Column(
            children: [
              // Magnifier
              SizedBox(
                width: _magnifierSize,
                height: _magnifierSize,
                child: !_magnifierImageLoading && _currentCorner != null
                    ? Stack(
                        children: [
                          SizedBox(
                            width: _magnifierSize,
                            height: _magnifierSize,
                            child: CustomPaint(
                              painter: CircularCropPainter(
                                image: _magnifierImage!,
                                cropRect: cropRect,
                              ),
                            ),
                          ),
                          _screenWidth != 0
                              ? CustomPaint(
                                  size: Size(_screenWidth, _displayHeigth),
                                  painter: _ZoomLinePainter(
                                    cornerPoints: _scaledPoints,
                                    color: Colors.white,
                                    strokeWidth: 1.0,
                                    colorBg: Colors.black45,
                                    strokeWidthBg: 3.0,
                                    currentCorner: _currentCorner!,
                                    zoomSize: _magnifierSize,
                                  ),
                                )
                              : SizedBox(),
                        ],
                      )
                    : SizedBox(),
              ),
              SizedBox(height: 24),
              // Image + CornersOverlay
              _displayHeigth != 0 && _imageScale != 0
                  ? Transform.translate(
                      offset: Offset(
                        0,
                        ((_imageScale * _displayHeigth - _displayHeigth) / 2),
                      ),
                      child: Transform.scale(
                        scale: _imageScale,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(child: Image.file(File(widget.imagePath))),
                            _draggableCornersOverlay(_imageScale),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(),
            ],
          ),
        ),
      ),
    );
  }

  _saveCorners() {
    for (var (i, scaledPoint) in _scaledPoints.indexed) {
      widget.cornerPoints[i] = [
        (scaledPoint.dy / _pointsScale).toInt(),
        (scaledPoint.dx / _pointsScale).toInt(),
      ];
    }
    widget.pagePreviewState.reprocessPhoto(
      newCornerPointsIn: widget.cornerPoints,
    );
    _allowPop = true;
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  void didUpdateWidget(Warp oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only reload the image if the imagePath changed
    if (widget.imagePath != oldWidget.imagePath) {
      setState(() {
        _magnifierImageLoading = true;
        _magnifierImage = null;
      });
      _initMagnifier();
    }
  }

  Widget _draggableCornersOverlay(double counterScale) {
    if (_screenWidth == 0 || counterScale == 0) {
      return SizedBox();
    }

    return Center(
      child: SizedBox(
        key: _imageAreaKey,
        width: _screenWidth,
        height: _displayHeigth,
        child: Stack(
          children: [
            // Dark frame
            CustomPaint(
              size: Size(_screenWidth, _displayHeigth),
              painter: _MiddleLinePainter(
                points: _scaledPoints,
                color: Theme.of(
                  context,
                ).colorScheme.onPrimaryFixed.withAlpha(100),
                strokeWidth: 7.0 / counterScale,
                normalizedOffset: true,
                offset: (_circleSize + 8) / counterScale / 2,
              ),
            ),
            // Sharp corners reaching outside circle
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: _CornerLinePainter(
                  points: _scaledPoints,
                  color: Theme.of(context).colorScheme.primaryFixed,
                  strokeWidth: 1.0 / counterScale,
                  offset: 0.25,
                  normalizedOffset: false,
                ),
              ),
            ),
            // Sharp middle section
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: _MiddleLinePainter(
                  points: _scaledPoints,
                  color: Theme.of(context).colorScheme.primaryFixed,
                  strokeWidth: 1.0,
                  offset: 0.55,
                  normalizedOffset: false,
                ),
              ),
            ),

            // Draggable edges
            ...[
              [0, 2, 1, 3], // top
              [2, 3, 0, 1], // right
              [3, 1, 2, 0], // bottom
              [1, 0, 3, 2], // left
            ].map((points) {
              final a = _scaledPoints[points[0]];
              final b = _scaledPoints[points[1]];
              final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
              final length = (b - a).distance;
              final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);

              return Positioned(
                left: center.dx - length / 2,
                top: center.dy - 12,
                child: Transform.rotate(
                  angle: angle,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (details) {
                      _handleEdgeDrag(
                        indexA: points[0],
                        indexB: points[1],
                        neighborA: points[2],
                        neighborB: points[3],
                        details: details,
                      );
                    },
                    child: Container(
                      width: length,
                      height: 24,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              );
            }),

            // Draggable corner points
            ..._scaledPoints.asMap().entries.map((entry) {
              final index = entry.key;
              final offset = entry.value;
              final isCurrent = index == _currentCorner;

              return Positioned(
                left: offset.dx - _circleSize / counterScale / 2,
                top: offset.dy - _circleSize / counterScale / 2,
                child: GestureDetector(
                  onPanStart: (details) {
                    if (_panning) return;
                    _allowPop = false;
                    _currentCorner = index;
                    final box =
                        _imageAreaKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (box == null) return;
                    Offset localPosition = box.globalToLocal(
                      details.globalPosition,
                    );
                    _touchOffset = localPosition - _scaledPoints[index];
                    _positionHistory.clear();
                    _positionHistory.add(
                      PositionTimestamp(
                        position: _scaledPoints[index],
                        timestamp: DateTime.now(),
                      ),
                    );
                    _panning = true;
                    _panningDelayed = true;
                  },
                  onPanUpdate: (details) {
                    DateTime now = DateTime.now();
                    // Haptic Feedback
                    if (_positionHistory.isNotEmpty &&
                        now.difference(_positionHistory.last.timestamp) >
                            Duration(milliseconds: 25)) {
                      HapticFeedback.selectionClick();
                    }
                    final box =
                        _imageAreaKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (box == null) return;
                    Offset localPosition = box.globalToLocal(
                      details.globalPosition,
                    );
                    Offset newPos = localPosition - _touchOffset;
                    double newX = newPos.dx.clamp(0.0, _screenWidth);
                    double newY = newPos.dy.clamp(0.0, _displayHeigth);

                    // Limit relative corner positions
                    switch (index) {
                      case 0: // top left
                        double maxX = [
                          _scaledPoints[2].dx,
                          _scaledPoints[3].dx,
                        ].reduce(math.min);
                        double maxY = [
                          _scaledPoints[1].dy,
                          _scaledPoints[3].dy,
                        ].reduce(math.min);
                        if (newX > maxX) {
                          newX = maxX;
                        }
                        if (newY > maxY) {
                          newY = maxY;
                        }
                        break;
                      case 1: // bottom left
                        double maxX = [
                          _scaledPoints[2].dx,
                          _scaledPoints[3].dx,
                        ].reduce(math.min);
                        double minY = [
                          _scaledPoints[0].dy,
                          _scaledPoints[2].dy,
                        ].reduce(math.max);
                        if (newX > maxX) {
                          newX = maxX;
                        }
                        if (newY < minY) {
                          newY = minY;
                        }
                        break;
                      case 2: // top right
                        double minX = [
                          _scaledPoints[0].dx,
                          _scaledPoints[1].dx,
                        ].reduce(math.max);
                        double maxY = [
                          _scaledPoints[1].dy,
                          _scaledPoints[3].dy,
                        ].reduce(math.min);
                        if (newX < minX) {
                          newX = minX;
                        }
                        if (newY > maxY) {
                          newY = maxY;
                        }
                        break;
                      case 3: // bottom right
                        double minX = [
                          _scaledPoints[0].dx,
                          _scaledPoints[1].dx,
                        ].reduce(math.max);
                        double minY = [
                          _scaledPoints[0].dy,
                          _scaledPoints[2].dy,
                        ].reduce(math.max);
                        if (newX < minX) {
                          newX = minX;
                        }
                        if (newY < minY) {
                          newY = minY;
                        }
                        break;
                      default:
                    }

                    setState(() {
                      _scaledPoints[index] = Offset(newX, newY);
                    });
                    _scaleImage();
                    // Add current position to history
                    _positionHistory.add(
                      PositionTimestamp(
                        position: _scaledPoints[index],
                        timestamp: now,
                      ),
                    );
                    // Remove oldest position if older than _historyDurationMs
                    if (_positionHistory.isNotEmpty &&
                        now
                                .difference(_positionHistory.first.timestamp)
                                .inMilliseconds >
                            _historyDurationMs) {
                      _positionHistory.removeAt(0);
                    }
                  },
                  onPanEnd: (details) => panOver(index),
                  onPanCancel: () => panOver(index),
                  // Circle
                  child: Container(
                    width: _circleSize / counterScale,
                    height: _circleSize / counterScale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withAlpha(50),
                      border: isCurrent
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primaryFixed,
                              width: 4 / counterScale,
                              strokeAlign: BorderSide.strokeAlignOutside,
                            )
                          : Border.all(
                              color: Theme.of(context).colorScheme.primaryFixed,
                              width: 2 / counterScale,
                              strokeAlign: BorderSide.strokeAlignOutside,
                            ),
                    ),
                  ),
                ),
              );
            }),
            // Sharp corners inside circle
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: _CornerLinePainter(
                  points: _scaledPoints,
                  color: Colors.white,
                  strokeWidth: 1.0 / counterScale,
                  offset: (_circleSize + 2) / counterScale / 2,
                  normalizedOffset: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleEdgeDrag({
    required int indexA,
    required int indexB,
    required int neighborA,
    required int neighborB,
    required DragUpdateDetails details,
  }) {
    final Offset a = _scaledPoints[indexA];
    final Offset b = _scaledPoints[indexB];
    final Offset na = _scaledPoints[neighborA];
    final Offset nb = _scaledPoints[neighborB];

    final double dragAmount =
        -details.delta.dy; // fixed vertical axis + flipped

    final Offset dirA = a - na;
    final Offset dirB = b - nb;
    if (dirA.distance == 0 || dirB.distance == 0) return;

    final Offset normA = dirA / dirA.distance;
    final Offset normB = dirB / dirB.distance;

    final Offset moveA = normA * dragAmount;
    final Offset moveB = normB * dragAmount;

    Offset newA = a + moveA;
    Offset newB = b + moveB;

    newA = Offset(
      newA.dx.clamp(0.0, _screenWidth),
      newA.dy.clamp(0.0, _displayHeigth),
    );
    newB = Offset(
      newB.dx.clamp(0.0, _screenWidth),
      newB.dy.clamp(0.0, _displayHeigth),
    );

    setState(() {
      _scaledPoints[indexA] = newA;
      _scaledPoints[indexB] = newB;
    });

    _scaleImage();
  }

  void panOver(int index) {
    if (!_panning) return;
    // Remove positions older than _historyDurationMs
    DateTime now = DateTime.now();
    while (_positionHistory.isNotEmpty &&
        now.difference(_positionHistory.first.timestamp).inMilliseconds >
            _historyDurationMs) {
      _positionHistory.removeAt(0);
    }
    // Use oldest position in history
    if (_positionHistory.isNotEmpty) {
      if ((_positionHistory.first.position - _scaledPoints[index]).distance <
          50) {
        setState(() {
          _scaledPoints[index] = _positionHistory.first.position;
        });
      }
    }
    _positionHistory.clear();
    _panning = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 600));
      _panningDelayed = false;
    });
    return;
  }
}

class CircularCropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;

  CircularCropPainter({required this.image, required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    // circular clipping path
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clipPath);

    canvas.drawImageRect(
      image,
      cropRect,
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is CircularCropPainter) {
      return image != oldDelegate.image || cropRect != oldDelegate.cropRect;
    }
    return true;
  }
}

class _ZoomLinePainter extends CustomPainter {
  final List<Offset> cornerPoints;
  final Color color;
  final double strokeWidth;
  final Color colorBg;
  final double strokeWidthBg;
  final int currentCorner;
  final double zoomSize;

  _ZoomLinePainter({
    required this.cornerPoints,
    required this.color,
    required this.strokeWidth,
    required this.colorBg,
    required this.strokeWidthBg,
    required this.currentCorner,
    required this.zoomSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cornerPoints.length < 4) return;
    final double radius = zoomSize / 2;

    final paintBg = Paint()
      ..color = colorBg
      ..strokeWidth = strokeWidthBg
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var order = [0, 2, 3, 1];
    List<Offset> orderedPoints = order.map((i) => cornerPoints[i]).toList();

    int currentIndex = order.indexOf(currentCorner);
    int nextIndex = (currentIndex + 1) % orderedPoints.length;
    int prevIndex = (currentIndex - 1) % orderedPoints.length;

    Offset currentPoint = orderedPoints[currentIndex];
    Offset nextPoint = orderedPoints[nextIndex];
    Offset prevPoint = orderedPoints[prevIndex];

    Offset center = Offset(radius, radius);

    // Calculate the vectors from currentPoint to its neighbors
    Offset vectorToNext = nextPoint - currentPoint;
    Offset vectorToPrev = prevPoint - currentPoint;

    // Normalize these vectors to get direction only
    Offset directionToNext = vectorToNext / vectorToNext.distance;
    Offset directionToPrev = vectorToPrev / vectorToPrev.distance;

    // Draw lines from center to the edge of the circle in both directions
    final pathBg = Path();
    pathBg.moveTo(
      (center + directionToPrev * radius).dx,
      (center + directionToPrev * radius).dy,
    );
    pathBg.lineTo(center.dx, center.dy);
    pathBg.lineTo(
      (center + directionToNext * radius).dx,
      (center + directionToNext * radius).dy,
    );

    canvas.drawPath(pathBg, paintBg);
    canvas.drawLine(center, center + directionToNext * radius, paint);
    canvas.drawLine(center, center + directionToPrev * radius, paint);
  }

  @override
  bool shouldRepaint(covariant _ZoomLinePainter oldDelegate) =>
      oldDelegate.cornerPoints != cornerPoints ||
      oldDelegate.currentCorner != currentCorner;
}

class PositionTimestamp {
  final Offset position;
  final DateTime timestamp;

  PositionTimestamp({required this.position, required this.timestamp});
}

List<String> versionNames = [
  tr("versions.photo"),
  tr("versions.warped"),
  tr("versions.contrast"),
  tr("versions.processed1"),
  tr("versions.processed2"),
  tr("versions.processed3"),
];

Future<bool> _changeDefaultThumbnailVersionPopup(BuildContext context) async {
  int selectedIndex = g.defaultIndex;
  bool allowed = true;
  bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hide_image, size: 30),
                SizedBox(width: 12),
                Flexible(child: Text(tr("popup.defaultThumbnail.title"))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr("popup.defaultThumbnail.text")),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(
                    versionNames.length - 1,
                    (index) => RadioListTile<int>(
                      title: Row(
                        children: [
                          Text(versionNames[index + 1]),
                          !g.proUnlocked &&
                                  g.proFilterIndexes.contains(index + 1)
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.lock),
                                )
                              : SizedBox(),
                        ],
                      ),
                      value: index + 1,
                      groupValue: selectedIndex,
                      onChanged: (int? value) {
                        if (value != null) {
                          if (!g.proUnlocked &&
                              g.proFilterIndexes.contains(index + 1)) {
                            allowed = false;
                          } else {
                            allowed = true;
                          }
                          setStateDialog(() {
                            selectedIndex = value;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false), // Cancel
                child: Text(tr("popup.cancel")),
              ),
              allowed
                  ? ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                      },
                      child: Text(tr("popup.ok")),
                    )
                  : ElevatedButton.icon(
                      icon: Icon(Icons.lock),
                      onPressed: () async {
                        await proPopup(context);
                        setStateDialog(() {});
                      },
                      label: Text(tr("popup.unlock")),
                    ),
            ],
          );
        },
      );
    },
  );

  if (confirmed == true && allowed) {
    _setDefaultThumbnail(selectedIndex);
    return true;
  }
  return false;
}

Future<bool> _setDefaultThumbnail(final int newDefaultThumnailIndex) async {
  final prefs = await SharedPreferences.getInstance();
  g.setDefaultIndex(newDefaultThumnailIndex);
  return await prefs.setString(
    "defaultThumnailVersion",
    versionNamesInternal[g.defaultIndex],
  );
}

Future<void> _changingThumbnailsSnackbar(
  BuildContext context,
  List<Future> saveThumbnailFutures,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final snackBar = SnackBar(
    content: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(tr("loading.changingThumbnails")),
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ],
    ),
    duration: const Duration(days: 1),
  );
  messenger.showSnackBar(snackBar);
  await Future.wait(saveThumbnailFutures);
  globalNotifier.triggerEvent(NotifierEvent.loadPagesThumbnails);
  messenger.hideCurrentSnackBar();
}

Future<bool> _pagesPopup(
  BuildContext callContext,
  List<int> pageIndexes,
  PopUpType type,
  int docIndex, {
  int? versionIndex,
}) async {
  bool confirmAction = false;
  final bool isDocument = pageIndexes.isEmpty;
  late List<String> thumbnailPaths;
  late int pagesCount;
  late bool importedPdfMode;
  // specific version
  if (versionIndex != null && pageIndexes.length == 1) {
    importedPdfMode = await MetadataHelper.readPageImportedPdf(
      docIndex,
      pageIndexes.first,
    );
    if (type == PopUpType.delete && !importedPdfMode) {
      thumbnailPaths = (await g.filesHelper.getImagePathsForPage(
        docIndex,
        pageIndexes.first,
      )).$1;
    } else {
      thumbnailPaths = [
        await g.filesHelper.getVersionPath(
          docIndex,
          pageIndexes.first,
          versionIndex,
        ),
      ];
    }
    pagesCount = 1;
  }
  // single page / multiple pages / document
  else {
    var thumbs = await g.filesHelper.getPagesThumbnails(
      docIndex,
      pageIndexes: pageIndexes,
      fullSized: false,
    );
    thumbnailPaths = thumbs.$1;
    pagesCount = thumbs.$2;
  }
  final bool isSinglePage = pagesCount == 1; // Locked?
  bool docUnlocked = await g.metadataHelper.readDocUnlocked(docIndex);
  bool pageUnlocked = false;
  if (pageIndexes.isNotEmpty) {
    pageUnlocked = await g.metadataHelper.readPageUnlocked(
      docIndex,
      pageIndexes.first,
    );
  }
  // FileSizes and DPI
  List<int> imagesFilesizes = await g.filesHelper.getImagesFilesizes(
    docIndex,
    pageIndexes: pageIndexes,
    versionIndex: versionIndex,
  );
  List<int> pagesDpis = (await g.filesHelper.getPdfPageDpis(
    docIndex,
    pageIndexes: pageIndexes,
    versionIndex: versionIndex,
  )).$1;
  int? selectedDpi;
  // IsLoading
  List<bool> loadingImages = await loadLoadingImages(
    docIndex,
    pageIndexes,
    thumbnailPaths,
  );
  bool allPagesLoaded = loadingImages.every((element) => !element);
  // Aspect Ratios
  List<double> imageRatios = await loadImageRatios(
    docIndex,
    pageIndexes,
    pagesCount,
  );

  await showDialog(
    // ignore: use_build_context_synchronously
    context: callContext,
    builder: (BuildContext context) {
      return StreamBuilder<NotifierEvent>(
        stream: globalNotifier.stream,
        builder: (context, snapshot) {
          final event = snapshot.data;
          if (event == NotifierEvent.loadPagesThumbnails) {
            if (versionIndex != null && pageIndexes.length == 1) {
              Future.microtask(() async {
                thumbnailPaths = [
                  await g.filesHelper.getVersionPath(
                    docIndex,
                    pageIndexes.first,
                    versionIndex,
                  ),
                ];
              });
            } else {
              Future.microtask(() async {
                var thumbs = await g.filesHelper.getPagesThumbnails(
                  docIndex,
                  pageIndexes: pageIndexes,
                  fullSized: true,
                  supressWarnings: true,
                );
                thumbnailPaths = thumbs.$1;
              });
            }
            Future.microtask(() async {
              imageRatios = await loadImageRatios(
                docIndex,
                pageIndexes,
                pagesCount,
              );
            });
            Future.microtask(() async {
              loadingImages = await loadLoadingImages(
                docIndex,
                pageIndexes,
                thumbnailPaths,
              );
              allPagesLoaded = loadingImages.every((element) => !element);
            });
            Future.microtask(() async {
              imagesFilesizes = await g.filesHelper.getImagesFilesizes(
                docIndex,
                pageIndexes: pageIndexes,
                versionIndex: versionIndex,
              );
            });
            Future.microtask(() async {
              pagesDpis = (await g.filesHelper.getPdfPageDpis(
                docIndex,
                pageIndexes: pageIndexes,
                versionIndex: versionIndex,
              )).$1;
            });
          }
          String title;
          if (isDocument) {
            switch (type) {
              case PopUpType.share:
                title = tr(
                  "popup.pagesPopup.document.share.title",
                  namedArgs: {"docIndex": "${docIndex + 1}"},
                );
                break;
              case PopUpType.save:
                title = tr(
                  "popup.pagesPopup.document.save.title",
                  namedArgs: {"docIndex": "${docIndex + 1}"},
                );
                break;
              case PopUpType.delete:
                title = tr(
                  "popup.pagesPopup.document.delete.title",
                  namedArgs: {"docIndex": "${docIndex + 1}"},
                );
                break;
            }
          } else if (!isSinglePage) {
            switch (type) {
              case PopUpType.share:
                title = tr(
                  "popup.pagesPopup.pages.share.title",
                  namedArgs: {"pagesCount": "$pagesCount"},
                );
                break;
              case PopUpType.save:
                title = tr(
                  "popup.pagesPopup.pages.save.title",
                  namedArgs: {"pagesCount": "$pagesCount"},
                );
                break;
              case PopUpType.delete:
                title = tr(
                  "popup.pagesPopup.pages.delete.title",
                  namedArgs: {"pagesCount": "$pagesCount"},
                );
                break;
            }
          } else {
            switch (type) {
              case PopUpType.share:
                title = tr(
                  "popup.pagesPopup.page.share.title",
                  namedArgs: {"pageIndex": "${pageIndexes.first + 1}"},
                );
                break;
              case PopUpType.save:
                title = tr(
                  "popup.pagesPopup.page.save.title",
                  namedArgs: {"pageIndex": "${pageIndexes.first + 1}"},
                );
                break;
              case PopUpType.delete:
                title = tr(
                  "popup.pagesPopup.page.delete.title",
                  namedArgs: {"pageIndex": "${pageIndexes.first + 1}"},
                );
                break;
            }
            if (versionIndex != null &&
                type != PopUpType.delete &&
                !importedPdfMode) {
              title += ", \n${versionNames[versionIndex]}";
            }
          }
          String? deleteText;
          if (type == PopUpType.delete) {
            if (isDocument) {
              deleteText = tr("popup.pagesPopup.document.delete.text");
            } else if (!isSinglePage) {
              deleteText = tr(
                "popup.pagesPopup.pages.delete.text",
                namedArgs: {"pagesCount": "$pagesCount"},
              );
            } else {
              deleteText = tr("popup.pagesPopup.page.delete.text");
            }
          }
          String? buttonTextImage;
          String? buttonTextPdf;
          if (!isSinglePage) {
            switch (type) {
              case PopUpType.share:
                buttonTextImage = tr("popup.pagesPopup.pages.share.images");
                buttonTextPdf = tr("popup.pagesPopup.pages.share.pdf");
                break;
              case PopUpType.save:
                buttonTextImage = tr("popup.pagesPopup.pages.save.images");
                buttonTextPdf = tr("popup.pagesPopup.pages.save.pdf");
                break;
              default:
            }
          } else {
            switch (type) {
              case PopUpType.share:
                buttonTextImage = tr("popup.pagesPopup.page.share.image");
                buttonTextPdf = tr("popup.pagesPopup.page.share.pdf");
                break;
              case PopUpType.save:
                buttonTextImage = tr("popup.pagesPopup.page.save.image");
                buttonTextPdf = tr("popup.pagesPopup.page.save.pdf");
                break;
              default:
            }
          }

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              IconData icon;
              switch (type) {
                case PopUpType.share:
                  icon = Icons.share;
                  break;
                case PopUpType.save:
                  icon = Icons.save;
                  break;
                case PopUpType.delete:
                  icon = Icons.delete;
                  break;
              }
              bool lockDpi =
                  !g.proUnlocked &&
                  !docUnlocked &&
                  !(isSinglePage && pageUnlocked);
              bool lockAll =
                  (isSinglePage &&
                      !(pageUnlocked || g.proUnlocked) &&
                      g.proFilterIndexes.contains(versionIndex)) ||
                  (lockDpi && selectedDpi != null);
              bool lockPdf =
                  lockAll || (!isSinglePage && !(docUnlocked || g.proUnlocked));

              return AlertDialog(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 30,
                    ),
                    SizedBox(width: 12.0),
                    Flexible(child: Text(title)),
                  ],
                ),
                actions: [
                  ImagesScrollPreview(
                    imagePaths: thumbnailPaths,
                    loadingImages: loadingImages,
                    imageRatios: imageRatios,
                  ),
                  SizedBox(height: 12.0),
                  !allPagesLoaded
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 36),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(),
                              ),
                              SizedBox(width: 8.0),
                              SizedBox(
                                width: 190,
                                child: Text(tr("loading.processingImages")),
                              ),
                            ],
                          ),
                        )
                      : SizedBox(),
                  type == PopUpType.delete
                      ? Align(
                          alignment: Alignment.center,
                          child: Text(deleteText!),
                        )
                      : SizedBox(),
                  if (type != PopUpType.delete)
                    DpiDropdown(
                      pagesDpis: pagesDpis,
                      imagesFilesizes: imagesFilesizes,
                      onChanged: (dpi) {
                        selectedDpi = dpi;
                        setStateDialog(() {});
                      },
                      lockDpi: lockDpi,
                    ),
                  SizedBox(height: 24.0),

                  type == PopUpType.delete
                      ? SizedBox()
                      : Container(
                          decoration: lockAll
                              ? BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [smallBoxShadow(context)],
                                )
                              : null,
                          child: Column(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Image
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: lockAll ? 4 : 0,
                                    ),
                                    // Image Export
                                    child: ElevatedButton.icon(
                                      onPressed: allPagesLoaded && !lockAll
                                          ? () async {
                                              confirmAction = true;
                                              Navigator.pop(context);
                                              Future? afterExport;
                                              switch (type) {
                                                case PopUpType.share:
                                                  afterExport = g.filesHelper
                                                      .shareImages(
                                                        docIndex,
                                                        pageIndexes:
                                                            pageIndexes,
                                                        versionIndex:
                                                            versionIndex,
                                                        maxDpi: selectedDpi,
                                                      );
                                                  break;
                                                case PopUpType.save:
                                                  afterExport = g.filesHelper
                                                      .saveImagesToGallery(
                                                        docIndex,
                                                        pageIndexes:
                                                            pageIndexes,
                                                        versionIndex:
                                                            versionIndex,
                                                        maxDpi: selectedDpi,
                                                      );
                                                  break;
                                                default:
                                              }
                                              if (feedbackHelper
                                                  .canShowExportPopup()) {
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback((
                                                      _,
                                                    ) async {
                                                      await afterExport;
                                                      if (type ==
                                                          PopUpType.share) {
                                                        await Future.delayed(
                                                          Duration(seconds: 4),
                                                        );
                                                      }
                                                      feedbackHelper
                                                          .showRatingDialog(
                                                            // ignore: use_build_context_synchronously
                                                            callContext,
                                                          );
                                                    });
                                              }
                                            }
                                          : null,

                                      icon: Icon(Icons.image),
                                      label: Text("$buttonTextImage"),
                                    ),
                                  ),

                                  // PDF
                                  SizedBox(height: lockPdf && !lockAll ? 4 : 0),
                                  Container(
                                    decoration: lockPdf && !lockAll
                                        ? BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            boxShadow: [
                                              smallBoxShadow(context),
                                            ],
                                          )
                                        : null,
                                    child: Column(
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: lockPdf ? 4 : 0,
                                          ),
                                          // PDF Export
                                          child: ElevatedButton.icon(
                                            onPressed:
                                                allPagesLoaded && !lockPdf
                                                ? () async {
                                                    confirmAction = true;
                                                    Navigator.pop(context);
                                                    Future? afterExport;
                                                    switch (type) {
                                                      case PopUpType.share:
                                                        afterExport = g
                                                            .filesHelper
                                                            .sharePdf(
                                                              context,
                                                              docIndex,
                                                              pageIndexes:
                                                                  pageIndexes,
                                                              versionIndex:
                                                                  versionIndex,
                                                              maxDpi:
                                                                  selectedDpi,
                                                            );
                                                        break;
                                                      case PopUpType.save:
                                                        afterExport = g
                                                            .filesHelper
                                                            .savePdfToDirectoy(
                                                              docIndex,
                                                              context,
                                                              pageIndexes:
                                                                  pageIndexes,
                                                              versionIndex:
                                                                  versionIndex,
                                                              maxDpi:
                                                                  selectedDpi,
                                                            );
                                                        break;
                                                      default:
                                                    }
                                                    if (feedbackHelper
                                                        .canShowExportPopup()) {
                                                      WidgetsBinding.instance
                                                          .addPostFrameCallback((
                                                            _,
                                                          ) async {
                                                            await afterExport;
                                                            if (type ==
                                                                PopUpType
                                                                    .share) {
                                                              await Future.delayed(
                                                                Duration(
                                                                  seconds: 4,
                                                                ),
                                                              );
                                                            }
                                                            feedbackHelper
                                                                .showRatingDialog(
                                                                  // ignore: use_build_context_synchronously
                                                                  callContext,
                                                                );
                                                          });
                                                    }
                                                  }
                                                : null,

                                            icon: Icon(Icons.picture_as_pdf),
                                            label: Text("$buttonTextPdf"),
                                          ),
                                        ),
                                        lockPdf && !lockAll
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      10,
                                                      0,
                                                      10,
                                                      6,
                                                    ),
                                                child: Column(
                                                  children: [
                                                    ElevatedButton.icon(
                                                      onPressed: () {
                                                        proPopup(context);
                                                      },
                                                      icon: Icon(Icons.lock),
                                                      label: Text(
                                                        tr("popup.unlock"),
                                                      ),
                                                    ),
                                                    ElevatedButton.icon(
                                                      onPressed: () async {
                                                        docUnlocked =
                                                            await _unlockDocumentWithAd(
                                                              context,
                                                            );
                                                        if (docUnlocked) {
                                                          setStateDialog(() {});
                                                          await g.metadataHelper
                                                              .writeDocUnlocked(
                                                                docIndex,
                                                                docUnlocked,
                                                              );
                                                        }
                                                      },
                                                      icon: Icon(
                                                        Icons.play_arrow,
                                                      ),
                                                      label: Text(
                                                        tr("popup.watchAd"),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : SizedBox(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Unlock PRO
                              lockAll
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        0,
                                        10,
                                        6,
                                      ),
                                      child: Column(
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              proPopup(context);
                                            },
                                            icon: Icon(Icons.lock),
                                            label: Text(tr("popup.unlock")),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () async {
                                              pageUnlocked =
                                                  await _unlockPageWithAd(
                                                    context,
                                                  );
                                              if (pageUnlocked) {
                                                setStateDialog(() {});
                                                await g.metadataHelper
                                                    .writePageUnlocked(
                                                      docIndex,
                                                      pageIndexes.first,
                                                      true,
                                                    );
                                                globalNotifier.triggerEvent(
                                                  NotifierEvent.setState,
                                                );
                                                setStateDialog(() {});
                                              }
                                            },
                                            icon: Icon(Icons.play_arrow),
                                            label: Text(tr("popup.watchAd")),
                                          ),
                                        ],
                                      ),
                                    )
                                  : SizedBox(),
                            ],
                          ),
                        ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cancel Button
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr("popup.cancel")),
                      ),
                      type == PopUpType.delete
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ElevatedButton(
                                onPressed: () {
                                  confirmAction = true;
                                  g.filesHelper.deleteImages(
                                    context,
                                    docIndex,
                                    pageIndexes: pageIndexes,
                                  );
                                  Navigator.pop(context);
                                },
                                child: Text(
                                  tr("popup.pagesPopup.deleteButton"),
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            )
                          : SizedBox(),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
  return confirmAction;
}

Future<List<double>> loadImageRatios(
  int docIndex,
  List<int> pageIndexes,
  int pagesCount,
) async {
  List<double> imageRatios = [];
  if (pageIndexes.isEmpty) {
    pageIndexes = List.generate(pagesCount, (index) => index);
  }
  for (var pageIndex in pageIndexes) {
    imageRatios.add(
      await MetadataHelper.readPageRatioValue(
            docIndex,
            pageIndex,
            supressWarnings: true,
          ) ??
          math.sqrt2,
    );
  }
  return imageRatios;
}

Future<List<bool>> loadLoadingImages(
  int docIndex,
  List<int> pageIndexes,
  List<String> thumbnailPaths,
) async {
  if (pageIndexes.isEmpty) {
    pageIndexes = List.generate(thumbnailPaths.length, (index) => index);
  }
  List<bool> thumbnailsLoading = [];
  for (var (i, pageIndex) in pageIndexes.indexed) {
    bool thumbnailLoading = false;
    if (thumbnailPaths[i].isEmpty) {
      thumbnailLoading = true;
    } else {
      final oldNames = await MetadataHelper.readOldPageFileNames(
        docIndex,
        pageIndex,
      );
      if (oldNames != null) {
        for (var oldName in oldNames) {
          if (oldName.isNotEmpty && thumbnailPaths[i].contains(oldName)) {
            thumbnailLoading = true;
            break;
          }
        }
      } else {
        thumbnailLoading = true;
      }
    }
    thumbnailsLoading.add(thumbnailLoading);
  }
  return thumbnailsLoading;
}

class DpiDropdown extends StatefulWidget {
  final List<int> pagesDpis;
  final List<int> imagesFilesizes;
  final void Function(int? selectedDpi) onChanged;
  final bool lockDpi;

  const DpiDropdown({
    super.key,
    required this.pagesDpis,
    required this.imagesFilesizes,
    required this.onChanged,
    required this.lockDpi,
  });

  @override
  State<DpiDropdown> createState() => _DpiDropdownState();
}

class _DpiDropdownState extends State<DpiDropdown> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<int> commonDpis = [600, 400, 300, 150, 75];
    final List<int> lowerDpis = commonDpis
        .where((dpi) => widget.pagesDpis.any((pageDpi) => pageDpi >= dpi))
        .toList();

    final double height = 30;

    return Container(
      constraints: BoxConstraints(minHeight: height, maxHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          isDense: true,
          isExpanded: false,
          alignment: Alignment.centerRight,
          //icon: const SizedBox.shrink(), // to hide drop-down-arrow
          value: selectedIndex,
          items: List.generate(lowerDpis.length + 1, (i) {
            String dpiString;
            String fileSizeString;
            String menuEntryString;

            if (i == 0) {
              dpiString = widget.pagesDpis.isEmpty
                  ? "--- DPI"
                  : widget.pagesDpis.length == 1
                  ? "${widget.pagesDpis.first} DPI"
                  : "Ø ${widget.pagesDpis.average.toInt()} DPI";

              fileSizeString = widget.imagesFilesizes.isEmpty
                  ? "--- MB"
                  : g.filesHelper.formatBytes(widget.imagesFilesizes.sum);

              menuEntryString = tr(
                "popup.pagesPopup.dpi.full",
                namedArgs: {
                  "dpiString": dpiString,
                  "fileSizeString": fileSizeString,
                },
              );
            } else {
              final int lowerDpi = lowerDpis[i - 1];
              double estimatedBytes = 0;

              for (int i = 0; i < widget.imagesFilesizes.length; i++) {
                final int originalSize = widget.imagesFilesizes[i];
                final int originalDpi = widget.pagesDpis[i];

                if (originalDpi > lowerDpi) {
                  double ratio =
                      (lowerDpi / originalDpi) +
                      0.075; // 0.075 is a correction from testing file sizes
                  estimatedBytes += originalSize * ratio * ratio;
                } else {
                  estimatedBytes += originalSize;
                }
              }

              dpiString = "$lowerDpi DPI";
              fileSizeString =
                  "~${g.filesHelper.formatBytes(estimatedBytes.toInt())}";

              menuEntryString = tr(
                "popup.pagesPopup.dpi.limit",
                namedArgs: {
                  "dpiString": dpiString,
                  "fileSizeString": fileSizeString,
                },
              );
            }

            return DropdownMenuItem(
              alignment: Alignment.centerRight,
              value: i,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    menuEntryString,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (i != 0 && widget.lockDpi)
                    Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.lock),
                    ),
                ],
              ),
            );
          }),
          onChanged: widget.pagesDpis.isEmpty
              ? null
              : (int? newIndex) {
                  setState(() {
                    selectedIndex = newIndex ?? 0;
                  });

                  // Return selectedDPI to where Widget is used
                  final selectedDpi = newIndex == 0
                      ? null
                      : lowerDpis[newIndex! - 1];
                  widget.onChanged(selectedDpi);
                },
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isFlashOn = false;
  final List<XFile> _capturedImages = [];
  double _cameraAspectRatio = 3 / 4;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

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
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _permissionStatus = await Permission.camera.request();

    if (_permissionStatus.isGranted) {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();

      final size = _controller!.value.previewSize!;
      _cameraAspectRatio = size.height / size.width;

      if (mounted) setState(() {});
    } else if (_permissionStatus.isPermanentlyDenied) {
      await showSettingsRedirectDialog();
    }
  }

  Future<void> showSettingsRedirectDialog() async {
    final bool? settingsOpened = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning,
              color: Theme.of(context).colorScheme.onSurface,
              size: 30,
            ),
            SizedBox(width: 12),
            Flexible(child: Text(tr("camera.permissionsPopup.title"))),
          ],
        ),
        content: Text(tr("camera.permissionsPopup.text")),
        actions: [
          TextButton(
            child: Text(tr("popup.cancel")),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context, false);
              }
            },
          ),
          ElevatedButton(
            child: Text(tr("camera.permissionsPopup.openSettings")),
            onPressed: () {
              openAppSettings();
              if (Navigator.canPop(context)) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
    if (settingsOpened != true &&
        mounted &&
        context.mounted &&
        Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _controller?.setFlashMode(FlashMode.off);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    _isFlashOn = !_isFlashOn;
    await _controller?.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
    if (mounted && context.mounted) setState(() {});
  }

  Future<void> _setFlash(bool setFlash) async {
    _isFlashOn = setFlash;
    await _controller?.setFlashMode(setFlash ? FlashMode.torch : FlashMode.off);
    if (mounted && context.mounted) setState(() {});
  }

  bool _cameraFlash = false;
  Future<void> _takePhoto() async {
    if (_permissionStatus != PermissionStatus.granted) {
      if (mounted) _initializeCamera();
    }

    if (_controller == null || _controller!.value.isTakingPicture) {
      return;
    }
    try {
      setState(() {
        _cameraFlash = true;
      });
      final image = await _controller!.takePicture();
      _capturedImages.add(image);
      setState(() {
        _cameraFlash = false;
      });
    } catch (e) {
      dev.log("Warning taking photo: $e");
    }
  }

  void _openPhotosGrid(BuildContext context) {
    _setFlash(false);
    showModalBottomSheet(
      backgroundColor: ColorScheme.dark().surface,
      showDragHandle: true,
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (_capturedImages.isEmpty) Navigator.pop(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: GridView.builder(
              cacheExtent: 1000,
              addRepaintBoundaries: false,
              itemCount: _capturedImages.length + 3,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (context, index) {
                if (index >= _capturedImages.length) {
                  return SizedBox();
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Image.file(
                        File(_capturedImages[index].path),
                        fit: BoxFit.cover,
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        splashColor: Colors.white30,
                        highlightColor: Colors.white10,
                        onTap: () {
                          _openFullscreenViewer(index, setStateDialog);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<bool> _leaveConfirmationDialog() async {
    bool? confirmLeave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.onSurface,
                size: 30,
              ),
              SizedBox(width: 12),
              Flexible(child: Text(tr("camera.discardPopup.title"))),
            ],
          ),
          content: Text(tr("camera.discardPopup.text")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("popup.cancel")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                tr("camera.discardPopup.discard"),
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
    return confirmLeave == true;
  }

  bool _isPressingCaptureButton = false;
  @override
  Widget build(BuildContext context) {
    bool allowPop = _capturedImages.isEmpty;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!allowPop) {
          HapticFeedback.heavyImpact();
          if (await _leaveConfirmationDialog() &&
              mounted &&
              context.mounted &&
              Navigator.canPop(context)) {
            allowPop = true;
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            tooltip: tr("camera.close"),
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            CustomIconButton(
              tooltip: tr("camera.confirm"),
              isDisabled: _capturedImages.isEmpty,
              onTap: () {
                allowPop = true;
                if (Navigator.canPop(context)) {
                  Navigator.pop(context, _capturedImages);
                }
              },
              icon: Icons.check,
            ),
            SizedBox(width: 12),
          ],
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Camera Preview
            AspectRatio(
              aspectRatio: _cameraAspectRatio,
              child: Stack(
                children: [
                  _controller != null
                      ? CameraPreview(_controller!)
                      : Positioned.fill(
                          child: Container(
                            color: ColorScheme.dark().surface,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                  Stack(
                    children: [
                      _cameraFlash
                          ? Positioned.fill(
                              child: Container(color: Colors.black38),
                            )
                          : SizedBox(),
                      Center(child: CustomPaint(painter: CrosshairPainter())),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: IconButton(
                    tooltip: _isFlashOn
                        ? tr("camera.flash.disable")
                        : tr("camera.flash.enable"),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _toggleFlash();
                    },
                    icon: Icon(
                      _isFlashOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                    ),
                  ),
                ),

                GestureDetector(
                  onTapDown: (details) {
                    if (_cameraFlash) return;
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _isPressingCaptureButton = true;
                    });
                  },
                  onTapUp: (details) {
                    if (!_isPressingCaptureButton) return;
                    HapticFeedback.lightImpact();
                    _takePhoto();
                    setState(() {
                      _isPressingCaptureButton = false;
                    });
                  },
                  onTapCancel: () {
                    setState(() {
                      _isPressingCaptureButton = false;
                    });
                  },

                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isPressingCaptureButton || _cameraFlash
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isPressingCaptureButton || _cameraFlash
                              ? Colors.transparent
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                Tooltip(
                  message: tr("camera.viewer.preview"),
                  child: ThumbnailWithBadge(
                    image: _capturedImages.isNotEmpty
                        ? File(_capturedImages.first.path)
                        : null,
                    count: _capturedImages.length,
                    onTap: _capturedImages.isEmpty
                        ? null
                        : () => _openPhotosGrid(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  _openFullscreenViewer(
    int initialIndex,
    Function(void Function()) setStateGallery,
  ) async {
    PageController controller = PageController(initialPage: initialIndex);

    await showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.black,
                leading: IconButton(
                  tooltip: tr("camera.viewer.back"),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    tooltip: tr("camera.viewer.delete"),
                    icon: Icon(Icons.delete, color: Colors.white),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      int index = controller.page!.round();
                      setState(() {
                        _capturedImages.removeAt(index);
                      });
                      setStateGallery(() {});
                      if (_capturedImages.isEmpty) {
                        Navigator.pop(context);
                      } else {
                        setStateDialog(() {});
                      }
                    },
                  ),
                ],
              ),
              body: PhotoViewGallery.builder(
                pageController: controller,
                scrollPhysics: const PageScrollPhysics(),
                backgroundDecoration: BoxDecoration(color: Colors.transparent),
                itemCount: _capturedImages.length,
                builder: (context, index) {
                  // Processed Images
                  return PhotoViewGalleryPageOptions(
                    imageProvider: FileImage(File(_capturedImages[index].path)),
                    filterQuality: FilterQuality.high,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: 1.0,
                  );
                },
              ),
              //floatingActionButton: Padding(
              //  padding: const EdgeInsets.fromLTRB(0, 0, 20, 100),
              //  child: Column(
              //    mainAxisAlignment: MainAxisAlignment.end,
              //    children: <Widget>[
              //      FloatingActionButton(
              //        heroTag: "deletePhoto",
              //        tooltip: "Delete Photo",
              //        onPressed: () {
              //          HapticFeedback.lightImpact();
              //          int index = controller.page!.round();
              //          setState(() {
              //            _capturedImages.removeAt(index);
              //          });
              //          setStateGallery(() {});
              //          if (_capturedImages.isEmpty) {
              //            Navigator.pop(context);
              //          } else {
              //            setStateDialog(() {});
              //          }
              //        },
              //        child: const Icon(Icons.delete, color: Colors.white),
              //      ),
              //    ],
              //  ),
              //),
            );
          },
        );
      },
    );
  }
}

class CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double crossSize = 17.0;
    final double crossThickness = 1.5;
    final double bgThickness = 0.5;
    final double bgThickness2 = 2;
    final double bgThickness3 = 4;
    final double bgThickness4 = 8;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = crossThickness;
    final paintBg = Paint()
      ..color = Colors.black.withAlpha(70)
      ..strokeWidth = crossThickness + 2 * bgThickness;
    final paintBg2 = Paint()
      ..color = Colors.black.withAlpha(14)
      ..strokeWidth = crossThickness + 2 * bgThickness2;
    final paintBg3 = Paint()
      ..color = Colors.black.withAlpha(5)
      ..strokeWidth = crossThickness + 2 * bgThickness3;
    final paintBg4 = Paint()
      ..color = Colors.black.withAlpha(2)
      ..strokeWidth = crossThickness + 2 * bgThickness4;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness4 * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness4 * 0.75, centerY),
      paintBg4,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness4 * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness4 * 0.75),
      paintBg4,
    );
    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness3 * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness3 * 0.75, centerY),
      paintBg3,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness3 * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness3 * 0.75),
      paintBg3,
    );
    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness2 * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness2 * 0.75, centerY),
      paintBg2,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness2 * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness2 * 0.75),
      paintBg2,
    );
    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness * 0.75, centerY),
      paintBg,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness * 0.75),
      paintBg,
    );
    // Draw Cross
    canvas.drawLine(
      Offset(centerX - crossSize, centerY),
      Offset(centerX + crossSize, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize),
      Offset(centerX, centerY + crossSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class ThumbnailWithBadge extends StatelessWidget {
  final File? image;
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
                  ? DecorationImage(image: FileImage(image!), fit: BoxFit.cover)
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

class AdsHelper {
  late Future<void> _loadAdFuture;
  AdsHelper() {
    _loadAdFuture = _loadRewardAd();
  }
  RewardedAd? _ad;

  Future<void> _loadRewardAd() async {
    final completer = Completer<void>();
    RewardedAd.load(
      adUnitId: "ca-app-pub-6739996186409182/8967462940",
      request: AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _ad = ad;

          _ad?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _loadRewardAd(); // Reload after watching
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _loadRewardAd();
            },
          );
          completer.complete();
        },
        onAdFailedToLoad: (LoadAdError error) {
          dev.log("Warning: Failed to load reward ad: $error");
          Fluttertoast.showToast(msg: tr("toast.e_ad"));
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<bool> showRewardAd() async {
    final completer = Completer<bool>();
    await _loadAdFuture;
    if (_ad != null) {
      _ad!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          dev.log("User earned reward: ${reward.type}"); //${reward.amount}
          completer.complete(true);
        },
      );
    } else {
      dev.log("Warning: Ad not loaded yet.");
      Fluttertoast.showToast(msg: tr("toast.e_noAd"));
      completer.complete(false);
    }
    return completer.future;
  }
}
