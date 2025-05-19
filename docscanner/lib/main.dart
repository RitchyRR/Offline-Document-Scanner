// design:
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:docscanner/isolates_manager.dart' show IsolatesManager;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:shared_preferences/shared_preferences.dart';
// monetization:
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// validity:
import 'package:package_info_plus/package_info_plus.dart';
// function:
import 'dart:io';
import 'dart:async'; // Timer
import 'dart:developer' as dev;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
// camera:
import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:permission_handler/permission_handler.dart';
// local:
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
// my packages:
import 'package:docscanner/app_globals.dart';
import 'package:docscanner/files_helper.dart';
import 'package:docscanner/metadata_helper.dart';
import 'package:docscanner/image_prosessing_manager.dart';
import 'package:docscanner/feedback_helper.dart';

final AdsHelper adsHelper = AdsHelper();
final FeedbackHelper feedbackHelper = FeedbackHelper();
final ImageProcessingManager imageProcessingManager = ImageProcessingManager();

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalNotifier globalNotifier = GlobalNotifier();

class GlobalNotifier extends ValueNotifier<NotifierEvent> {
  GlobalNotifier() : super(NotifierEvent.loadPagesThumbnails);

  void triggerEvent(NotifierEvent event) {
    if (event == value) {
      notifyListeners(); // so that multiple triggers of the same type can work
    }
    value = event;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CameraPlatform.instance = AndroidCameraCameraX();
  MobileAds.instance.initialize();
  //// Play Test Ads
  //MobileAds.instance.updateRequestConfiguration(
  //  RequestConfiguration(testDeviceIds: ['09BF6CED0A634AD6921EF7E4280CFAFC']),
  //);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    //DeviceOrientation.portraitDown,
  ]);
  runApp(ChangeNotifierProvider.value(value: globalNotifier, child: MyApp()));
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
    return (
      lightScheme,
      darkScheme,
      //.copyWith(
      //surface: darkScheme.surfaceContainerLow,
      //surfaceContainerLow: darkScheme.surfaceContainerHigh, // cards + elevated buttons
      //surfaceContainer: darkScheme.surfaceContainerHighest,
      //     primary: darkScheme.primary,
      //     secondary: darkScheme.secondary,
      //shadow: Color.fromARGB(255, 0, 0, 0),
      //)
    );
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
    initStoreInfo();
  }

  Future<void> initAsync() async {
    Future.microtask(() {
      if (mounted) {
        g.filesHelper.calculateScreenWidth(context);
      } else {
        dev.log("Error, _MyAppState, initAsync(): not mounted");
      }
    });
    final sStorage = FlutterSecureStorage();
    final proUnlockedString = await sStorage.read(key: 'proUnlocked');
    setState(() {
      g.proUnlocked = proUnlockedString != null && proUnlockedString == 'true';
    });
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
          navigatorKey: navigatorKey, // to pop until homepage from anywhere
          navigatorObservers: [routeObserver],
          title: 'Offline Document Scanner',
          initialRoute: '/',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/':
                return MaterialPageRoute(builder: (_) => DocumentsHome());

              case '/pages':
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder:
                      (_) => Pages(
                        docIndex: args['docIndex'],
                        initialPageIndex: args['initialPageIndex'],
                      ),
                );

              case '/preview':
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder:
                      (_) => PagePreview(
                        docIndex: args['docIndex'],
                        pageIndex: args['pageIndex'],
                      ),
                );

              case '/camera':
                return MaterialPageRoute(
                  builder:
                      (context) => Theme(
                        data: Theme.of(context).copyWith(
                          brightness: Brightness.dark,
                        ), //for tooltips and splash effects
                        child: CameraScreen(),
                      ),
                );

              case '/warp':
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder:
                      (_) => Warp(
                        pagePreviewState: args['pagePreviewState'],
                        docIndex: args['docIndex'],
                        pageIndex: args['pageIndex'],
                        imagePath: args['imagePath'],
                        cornerPoints: args['cornerPoints'],
                        rotation: args['rotation'],
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
            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                systemNavigationBarColor: Colors.transparent,
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
              ),
            ),
            //cardTheme: CardTheme(color: lightTheme.surfaceContainerHigh),
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
            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                systemNavigationBarColor: Colors.transparent,
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
              ),
            ),
            cardTheme: CardTheme(color: darkTheme.surfaceContainerHigh),
            popupMenuTheme: PopupMenuThemeData(
              color: darkTheme.primaryContainer,
            ),
          ),
          themeMode: ThemeMode.system, // device controls theme
          home: const DocumentsHome(title: 'Documents'),
        );
      },
    );
  }
}

class DocumentsHome extends StatefulWidget {
  const DocumentsHome({super.key, this.title});

  final String? title;

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
    globalNotifier.addListener(_handleGlobalEvent);
    WidgetsBinding.instance.addObserver(this);
    initAsync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(Duration(milliseconds: 500));
        if (IsolatesManager().getIsolatesCount() == 0) {
          g.filesHelper.repairDirectoryStructure(deleteEmptyPages: false);
        }
      });
    }
  }

  late PackageInfo _packageInfo;
  Future<void> initAsync() async {
    _initReceiveSharingIntent();
    _packageInfo = await PackageInfo.fromPlatform();
    await _loadDocsDisplay(onInit: true);
    await loadAvailableAspectRatios();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      g.filesHelper.repairDirectoryStructure();
    });
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
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
  Future<void> _handleGlobalEvent() async {
    if (!mounted) return;
    switch (globalNotifier.value) {
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
      final newDate = "${now.year}-${now.month}-${now.day}";
      g.metadataHelper.writeDocDate(docIndex, newDate, supressWarnings: true);
      await Future.delayed(Duration(milliseconds: 50));
      imageProcessingManager.processPages(docIndex, 0, photoPaths, false);
    });

    return (docIndex, firstPageIndex);
  }

  Future<void> _openImagePicker(
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
    List<String> photoPaths;
    if (g.filesHelper.pickingImage) return;
    if (source == ImageSource.camera) {
      photoPaths = await _openCamera();
    } else {
      photoPaths = await g.filesHelper.pickImage(
        context,
        source,
        isMultiImage: isMultiImage,
      );
    }
    if (photoPaths.isEmpty) return;

    final newIndexes = await _processDocument(photoPaths);
    int docIndex = newIndexes.$1;
    int firstPageIndex = newIndexes.$2;
    // only open PagePreview for first page
    _openNewPagePreview(docIndex, firstPageIndex);
  }

  Future<void> _openNewPagePreview(int docIndex, int pageIndex) async {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamed(
        context,
        '/pages',
        arguments: {'docIndex': docIndex, 'initialPageIndex': pageIndex},
      );
    });
  }

  Future<List<String>> _openCamera() async {
    g.filesHelper.pickingImage = true;
    final result = await Navigator.pushNamed(context, '/camera');
    List<String> photoPaths = [];
    if (result is List<XFile>) {
      for (var xfile in result) {
        photoPaths.add(xfile.path);
      }
    }
    g.filesHelper.pickingImage = false;
    return photoPaths;
  }

  _initReceiveSharingIntent() {
    // App launched by Opening/Sharing image(s)/pdf
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      _handleSharedFiles(value);
    });
    // While app is already running
    ReceiveSharingIntent.instance.getMediaStream().listen((
      List<SharedMediaFile> value,
    ) {
      _handleSharedFiles(value);
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    final pdfs =
        files.where((f) => f.path.toLowerCase().endsWith(".pdf")).toList();
    final images = files.where((f) => f.type == SharedMediaType.image).toList();

    // PDFs
    if (pdfs.isNotEmpty) {
      for (final pdf in pdfs) {
        final docData = await g.filesHelper.pdfToDoc(pdf.path);
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
    _thumbnailRatios = List.generate(_docsCount, (_) => 1.0 / math.sqrt2);
    for (int docIndex = 0; docIndex < _docsCount; docIndex++) {
      _docDates[docIndex] =
          (await g.metadataHelper.readDocDate(docIndex)) ?? "";
      String? docName = await g.metadataHelper.readDocName(docIndex);
      if (docName != null) {
        _docNames[docIndex] = docName;
      } else {
        g.metadataHelper.writeDocName(docIndex, _docNames[docIndex]);
      }

      bool supressWarnings = onInit;
      if (thumbnailPaths[docIndex].isEmpty) supressWarnings = true;
      double ratioValue =
          await MetadataHelper.readPageRatioValue(
            docIndex,
            0,
            supressWarnings: supressWarnings,
          ) ??
          math.sqrt2;
      _thumbnailRatios[docIndex] = 1.0 / ratioValue;
    }

    // Refresh Display
    if (mounted) {
      setState(() {
        _docThumbnails = thumbnailPaths;
      });
    }
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
      Navigator.pushNamed(context, '/pages', arguments: {'docIndex': docIndex});
    });
  }

  void _openDocEditDialog(
    BuildContext context,
    int docIndex,
    int displayDocIndex,
  ) async {
    Future<void> future = imageProcessingManager.awaitAllIsolates();
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
            title: Text("Edit Document $displayDocIndex"),
            content: StatefulBuilder(
              builder: (context, setState) {
                future.whenComplete(() {
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
                        labelText: "Document Name",
                        hintText: "Document $displayDocIndex",
                      ),
                      clipBehavior: Clip.hardEdge,
                      onChanged:
                          (value) => setState(() {
                            nameController.text = value;
                          }),
                    ),
                    SizedBox(height: 16),
                    // Dropdown for changing the index
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: "Move Document to new Index",
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
                                    : "Document ${i + 1}"
                                : _docNames[i].isNotEmpty
                                ? _docNames[i]
                                : "Document ${i + 1}",
                          ),
                        ),
                      ),
                      onChanged:
                          allowChangeDocIndex
                              ? (int? newValue) {
                                if (newValue != null) {
                                  setState(() => currentIndex = newValue);
                                }
                              }
                              : null,
                      onTap:
                          !allowChangeDocIndex
                              ? () => Fluttertoast.showToast(
                                msg:
                                    'Blocked while other Documents are processing...',
                              )
                              : null,
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel"),
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
                child: Text("OK"),
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

  Future<void> _selectAspectRatios(BuildContext context) async {
    // bool List for selected Ratios
    List<bool> selectedStates =
        g.commonAspectRatios
            .map((aspect) => g.availableAspectRatios.contains(aspect))
            .toList();

    bool? selectionConfirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Select Aspect Ratios"),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Select the aspect ratios "
                  "that you want the app to be able to recognize "
                  "and that you can manually select.",
                ),
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
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text("Update"),
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
      saveAvailableAspectRatios();
    }
  }

  Future<void> saveAvailableAspectRatios() async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        g.availableAspectRatios.map((e) => e.value.toString()).toList();
    await prefs.setStringList("availableAspectRatios", values);
  }

  Future<void> loadAvailableAspectRatios() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValues = prefs.getStringList("availableAspectRatios");

    if (savedValues == null || savedValues.isEmpty) {
      // Default selection
      g.availableAspectRatios =
          g.commonAspectRatios
              .where(
                (e) =>
                    e.value == math.sqrt2 || // DIN
                    e.value == 1 || // Square
                    e.value == 4 / 3 || // 4:3
                    e.value == 16 / 9 || // 16:9
                    e.value == 21 / 9, // 21:9
              )
              .toList();
    } else {
      g.availableAspectRatios =
          g.commonAspectRatios
              .where((e) => savedValues.contains(e.value.toString()))
              .toList();
    }
  }

  Future<void> _shareAppDialog(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    controller.text =
        "Hey, I found this document scanner app that works without uploading your data.\n"
        "The image processing is really good!\n";
    final url = Uri(
      scheme: 'https',
      host: 'play.google.com',
      path: '/store/apps/details',
      queryParameters: {'id': 'com.rrapps.docscanner'},
    );
    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('Tell a Friend!'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: "Your message here.\n",
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
                    child: Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.share),
                    onPressed:
                        controller.text.trim().isEmpty
                            ? null
                            : () {
                              final message = controller.text.trim();
                              final fullMessage =
                                  "$message\n\nhttps://play.google.com/store/apps/details?id=com.rrapps.docscanner";
                              Share.share(fullMessage);
                            },
                    label: Text('Share'),
                  ),
                ],
              );
            },
          ),
    );
  }

  final ScrollController _scrollController = ScrollController();
  // Documents
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text("Documents"),
        actions: [
          if (feedbackHelper.canShowInAppbar())
            CustomExpandingButton(
              onPressed: () async {
                await feedbackHelper.showRatingDialog(context);
                setState(() {});
              },
              icon: Icons.star_half,
              text: "Give Feedback",
            ),
          PopupMenuButton(
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: "pro",
                    child: Row(
                      children: [
                        SizedBox(width: 8),
                        Icon(
                          g.proUnlocked == true ? Icons.verified : Icons.lock,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: 10),
                        Text(
                          g.proUnlocked == true ? "PRO Features" : "Unlock PRO",
                          style: TextStyle(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
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
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Licenses",
                          style: TextStyle(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
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
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Aspect Ratios",
                          style: TextStyle(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!feedbackHelper.isHidden())
                    PopupMenuItem(
                      value: "rate",
                      child: Row(
                        children: [
                          SizedBox(width: 8),
                          Icon(
                            Icons.star_half,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Give Feedback",
                            style: TextStyle(
                              color:
                                  Theme.of(
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
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Tell a Friend!",
                          style: TextStyle(
                            color:
                                Theme.of(
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
                    applicationName: 'Offline Document Scanner',
                    applicationVersion:
                        "${_packageInfo.version}+${_packageInfo.buildNumber}",
                  );
                  break;
                case "ratios":
                  _selectAspectRatios(context);
                  break;
                case "rate":
                  feedbackHelper.showRatingDialog(context);
                  break;
                case "shareApp":
                  _shareAppDialog(context);
                  break;
              }
            },
          ),
        ],
      ),
      body:
          _docThumbnails.isNotEmpty
              // Documents Cards
              ? CustomScrollbar(
                controller: _scrollController,
                pageAspectRatios:
                    _thumbnailRatios
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
                    String docName =
                        _docNames[docIndex].isNotEmpty
                            ? _docNames[docIndex]
                            : "Document $displayDocIndex";
                    String creationDate = _docDates[docIndex];
                    int pagesCount =
                        _docPageCounts.isNotEmpty
                            ? _docPageCounts[docIndex]
                            : -1;
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
                                        onTap:
                                            !_deletedDocs.contains(docIndex)
                                                ? () => _openDocEditDialog(
                                                  context,
                                                  docIndex,
                                                  displayDocIndex,
                                                )
                                                : null,
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 5,
                                                  ),
                                                  SizedBox(height: 6),
                                                  Text(
                                                    "Created: $creationDate",
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withAlpha(150),
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    "Pages: $pagesCount",
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
                                    !_deletedDocs.contains(docIndex)
                                        ? Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            // Save
                                            IconButton(
                                              onPressed:
                                                  () => _pagesPopup(
                                                    context,
                                                    [],
                                                    PopUpType.save,
                                                    docIndex,
                                                  ),
                                              icon: Icon(Icons.save),
                                            ),
                                            // Share
                                            IconButton(
                                              onPressed:
                                                  () => _pagesPopup(
                                                    context,
                                                    [],
                                                    PopUpType.share,
                                                    docIndex,
                                                  ),
                                              icon: Icon(Icons.share),
                                            ),
                                            // Delete
                                            IconButton(
                                              onPressed:
                                                  () => _pagesPopup(
                                                    context,
                                                    [],
                                                    PopUpType.delete,
                                                    docIndex,
                                                  ),
                                              icon: Icon(Icons.delete),
                                            ),
                                          ],
                                        )
                                        : SizedBox(),
                                  ],
                                ),
                              ),
                              // Thumbnail (Right Side)
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 184,
                                ), // space for creation date
                                child: Container(
                                  decoration: BoxDecoration(
                                    boxShadow: [bigBoxShadow(context)],
                                  ),
                                  child: Stack(
                                    children: [
                                      (_docThumbnails[docIndex].isNotEmpty)
                                          ? AnimatedSwitcher(
                                            duration: Duration(
                                              milliseconds: 200,
                                            ),
                                            child: Image.file(
                                              File(_docThumbnails[docIndex]),
                                              key: ValueKey(
                                                _docThumbnails[docIndex],
                                              ),
                                              fit: BoxFit.cover,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                return AspectRatio(
                                                  aspectRatio:
                                                      (_thumbnailRatios.length >
                                                              docIndex)
                                                          ? _thumbnailRatios[docIndex]
                                                          : 1.0 / math.sqrt2,
                                                  child: Builder(
                                                    builder: (context) {
                                                      return Material(
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .surfaceBright,
                                                        child: const Icon(
                                                          Icons.broken_image,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                          : AspectRatio(
                                            aspectRatio:
                                                _thumbnailRatios[docIndex],
                                            child: Builder(
                                              builder: (context) {
                                                return Material(
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .surfaceBright,
                                                  child:
                                                      IndicatorProcessingImage(),
                                                );
                                              },
                                            ),
                                          ),
                                      Positioned.fill(
                                        child: Material(
                                          color:
                                              _deletedDocs.contains(docIndex)
                                                  ? Color.fromRGBO(
                                                    100,
                                                    0,
                                                    10,
                                                    0.412,
                                                  )
                                                  : Colors.transparent,
                                          child:
                                              !_deletedDocs.contains(docIndex)
                                                  ? InkWell(
                                                    onTap:
                                                        () => _openDocument(
                                                          docIndex,
                                                        ),
                                                    onLongPress:
                                                        () =>
                                                            _openDocEditDialog(
                                                              context,
                                                              docIndex,
                                                              displayDocIndex,
                                                            ),
                                                    splashColor: Colors.black26,
                                                    highlightColor:
                                                        Colors.black26,
                                                  )
                                                  : Center(
                                                    child: Container(
                                                      padding: EdgeInsets.all(
                                                        12,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        color: Colors.black45,
                                                      ),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  8.0,
                                                                ),
                                                            child: SizedBox(
                                                              width: 24,
                                                              height: 24,
                                                              child: CircularProgressIndicator(
                                                                color:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                            ),
                                                          ),
                                                          Text(
                                                            "  Deleting...",
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                        ),
                                      ),
                                    ],
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
                      'Add a new Document',
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
                        'assets/arrow.png',
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
                  _openImagePicker(ImageSource.gallery, isMultiImage: true);
                },
                tooltip: 'Pick Images from Gallery',
                child: const Icon(Icons.photo_library),
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
                  _openDocument(indexPairsList.first.$1!);
                },
                tooltip: 'Pick PDF from Directory',
                child: const Icon(Icons.picture_as_pdf),
              ),
            ),
            SizedBox(height: 18.0),
            if (_picker.supportsImageSource(ImageSource.camera))
              FloatingActionButton(
                heroTag: "takePhotoDoc",
                onPressed: () {
                  _openImagePicker(ImageSource.camera);
                },
                tooltip: 'Take a Photo',
                child: const Icon(Icons.camera_alt),
              ),
          ],
        ),
      ),
    );
  }
}

class CustomExpandingButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String text;

  const CustomExpandingButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.star_half,
    this.text = "Give Feedback",
  });

  @override
  State<CustomExpandingButton> createState() => _CustomExpandingButtonState();
}

class _CustomExpandingButtonState extends State<CustomExpandingButton>
    with SingleTickerProviderStateMixin, RouteAware {
  static const animDuration = Duration(milliseconds: 350);

  bool _expanded = false;
  late Timer _collapseTimer;

  static const double _collapsedWidth = 40;
  static const double _expandedWidth = 150;
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
        _expandTemporarily();
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
        _expandTemporarily();
      }
    });
  }

  void _expandTemporarily() {
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
    _collapseTimer.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor =
        _expanded
            ? colorScheme.primaryContainer
            : colorScheme.primaryContainer.withAlpha(0);
    final textColor = colorScheme.onPrimaryContainer;

    return AnimatedContainer(
      duration: animDuration,
      width: _expanded ? _expandedWidth : _collapsedWidth,
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
          onLongPress: _expandTemporarily,
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
    );
  }
}

final InAppPurchase iap = InAppPurchase.instance;
final List<ProductDetails> products = [];
Future<void> initStoreInfo() async {
  final bool available = await iap.isAvailable();
  if (!available) {
    dev.log("Error, initStoreInfo: In-App-Purchases not available");
    return;
  }
  listenToPurchaseUpdates();

  const Set<String> productNames = {"pro_upgrade"};
  final ProductDetailsResponse response = await iap.queryProductDetails(
    productNames,
  );

  if (response.notFoundIDs.isNotEmpty) {
    dev.log(
      "Error, initStoreInfo: Product IDs not forund: ${response.notFoundIDs}",
    );
  }

  if (!available || response.notFoundIDs.contains("pro_upgrade")) {
    deactivateProAfterWeekOffline();
  }

  products.addAll(response.productDetails);
  iap.restorePurchases(); // activate listenToPurchaseUpdates() // does not work for license testing
}

deactivateProAfterWeekOffline() async {
  final sStorage = FlutterSecureStorage();

  final bool isSaved = 'true' == await sStorage.read(key: 'proUnlocked');
  final String? savedDate = await sStorage.read(key: 'proUnlockedDate');

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
                setPro(true);
                break;
              case PurchaseStatus.error:
                if (purchase.error != null) {
                  if (purchase.error!.message ==
                      "BillingResponse.itemAlreadyOwned") {
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
                      "BillingResponse.itemAlreadyOwned") {
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
    dev.log("Error, buyPro: proUpgrade not available: $e");
    return false;
  }
  final PurchaseParam purchaseParam = PurchaseParam(productDetails: proUpgrade);
  if (!await iap.buyNonConsumable(purchaseParam: purchaseParam)) {
    dev.log("Error, buyPro: Request not sent successfully.");
    return false;
  }
  return true;
}

Future<bool> proPopup(BuildContext context) async {
  bool? selectBuyPro = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title:
            g.proUnlocked == true
                ? Text("PRO Features:")
                : Text("Unlock PRO Features"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              " •  Save and share multi page PDFs.\n"
              " •  Get access to the PRO filter.",
            ),
            (g.proUnlocked == true)
                ? Text("\nThank you for your support! :)")
                : SizedBox(),
          ],
        ),
        actions: [
          g.proUnlocked == true
              ? ElevatedButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("OK", style: TextStyle(color: Colors.green)),
              )
              : TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("Cancel"),
              ),
          g.proUnlocked == true
              ? SizedBox()
              : ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text("Purchase", style: TextStyle(color: Colors.green)),
              ),
        ],
      );
    },
  );
  if (selectBuyPro == true) {
    return buyPro();
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
    key: 'proUnlocked',
    value: proUnlockedIn == true ? 'true' : 'false',
  );

  if (proUnlockedIn) {
    final now = DateTime.now().toIso8601String();
    sStorage.write(key: 'proUnlockedDate', value: now);
  }

  if (showMessages) {
    Fluttertoast.showToast(
      msg: proUnlockedIn ? 'PRO Features unlocked!' : 'PRO Features disabled!',
    );
  }
  globalNotifier.triggerEvent(NotifierEvent.setState);
}

Future<bool> _unlockDocumentWithAd(BuildContext context) async {
  final bool adWatched = await adsHelper.showRewardAd();
  if (adWatched) {
    Fluttertoast.showToast(
      msg: 'Combined PDF temorarily unlocked for Document!',
    );
    return true;
  }
  return false;
}

Future<bool> _unlockPageWithAd(BuildContext context) async {
  final bool adWatched = await adsHelper.showRewardAd();
  if (adWatched) {
    Fluttertoast.showToast(msg: 'PRO filter temorarily unlocked for Page!');
    return true;
  }
  return false;
}

class ImagesScrollPreview extends StatelessWidget {
  const ImagesScrollPreview({super.key, required this.pagePaths});

  final List<String> pagePaths;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  pagePaths.map((path) {
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
                          child:
                              path.isNotEmpty
                                  ? Image.file(
                                    File(path),
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return AspectRatio(
                                        aspectRatio: 1 / math.sqrt2,
                                        child: Material(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.surfaceBright,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                      );
                                    },
                                  )
                                  : AspectRatio(
                                    aspectRatio: 1 / math.sqrt2,
                                    child: Material(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceBright,
                                      child: Center(
                                        child:
                                            const CircularProgressIndicator(),
                                      ),
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
    globalNotifier.addListener(_handleGlobalEvent);
    _loadPagesThumbnails(onInit: true, supressWarnings: true);
    _initPushToPreview();
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  List<int> _deletedPages = [];
  Future<void> _handleGlobalEvent() async {
    if (!mounted) return;
    switch (globalNotifier.value) {
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

  @override
  void didPopNext() {
    _loadPagesThumbnails();
  }

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
    _thumbnailRatios = List.generate(_pagesCount, (_) => 1.0 / math.sqrt2);
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
      _thumbnailRatios[pageIndex] = 1.0 / ratioValue;
    }
    if (thumbnailPaths.isEmpty) {
      if (!onInit && mounted && context.mounted) {
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

  Future<void> _openPagePreview(int pageIndex) async {
    Navigator.pushNamed(
      context,
      '/preview',
      arguments: {'docIndex': widget.docIndex, 'pageIndex': pageIndex},
    );
  }

  Future<void> _openImagePicker(
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
    List<String> photoPaths;
    if (g.filesHelper.pickingImage) return;
    if (source == ImageSource.camera) {
      photoPaths = await _openCamera();
    } else {
      photoPaths = await g.filesHelper.pickImage(
        context,
        source,
        isMultiImage: isMultiImage,
      );
    }
    if (photoPaths.isEmpty) return;

    int firstPageIndex = await _processNewPages(
      photoPaths,
      photosAlreadyInPages: false,
    );

    // Only open PagePreview for first page
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
      g.metadataHelper.writeDocUnlocked(widget.docIndex, false);
      await Future.delayed(Duration(milliseconds: 25));
      imageProcessingManager.processPages(
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
    final result = await Navigator.pushNamed(context, '/camera');
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

  _selectAll() async {
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

  final ScrollController _scrollController = ScrollController();
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
        appBar:
            !_selectMode
                ? AppBar(
                  title: Text("Document ${widget.docIndex + 1}"),
                  actions: [
                    IconButton(
                      onPressed: () => _selectAll(),
                      icon: Icon(Icons.select_all),
                      tooltip: "Select all",
                    ),
                  ],
                )
                : AppBar(
                  title: Text("${_selectedPages.length} Pages selected"),
                  leading: IconButton(
                    onPressed: () => _cancelSelectMode(),
                    icon: Icon(Icons.close),
                    tooltip: "Cancel Selection",
                  ),
                  actions: [
                    IconButton(
                      onPressed: () => _selectAll(),
                      icon: Icon(Icons.select_all),
                      tooltip: "Select all",
                    ),
                  ],
                ),
        body:
            _pageThumbnails
                    .isNotEmpty // && isTopOfNavigationStack
                // Pages
                ? CustomScrollbar(
                  controller: _scrollController,
                  pageAspectRatios:
                      _thumbnailRatios
                          .whereIndexed(
                            (index, element) => !_deletedPages.contains(index),
                          )
                          .toList(),
                  scrollRangeStart: 0.1,
                  scrollRangeEnd: 0.675,

                  child: ListView.builder(
                    controller: _scrollController,
                    cacheExtent: 1000,
                    itemCount: _pagesCount,
                    itemBuilder: (BuildContext context, int pageIndex) {
                      if (_deletedPages.contains(pageIndex)) return SizedBox();
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
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 6,
                        ),
                        child: AspectRatio(
                          aspectRatio: thumbnailRatio,
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [bigBoxShadow(context)],
                            ),
                            child: Stack(
                              children: [
                                // Load image
                                (thumbnailPath.isNotEmpty)
                                    ? AnimatedSwitcher(
                                      duration: Duration(milliseconds: 200),
                                      child: Image.file(
                                        pageThumbnail,
                                        key: ValueKey(thumbnailPath),
                                        errorBuilder: (
                                          context,
                                          error,
                                          stackTrace,
                                        ) {
                                          return Material(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.surfaceBright,
                                            child: const Icon(
                                              Icons.broken_image,
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                    // Skeleton
                                    : Positioned.fill(
                                      child: Material(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surfaceBright,
                                        child: IndicatorProcessingImage(),
                                      ),
                                    ),
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
                                            : _deletedPages.contains(pageIndex)
                                            ? Color.fromRGBO(100, 0, 10, 0.412)
                                            : Colors.transparent,
                                    child:
                                        !_deletedPages.contains(pageIndex)
                                            ? InkWell(
                                              onTap:
                                                  !_selectMode
                                                      ? () => _openPagePreview(
                                                        pageIndex,
                                                      )
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
                                            )
                                            : Center(
                                              child: Container(
                                                padding: EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  color: Colors.black45,
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8.0,
                                                          ),
                                                      child: SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child:
                                                            CircularProgressIndicator(
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      ),
                                                    ),
                                                    Text(
                                                      "  Deleting...",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                  ),
                                ),
                                // Page Index Indicator
                                Positioned(
                                  top: 18,
                                  left: 12,
                                  child: GestureDetector(
                                    // Move Page Index Dialog
                                    onTap:
                                        !_deletedPages.contains(pageIndex)
                                            ? _selectMode
                                                ? () => _selectPage(pageIndex)
                                                : () => _openPageEditDialog(
                                                  context,
                                                  pageIndex,
                                                  displayPageIndex,
                                                )
                                            : null,
                                    onLongPress:
                                        !_deletedPages.contains(pageIndex)
                                            ? () => _selectPage(pageIndex)
                                            : null,
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
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surfaceBright,
                                        borderRadius: BorderRadius.circular(20),
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
                        ),
                      );
                    },
                  ),
                )
                : const SizedBox(),
        // Floating Action Buttons
        floatingActionButton: Padding(
          padding: const EdgeInsets.all(20.0),
          child:
              !_selectMode
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
                            _openImagePicker(
                              ImageSource.gallery,
                              isMultiImage: true,
                            );
                          },
                          tooltip: 'Pick Images from Gallery',
                          child: const Icon(Icons.photo_library),
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
                                .pickPdfToDoc(
                                  addToDocWithIndex: widget.docIndex,
                                );
                            int pdfsCount = indexPairsList.length;
                            if (pdfsCount != 0 && context.mounted) {
                              ScaffoldMessengerState messenger =
                                  ScaffoldMessenger.of(context);
                              SnackBar snackBar = SnackBar(
                                content: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Importing PDF${(pdfsCount > 1) ? "s" : ""}...",
                                    ),
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                      ),
                                    ),
                                  ],
                                ),
                                duration: const Duration(days: 1),
                              );
                              messenger.showSnackBar(snackBar);
                              hideSnackbarOnPageReload() {
                                if (globalNotifier.value ==
                                    NotifierEvent.loadPagesThumbnails) {
                                  messenger.hideCurrentSnackBar();
                                  globalNotifier.removeListener(
                                    hideSnackbarOnPageReload,
                                  );
                                }
                              }

                              globalNotifier.addListener(
                                hideSnackbarOnPageReload,
                              );
                            }
                          },
                          tooltip: 'Pick PDF from Directory',
                          child: const Icon(Icons.picture_as_pdf),
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
                          tooltip: 'Take a Photo',
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
                          tooltip: 'Delete',
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
                            _pagesPopup(
                              context,
                              _selectedPages,
                              PopUpType.save,
                              widget.docIndex,
                            );
                          },
                          tooltip: 'Save',
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
                          tooltip: 'Share',
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
              setState(() => allowChangePageIndex = true);
            });
            return AlertDialog(
              title: Text("Page $displayPageIndex"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Move Page to new Index - Dropdown
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: "Move Page to new Index",
                    ),
                    value: currentIndex,
                    isExpanded: true,
                    items: List.generate(
                      _pageThumbnails.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(
                          overflow: TextOverflow.ellipsis,
                          "Page ${i + 1}",
                        ),
                      ),
                    ),
                    onChanged:
                        allowChangePageIndex
                            ? (int? newValue) {
                              if (newValue != null) {
                                setState(() => currentIndex = newValue);
                              }
                            }
                            : null,
                    onTap:
                        !allowChangePageIndex
                            ? () => Fluttertoast.showToast(
                              msg:
                                  'Blocked while other Pages of this Document are processing...',
                            )
                            : null,
                  ),
                  SizedBox(height: 24),
                  // Reverse Order - Button
                  ElevatedButton.icon(
                    onPressed:
                        allowChangePageIndex
                            ? () async {
                              await g.filesHelper.reversePagesOrder(
                                widget.docIndex,
                              );
                              if (context.mounted) Navigator.pop(context);
                              _loadPagesThumbnails();
                            }
                            : () => Fluttertoast.showToast(
                              msg:
                                  'Blocked while Pages of this Document are processing...',
                            ),
                    label: Text("Reverse Order"),
                    icon: Icon(Icons.swap_vert),
                  ),
                  //SizedBox(height: 24),
                  //// Save, Share, Delete
                  //Align(
                  //  alignment: Alignment.centerLeft,
                  //  child: Text(
                  //    "Save, Share, Delete",
                  //    style: TextStyle(
                  //      color: Colors.white70,
                  //      fontSize: 12,
                  //      fontWeight: FontWeight.w400,
                  //    ),
                  //  ),
                  //),
                  //Row(
                  //  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  //  children: [
                  //    // Save
                  //    IconButton(
                  //      onPressed:
                  //          () => _pagesPopup(
                  //            context,
                  //            [pageIndex],
                  //            PopUpType.save,
                  //            widget.docIndex,
                  //          ),
                  //      icon: Icon(Icons.save),
                  //    ),
                  //    // Share
                  //    IconButton(
                  //      onPressed:
                  //          () => _pagesPopup(
                  //            context,
                  //            [pageIndex],
                  //            PopUpType.share,
                  //            widget.docIndex,
                  //          ),
                  //      icon: Icon(Icons.share),
                  //    ),
                  //    // Delete
                  //    IconButton(
                  //      onPressed: () async {
                  //        if (await _pagesPopup(
                  //          context,
                  //          selected,
                  //          PopUpType.delete,
                  //          widget.docIndex,
                  //        )) {
                  //          if (context.mounted) {
                  //            Navigator.pop(context);
                  //          }
                  //        }
                  //      },
                  //      icon: Icon(Icons.delete),
                  //    ),
                  //  ],
                  //),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, currentIndex);
                  },
                  child: Text("OK"),
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
}

class CustomScrollbar extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
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

  double maxScroll = double.infinity;
  _setMaxScroll({bool reset = false}) {
    if (!widget.controller.hasClients) return;
    if (reset) {
      maxScroll = widget.controller.position.maxScrollExtent;
    } else {
      maxScroll = [
        widget.controller.position.maxScrollExtent,
        maxScroll,
      ].reduce(math.min);
    }
  }

  List<double> ratios = [];
  _setRatios() {
    final List<double> priorRatios = List<double>.from(ratios);
    ratios = List<double>.from(widget.pageAspectRatios);
    ratios[ratios.length - 1] = 0.0;
    return priorRatios != ratios;
  }

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
    widget.controller.addListener(_onScroll);
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
    _railSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.5, 0), // slide off to the right
    ).animate(
      CurvedAnimation(parent: _railSlideController, curve: Curves.easeInOut),
    );
    _setRatios();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hideTimer?.cancel();
    _fadeController.dispose();
    _railSlideController.dispose();
    super.dispose();
  }

  void _onScroll() {
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

    final scrollFraction =
        maxScroll == 0
            ? 0
            : (widget.controller.offset / maxScroll).clamp(0.0, 1.0);
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
    _thumbTop = (_thumbTop + details.delta.dy).clamp(minTop, maxTop);
    setState(() {});

    // move page
    final scrollAreaHeight = maxTop - minTop;
    final scrollFraction = (_thumbTop - minTop) / scrollAreaHeight;

    final newScrollOffset = scrollFraction * maxScroll;
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
    if (!widget.controller.hasClients || ratios.isEmpty) {
      return 0;
    }

    final offset = widget.controller.offset;

    final total = ratios.fold<double>(0.0, (a, b) => a + b);
    final cumulative = <double>[];
    double sum = 0.0;
    for (var ratio in ratios) {
      sum += ratio;
      cumulative.add(sum);
    }

    final scrolledFraction = maxScroll == 0 ? 0 : offset / maxScroll;
    final scrollPosition = total * scrolledFraction;

    for (int i = 0; i < cumulative.length; i++) {
      if (scrollPosition < cumulative[i]) {
        return i;
      }
    }

    return ratios.length - 1;
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
        widget.controller.offset >= maxScroll)) {
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

    final bool newRatios = _setRatios();
    _setMaxScroll(reset: newRatios);

    return LayoutBuilder(
      builder: (_, constraints) {
        return Stack(
          children: [
            // Child
            //AbsorbPointer(absorbing: _isDragging, child:
            widget.child,
            //)
            // Rail
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
                    onVerticalDragUpdate:
                        (d) => _onDragUpdate(d, constraints.maxHeight),
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
                            '${_getCurrentPage() + 1}/${ratios.length}',
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
  static const List<String> versionNames = [
    "Photo",
    "Transformed",
    "Basic",
    "PRO",
  ];
  // Widget
  int _selectedVersion = 0;
  List<String> _versionPaths = ["", "", "", ""];
  final List<Future<String>> _rotatedPhotoPaths = List.generate(
    3,
    (_) => Future<String>.value(""),
  );
  String _photoPath = "";
  int _imageRetryKey = 0; // to refresh brokenImages
  // Reprocessing Parameters
  double? _ratioValue;
  double? _guiRatioValue;
  int? _orientation;
  int? _guiOrientationIndex;
  int _totalRotation = 0;
  // Corner Points
  List<List<int>> _cornerPoints = [];
  int _imagePixelWidth = 0;
  int _imagePixelHeight = 0;
  bool _hideOverlayReprocessing = false;
  // Status
  bool _rotationOngoing = false;
  bool _metadataBlocked = true;
  // PageView
  final PageController _pageController = PageController();
  final PhotoViewController _photoViewController = PhotoViewController();
  double _photoScale = 0.0;
  double _evenPhotoScale = 0.0;
  double _oddPhotoScale = 0.0;
  // Unlock page
  bool _pageUnlocked = false;

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
    globalNotifier.addListener(_handleGlobalEvent);
    FilesHelper.deleteCachedRoatedImages();
    _pollForImagesAndMetadata();
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
    var imagePaths = await g.filesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    );
    _versionPaths = imagePaths.$1;
    _photoPath = _versionPaths.first;
    _showAllImages();
    _loadPageMeatadata(supressWarnings: true);
    _pageUnlocked = await g.metadataHelper.readPageUnlocked(
      widget.docIndex,
      widget.pageIndex,
      supressWarnings: true,
    );
    // if processing on init
    if (_versionPaths.any((element) => element.isEmpty)) {
      // Feedback Popup
      bool showRatingPopupWhileProcessing =
          feedbackHelper.canShowProcessingPopup();
      if (showRatingPopupWhileProcessing) {
        // ignore: use_build_context_synchronously
        feedbackHelper.showRatingDialog(context);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _photoViewController.dispose();
    globalNotifier.removeListener(_handleGlobalEvent);
    FilesHelper.deleteCachedRoatedImages();
    super.dispose();
  }

  Future<void> _handleGlobalEvent() async {
    if (!mounted) return;
    switch (globalNotifier.value) {
      case NotifierEvent.setState:
        _pageUnlocked = await g.metadataHelper.readPageUnlocked(
          widget.docIndex,
          widget.pageIndex,
        );
        setState(() {});
        break;
      case NotifierEvent.imagesDeleted:
        if (!File(_photoPath).existsSync()) {
          _allowPop = true;
          Navigator.pop(context);
        }
        break;
      default:
    }
  }

  void _pollForImagesAndMetadata() {
    // Poll Metadtata
    _pollWhile(
      condition: () => _ratioValue == null || _orientation == null,
      onTick: () => _loadPageMeatadata(),
    );
    // Poll Images
    for (int i = 0; i <= 3; i++) {
      _pollWhile(
        condition: () => _versionPaths[i].isEmpty,
        onTick: () async {
          _versionPaths[i] = await g.filesHelper.getVersionPath(
            widget.docIndex,
            widget.pageIndex,
            i,
          );
        },
        onComplete: () {
          if (i == 0) {
            // Photo
            _photoPath = _versionPaths.first;
            FilesHelper.deleteCachedRoatedImages();
            _refreshCornersOverlay(supressWarnings: true);
          }
          setState(() {});
        },
      );
    }
  }

  void _pollWhile({
    required bool Function() condition,
    required FutureOr<void> Function() onTick,
    FutureOr<void> Function()? onComplete,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    while (condition()) {
      await onTick();
      await Future.delayed(delay);
    }
    if (onComplete != null) {
      await onComplete();
    }
  }

  _showAllImages() async {
    if (!mounted || _versionPaths.isEmpty) return;
    for (var versionPath in _versionPaths) {
      if (versionPath.isEmpty) return;
    }
    int? versionIndex = await MetadataHelper.readPageThumbnailIndex(
      widget.docIndex,
      widget.pageIndex,
    );
    setState(() => _selectedVersion = versionIndex);
    _pageController.jumpToPage(_selectedVersion);
  }

  Future<void> _loadPageMeatadata({bool supressWarnings = false}) async {
    _guiRatioValue =
        _ratioValue = await MetadataHelper.readPageRatioValue(
          widget.docIndex,
          widget.pageIndex,
          supressWarnings: supressWarnings,
        );
    _guiOrientationIndex =
        _orientation = await MetadataHelper.readPageOrientationIndex(
          widget.docIndex,
          widget.pageIndex,
          supressWarnings: supressWarnings,
        );
    if (mounted) {
      setState(() {
        _guiRatioValue;
        _guiOrientationIndex;
      });
    }
    await _refreshCornersOverlay(supressWarnings: supressWarnings);
    if (mounted) {
      setState(() {
        _cornerPoints;
        if (_cornerPoints.isNotEmpty) {
          _hideOverlayReprocessing = false;
          _metadataBlocked = false;
        }
      });
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
    if (_versionPaths[0].isEmpty) return;
    final image = await decodeImageFromList(
      (File(_versionPaths[0]).readAsBytesSync()),
    );
    _imagePixelWidth = image.width;
    _imagePixelHeight = image.height;
    if (mounted) setState(() {});
  }

  Future<void> _reprocessingSetup() async {
    _metadataBlocked = true;
    _ratioValue = null; // don't reset _new values, for uninterrupted display
    _orientation = null;
    _totalRotation = 0;
    g.filesHelper.deleteProcessedVersionsOfPage(
      widget.docIndex,
      widget.pageIndex,
    );
    _pollForImagesAndMetadata();
  }

  void _reprocessingCleanup() {
    _evenPhotoScale = 0.0;
    _oddPhotoScale = 0.0;
    _versionPaths = ["", "", "", ""];
    setState(() {});
  }

  Future<void> _openWarpManuallyPage() async {
    Navigator.pushNamed(
      context,
      '/warp',
      arguments: {
        'pagePreviewState': this,
        'docIndex': widget.docIndex,
        'pageIndex': widget.pageIndex,
        'imagePath': _versionPaths.first,
        'cornerPoints': _cornerPoints,
        'rotation': _totalRotation,
      },
    );
  }

  Future<void> _popOnProFilterPopup(BuildContext context) async {
    //final bool? selectedUnlock = await
    showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Unlock PRO filter"),
          content: Text(
            "You have selected the PRO filter, by selecting it"
            "and then trying to leave this page.\n\n"
            "To get access, first unlock PRO Features.\n\n"
            "Alternatively select a different version before leaving.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel"),
            ),
            //ElevatedButton(
            //  onPressed: () => Navigator.pop(context, true),
            //  child: Text("Purchase", style: TextStyle(color: Colors.green)),
            //),
            ElevatedButton.icon(
              onPressed: () async {
                bool purchased = await proPopup(context);
                if (context.mounted) {
                  Navigator.pop(context, purchased);
                }
              },
              icon: Icon(Icons.lock),
              label: Text("Unlock PRO"),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                bool adWatched = await _unlockPageWithAd(context);
                _pageUnlocked = adWatched;
                setState(() {});
                if (context.mounted) {
                  Navigator.pop(context, adWatched);
                }
                g.metadataHelper.writePageUnlocked(
                  widget.docIndex,
                  widget.pageIndex,
                  adWatched,
                );
              },
              icon: Icon(Icons.play_arrow),
              label: Text("Watch Ad"),
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

  // Page Preview
  bool _allowPop = true;
  @override
  Widget build(BuildContext context) {
    bool enableFAB0 = _versionPaths.first.isNotEmpty && !_rotationOngoing;
    bool enableFABs =
        _selectedVersion == 0
            ? enableFAB0
            : _versionPaths[_selectedVersion].isNotEmpty;
    _allowPop = g.proUnlocked == true || _selectedVersion != 3 || _pageUnlocked;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!_allowPop) {
          HapticFeedback.heavyImpact();
          _popOnProFilterPopup(context);
        } else {
          // new thumbnail
          imageProcessingManager.saveNewThumbnail(
            widget.docIndex,
            widget.pageIndex,
            _selectedVersion,
            tmpPro: _pageUnlocked,
          );
          if (!didPop) Navigator.pop(context);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        // Top Bar
        appBar: AppBar(
          title: Text('Page ${widget.pageIndex + 1}'),
          actions: [
            PopupMenuButton(
              itemBuilder:
                  (context) => [
                    PopupMenuItem(
                      value: "del",
                      child: Row(
                        children: [
                          SizedBox(width: 12),
                          Icon(
                            Icons.delete,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Delete Page",
                            style: TextStyle(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              onSelected: (String value) async {
                switch (value) {
                  case "del":
                    bool deletionConfirmed = await _pagesPopup(
                      context,
                      [widget.pageIndex],
                      PopUpType.delete,
                      widget.docIndex,
                      versionIndex: _selectedVersion,
                    );
                    if (deletionConfirmed && mounted && context.mounted) {
                      Navigator.pop(context);
                    }
                    break;
                }
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // Bg Shadow
            Align(
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio:
                    (((_orientation ?? 0) == 0)
                        ? 1.0 / (_ratioValue ?? math.sqrt2)
                        : (_ratioValue ?? math.sqrt2)),
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withAlpha(25),
                        blurRadius: 50,
                        spreadRadius: -20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Images (Page Versions)
            PhotoViewGallery.builder(
              scrollPhysics: const PageScrollPhysics(),
              itemCount: _versionPaths.length,
              builder: (context, index) {
                // Loading indicator
                if (_versionPaths[index].isEmpty) {
                  return PhotoViewGalleryPageOptions.customChild(
                    child: IndicatorProcessingImage(),
                  );
                }
                // Photo
                if (index == 0) {
                  bool isZoomed = false;
                  return PhotoViewGalleryPageOptions.customChild(
                    child: Stack(
                      children: [
                        PhotoView(
                          controller: _photoViewController,
                          imageProvider: FileImage(File(_versionPaths[0])),
                          filterQuality: FilterQuality.high,
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: 1.0,
                          key: ValueKey(_imageRetryKey),
                          errorBuilder: (context, error, stackTrace) {
                            _refreshAfterBrokenImage(index);
                            return IndicatorProcessingImage();
                          },
                          backgroundDecoration: BoxDecoration(
                            color: Colors.transparent,
                          ),
                          scaleStateChangedCallback: (scaleState) async {
                            isZoomed =
                                scaleState != PhotoViewScaleState.initial;
                            if (!isZoomed) {
                              await Future.delayed(Duration(milliseconds: 300));
                            } // delay becuase of zoom animation
                            setState(() {
                              _hideOverlayReprocessing = isZoomed;
                            });
                          },
                        ),

                        // Corner Points
                        _displayCornerOverlay(context),
                      ],
                    ),
                  );
                }
                // Processed Images
                return PhotoViewGalleryPageOptions(
                  imageProvider: FileImage(File(_versionPaths[index])),
                  filterQuality: FilterQuality.high,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: 1.0,
                  key: ValueKey(_imageRetryKey),
                  errorBuilder: (context, error, stackTrace) {
                    _refreshAfterBrokenImage(index);
                    return IndicatorProcessingImage();
                  },
                );
              },
              backgroundDecoration: BoxDecoration(color: Colors.transparent),
              pageController: _pageController,
              onPageChanged: (index) {
                setState(() => _selectedVersion = index);
              },
            ),
            // Reprocessing Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Align(
                alignment:
                    _selectedVersion == 0
                        ? Alignment.topCenter
                        : Alignment.topLeft,

                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  constraints: BoxConstraints(minHeight: 48, maxHeight: 48),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [smallBoxShadow(context)],
                  ),
                  child:
                      _selectedVersion == 0
                          ? Row(
                            spacing: 12,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                spacing: 12,
                                children: [
                                  _aspectRatioDropDown(context),
                                  _orientationDropDown(context),
                                  _rotateButton(
                                    context,
                                    -90,
                                    Icons.rotate_left,
                                    "Rotate 90° left",
                                  ),
                                  _rotateButton(
                                    context,
                                    90,
                                    Icons.rotate_right,
                                    "Rotate 90° right",
                                  ),
                                ],
                              ),
                              _confirmReProcessingButton(context),
                            ],
                          )
                          : _toEditingButton(context),
                ),
              ),
            ),
          ],
        ),
        // Floating Buttons
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _selectedVersion == 0
                ? SizedBox(
                  width: 40,
                  height: 40,
                  child: FloatingActionButton(
                    heroTag: "adjustCorners",
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onPressed:
                        enableFAB0 && !_metadataBlocked
                            ? () => _openWarpManuallyPage()
                            : null,
                    tooltip:
                        enableFAB0 && !_metadataBlocked
                            ? 'Adjust Corner Points'
                            : 'Waiting for image to load...',
                    backgroundColor:
                        enableFAB0 && !_metadataBlocked
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
                            color:
                                enableFAB0 && !_metadataBlocked
                                    ? null
                                    : Theme.of(context).disabledColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                : SizedBox(),
            SizedBox(height: 18.0),
            SizedBox(
              width: 40,
              height: 40,
              child: FloatingActionButton(
                heroTag: "savePageVersion",
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onPressed:
                    enableFABs
                        ? () => _pagesPopup(
                          context,
                          [widget.pageIndex],
                          PopUpType.save,
                          widget.docIndex,
                          versionIndex: _selectedVersion,
                        )
                        : null,
                tooltip:
                    enableFABs ? 'Save Image' : 'Waiting for image to load...',
                backgroundColor:
                    enableFABs ? null : Theme.of(context).disabledColor,
                elevation: enableFABs ? null : 0.0,
                child: Icon(
                  Icons.save,
                  color: enableFABs ? null : Theme.of(context).disabledColor,
                ),
              ),
            ),
            SizedBox(height: 18.0),
            FloatingActionButton(
              heroTag: "sharePageVersion",

              onPressed:
                  enableFABs
                      ? () => _pagesPopup(
                        context,
                        [widget.pageIndex],
                        PopUpType.share,
                        widget.docIndex,
                        versionIndex: _selectedVersion,
                      )
                      : null,
              tooltip:
                  enableFABs ? 'Share Image' : 'Waiting for image to load...',
              backgroundColor:
                  enableFABs ? null : Theme.of(context).disabledColor,
              elevation: enableFABs ? null : 0.0,
              child: Icon(
                Icons.share,
                color: enableFABs ? null : Theme.of(context).disabledColor,
              ),
            ),
            SizedBox(height: 20.0),
          ],
        ),
        // Thumbnail Bar
        bottomNavigationBar: SizedBox(
          height: 130,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedVersion = index);
                  _pageController.jumpToPage(index);
                },
                child: Column(
                  children: [
                    Stack(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  _selectedVersion == index
                                      ? Colors.white
                                      : Colors.white54,
                              width: 3,
                            ),
                            boxShadow: [bigBoxShadow(context)],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.5),
                            child:
                                _versionPaths[index].isNotEmpty
                                    ? Image.file(
                                      File(_versionPaths[index]),
                                      width:
                                          _selectedVersion == index ? 70 : 50,
                                      height:
                                          _selectedVersion == index ? 70 : 50,
                                      fit: BoxFit.cover,
                                      key: ValueKey(_imageRetryKey),
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        _refreshAfterBrokenImage(index);
                                        return SizedBox(
                                          width:
                                              _selectedVersion == index
                                                  ? 70
                                                  : 50,
                                          height:
                                              _selectedVersion == index
                                                  ? 70
                                                  : 50,
                                          child: const Padding(
                                            padding: EdgeInsets.all(12.0),
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      },
                                    )
                                    : Container(
                                      width:
                                          _selectedVersion == index &&
                                                  index != 0
                                              ? 70
                                              : 50,
                                      height:
                                          _selectedVersion == index &&
                                                  index != 0
                                              ? 70
                                              : 50,
                                      color: Theme.of(context).disabledColor,
                                      child: const Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                          ),
                        ),
                        // Locked Badge
                        (g.proUnlocked == true || index != 3 || _pageUnlocked)
                            ? SizedBox()
                            : Positioned(
                              top: 0,
                              right: 0,
                              child: CustomIconButton(
                                onTap: null,
                                icon: Icons.lock,
                                iconColor:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                              ),
                            ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      versionNames[index],
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Padding _toEditingButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CustomIconButton(
        onTap: () {
          setState(() => _selectedVersion = 0);
          _pageController.jumpToPage(0);
        },
        isFlat: true,
        icon: Icons.keyboard_arrow_left,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        constraints: BoxConstraints(maxHeight: 46, maxWidth: 60),
        child: Icon(Icons.edit),
      ),
    );
  }

  Future<void> _refreshAfterBrokenImage(int index) async {
    dev.log("_refreshAfterBrokenImage");
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _imageRetryKey = (_imageRetryKey - 1) * (-1);
        });
      } else {
        dev.log("Error, _refreshAfterBrokenImage: not mounted");
      }
    });
  }

  CustomIconButton _rotateButton(
    BuildContext context,
    int rotation,
    IconData icon,
    String tooltip,
  ) {
    return CustomIconButton(
      onTap: () async {
        setState(() {
          _rotationOngoing = true;
          _guiOrientationIndex =
              ((_guiOrientationIndex ?? 0) - 1) * (-1); // toggle
        });
        _totalRotation = (_totalRotation + rotation) % 360;
        int quarterTurns = _totalRotation ~/ 90;
        if (_totalRotation == 0) {
          setState(() {
            _versionPaths[0] = _photoPath;
            _rotationOngoing = false;
          });
        } else {
          _rotatedPhotoPaths[quarterTurns -
              1] = FilesHelper.rotateImageInTmpDir(_photoPath, _totalRotation);
          _rotatedPhotoPaths[quarterTurns - 1].whenComplete(() async {
            // if image matches current rotation
            if (_totalRotation ~/ 90 == quarterTurns) {
              _versionPaths[0] = await _rotatedPhotoPaths[quarterTurns - 1];
              if (mounted) {
                _rotationOngoing = false;
                setState(() {});
              }
            }
          });
        }
      },
      isFlat: true,
      //isDisabled: _rotationOngoing,
      icon: icon,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      tooltip: tooltip,
    );
  }

  CustomIconButton _confirmReProcessingButton(BuildContext context) {
    return CustomIconButton(
      constraints: BoxConstraints(maxHeight: 30, maxWidth: 30),
      color: Theme.of(context).colorScheme.primaryContainer,
      icon: Icons.check,
      iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
      isDisabled:
          _versionPaths.isEmpty ||
          _versionPaths.first.isEmpty ||
          _metadataBlocked ||
          _rotationOngoing,
      isHidden:
          ((_guiRatioValue != null &&
                  (_ratioValue == _guiRatioValue ||
                      _ratioValue == 1.0 / _guiRatioValue!)) &&
              (_orientation == _guiOrientationIndex) &&
              _totalRotation == 0),
      tooltip: "Confirm changes",
      onTap: () async {
        await reprocessPhoto();
      },
    );
  }

  Future<void> reprocessPhoto({List<List<int>>? newCornerPoints}) async {
    if (mounted) {
      setState(() {
        _hideOverlayReprocessing = true;
      });
    }

    bool onlyRotation = true;
    bool customCorners = false;

    // Read Matadata
    var metadata = await g.metadataHelper.readPageProcessingMetadata(
      widget.docIndex,
      widget.pageIndex,
    );
    double? ratioValue = metadata.$1;
    int? orientationIndex = metadata.$2;
    //List<List<int>>? cornerPoints = metadata.$4;

    // use new / rotate old corner points
    imageProcessingManager.killIsolatesOfPage(
      widget.docIndex,
      widget.pageIndex,
    );
    if (newCornerPoints == null) {
      newCornerPoints = await MetadataHelper.readPageCornerPoints(
        widget.docIndex,
        widget.pageIndex,
      );
      newCornerPoints = rotateCornerPoints(newCornerPoints);
    } else {
      onlyRotation = false;
      customCorners = true;
    }

    await MetadataHelper.writePageProcessingMetadata(
      widget.docIndex,
      widget.pageIndex,
      _guiRatioValue,
      _guiOrientationIndex,
      newCornerPoints,
    );

    // Compare old and new metadata -> only rotation?

    if (ratioValue != _guiRatioValue) onlyRotation = false;
    int quarterTurns = (_totalRotation ~/ 90) % 4;
    if (quarterTurns.isEven && orientationIndex != _guiOrientationIndex ||
        quarterTurns.isOdd && orientationIndex == _guiOrientationIndex) {
      onlyRotation = false;
    }

    if (onlyRotation && _versionPaths.every((key) => File(key).existsSync())) {
      if (mounted) {
        setState(() {
          _metadataBlocked = true;
        });
        MetadataHelper.writePageCornerPoints(
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
        (g.proUnlocked == true ? 3 : 2),
      );
      _totalRotation = 0;
    } else {
      _reprocessingSetup();
      imageProcessingManager.reprocessPage(
        widget.docIndex,
        widget.pageIndex,
        _versionPaths[0], // potentially rotated image
        customCorners ? null : _guiRatioValue,
        customCorners ? null : _guiOrientationIndex,
        (g.proUnlocked == true ? 3 : 2),
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
    List<List<int>> rotated =
        cornerPoints.map((p) {
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
            g.availableAspectRatios.length,
            (i) => DropdownMenuItem(
              alignment: Alignment.center,
              value: i,
              child: Text(
                g.availableAspectRatios[i].name,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          onChanged:
              _versionPaths.first.isEmpty || _metadataBlocked
                  ? null
                  : (int? newValue) {
                    if (newValue != null && newValue != _guiRatioValue) {
                      setState(
                        () =>
                            _guiRatioValue =
                                g.availableAspectRatios[newValue].value,
                      );
                    }
                  },
        ),
      ),
    );
  }

  Container _orientationDropDown(BuildContext context) {
    const double height = 30;
    List<String> orientationsList = ["Portrait", "Landscape"];
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
          onChanged:
              _versionPaths.first.isEmpty || _metadataBlocked
                  ? null
                  : (int? newValue) {
                    if (newValue != null && newValue != _guiOrientationIndex) {
                      setState(() => _guiOrientationIndex = newValue);
                    }
                  },
        ),
      ),
    );
  }

  Widget _displayCornerOverlay(BuildContext context) {
    if (_cornerPoints.isEmpty ||
        _photoScale == 0.0 ||
        _rotationOngoing ||
        _hideOverlayReprocessing) {
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
      } else {
        return SizedBox();
      }
      displayHeight = _imagePixelHeight * _photoScale;
      displayWidth = _imagePixelWidth * _photoScale;
    } else {
      if (_oddPhotoScale == 0.0 && _photoScale != _evenPhotoScale) {
        _oddPhotoScale = _photoScale;
      } else if (_oddPhotoScale != 0.0) {
        _photoScale = _oddPhotoScale;
      } else {
        return SizedBox();
      }
      displayHeight = _imagePixelWidth * _photoScale;
      displayWidth = _imagePixelHeight * _photoScale;
    }

    // Apply rotation to corner points visually
    List<Offset> scaledPoints =
        _cornerPoints.map((point) {
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
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _FrameLinePainter(points: scaledPoints),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 2.0,
                    offset: 0.1,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: _MiddleLinePainter(
                    points: scaledPoints,
                    strokeWidth: 2.0,
                    color: Colors.white,
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

class _FrameLinePainter extends CustomPainter {
  final List<Offset> points;
  // ignore: prefer_typing_uninitialized_variables
  final color;
  // ignore: prefer_typing_uninitialized_variables
  final strokeWidth;

  _FrameLinePainter({
    required this.points,
    // ignore: unused_element_parameter
    this.color = Colors.black45,
    // ignore: unused_element_parameter
    this.strokeWidth = 7.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paintEdges =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;

    var order = [0, 2, 3, 1];
    List<Offset> orderedPoints = order.map((i) => points[i]).toList();

    // Edges
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < orderedPoints.length; i++) {
      path.lineTo(orderedPoints[i].dx, orderedPoints[i].dy);
    }
    path.close();
    canvas.drawPath(path, paintEdges);
  }

  @override
  bool shouldRepaint(covariant _FrameLinePainter oldDelegate) =>
      oldDelegate.points != points;
}

class _CornerLinePainter extends CustomPainter {
  final List<Offset> points;
  // ignore: prefer_typing_uninitialized_variables
  final color;
  // ignore: prefer_typing_uninitialized_variables
  final strokeWidth;
  final double offset;
  final bool normalizedOffset;

  _CornerLinePainter({
    required this.points,
    // ignore: unused_element_parameter
    this.color = Colors.white,
    this.strokeWidth = 2.0,
    this.offset = 17.0,
    this.normalizedOffset = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paintCorners =
        Paint()
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
      p1 -= delta / delta.distance * strokeWidth / 2;
      p2 += delta / delta.distance * strokeWidth / 2;
      Offset startOffset = p1 + (normalizedOffset ? deltaN : delta) * offset;
      Offset endOffset = p2 - (normalizedOffset ? deltaN : delta) * offset;
      canvas.drawLine(p1, startOffset, paintCorners);
      canvas.drawLine(endOffset, p2, paintCorners);
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

    final paintCorners =
        Paint()
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
        const Text("Processing image..."),
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
  final Color? color;
  final IconData icon;
  final Color? iconColor;
  final double radius;
  final bool isFlat;
  final bool isHidden;
  final bool isDisabled;
  final String? tooltip;
  final Widget child;

  const CustomIconButton({
    super.key,
    required this.onTap,
    this.constraints = const BoxConstraints(maxHeight: 36, maxWidth: 36),
    this.color,
    this.icon = Icons.check,
    this.iconColor,
    this.radius = 20,
    this.isFlat = false,
    this.isHidden = false,
    this.isDisabled = false,
    this.tooltip,
    this.child = const SizedBox(),
  });

  @override
  Widget build(BuildContext context) {
    return isHidden
        ? Stack()
        : Stack(
          children: [
            Container(
              constraints: constraints,
              decoration:
                  isFlat
                      ? null
                      : BoxDecoration(
                        color:
                            isDisabled
                                ? Theme.of(context).disabledColor
                                : color,
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow:
                            isDisabled ? null : [smallBoxShadow(context)],
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
                          color:
                              isDisabled
                                  ? Theme.of(context).disabledColor
                                  : iconColor,
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
  double _displayHeigth = 0;
  double _scale = 1.0;
  int _imagePixelWidth = 0;
  int _imagePixelHeight = 0;
  int? _currentCorner;
  Offset _touchOffset = Offset(0, 0);
  bool _panning = false;
  double _moveUpBy = 0;

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
    _initZoom();
  }

  void _initAsync() async {
    final image = await decodeImageFromList(
      (File(widget.imagePath).readAsBytesSync()),
    );
    _imagePixelWidth = image.width;
    _imagePixelHeight = image.height;
    if (mounted) {
      _screenWidth = MediaQuery.of(context).size.width;
    }
    _scale = _screenWidth / _imagePixelWidth;
    _displayHeigth = _imagePixelHeight * _scale;

    var rotatedPoints = widget.pagePreviewState.rotateCornerPoints(
      widget.cornerPoints,
    );

    _scaledPoints =
        rotatedPoints.map((point) {
          double x = point[1] * _scale;
          double y = point[0] * _scale;
          return Offset(x, y);
        }).toList();
    _initialScaledPoints = List<Offset>.from(_scaledPoints);

    for (var point in _scaledPoints) {
      double maxHeight = 424.0;
      double pointMoveUpBy = point.dy - maxHeight;
      if (pointMoveUpBy > _moveUpBy) {
        _moveUpBy = pointMoveUpBy;
      }
    }
    setState(() {});
  }

  void _scaleImage() {
    double newMoveUpBy = 0.0;
    for (var point in _scaledPoints) {
      double maxHeight = 424.0;
      double pointMoveUpBy = point.dy - maxHeight;
      if (pointMoveUpBy > newMoveUpBy) {
        newMoveUpBy = pointMoveUpBy;
      }
    }

    double changeUp = newMoveUpBy - _moveUpBy;
    if (mounted) {
      if (changeUp.isNegative || changeUp > 25) {
        _moveUpBy += changeUp / 60;
        setState(() {});
      }
    }
  }

  Future<void> _initZoom() async {
    final file = File(widget.imagePath);
    final bytes = file.readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _magnifierImage = frameInfo.image;
        _magnifierImageLoading = false;
        _moveUpBy;
      });
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
          title: Text("Discard Corner Adjustments"),
          content: Text(
            "Are you sure you want to discard your corner adjustments?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Discard", style: TextStyle(color: Colors.red)),
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
    double scale = (_displayHeigth - _moveUpBy) / _displayHeigth;
    Rect cropRect =
        _scaledPoints.isNotEmpty && _currentCorner != null && _screenWidth != 0
            ? Rect.fromCenter(
              center: Offset(
                _scaledPoints[_currentCorner!].dx / _scale,
                _scaledPoints[_currentCorner!].dy / _scale,
              ),
              width: _circleSize / scale / _screenWidth * _imagePixelWidth,
              height: _circleSize / scale / _screenWidth * _imagePixelWidth,
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
        appBar: AppBar(title: const Text("Adjust Corners")),
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
                child:
                    !_magnifierImageLoading && _currentCorner != null
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
              _displayHeigth != 0
                  ? Transform.translate(
                    offset: Offset(
                      0,
                      ((scale * _displayHeigth - _displayHeigth) / 2),
                    ),
                    child: Transform.scale(
                      scale: scale,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Center(child: Image.file(File(widget.imagePath))),
                          _draggableCornersOverlay(scale),
                        ],
                      ),
                    ),
                  )
                  : SizedBox(),
            ],
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.all(8.0),
          child: FloatingActionButton(
            heroTag: "saveCorners",
            onPressed: () {
              for (var (i, scaledPoint) in _scaledPoints.indexed) {
                widget.cornerPoints[i] = [
                  (scaledPoint.dy / _scale).toInt(),
                  (scaledPoint.dx / _scale).toInt(),
                ];
              }
              widget.pagePreviewState.reprocessPhoto(
                newCornerPoints: widget.cornerPoints,
              );
              _allowPop = true;
              Navigator.pop(context);
            },
            tooltip: 'Save adjusted Corners',
            child: Icon(Icons.check),
          ),
        ),
      ),
    );
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
      _initZoom();
    }
  }

  Widget _draggableCornersOverlay(double counterScale) {
    if (_screenWidth == 0) {
      return SizedBox();
    }

    return Center(
      child: SizedBox(
        key: _imageAreaKey,
        width: _screenWidth,
        height: _displayHeigth,
        child: Stack(
          children: [
            // dark frame
            CustomPaint(
              size: Size(_screenWidth, _displayHeigth),
              painter: _MiddleLinePainter(
                points: _scaledPoints,
                color: Colors.black38,
                strokeWidth: 7.0 / counterScale,
                normalizedOffset: true,
                offset: _circleSize / counterScale / 2 + 2,
              ),
            ),

            // Draggable corner points
            ..._scaledPoints.asMap().entries.map((entry) {
              final index = entry.key;
              final offset = entry.value;

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

                    // limit position
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
                  child: Container(
                    width: _circleSize / counterScale,
                    height: _circleSize / counterScale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black12,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              );
            }),
            // sharp corners
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: _CornerLinePainter(
                  points: _scaledPoints,
                  strokeWidth: 1.0 / counterScale,
                  offset: 50,
                  normalizedOffset: true,
                ),
              ),
            ),
            // sharp middle section
            IgnorePointer(
              child: CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: _MiddleLinePainter(
                  points: _scaledPoints,
                  color: Colors.white,
                  strokeWidth: 1.0,
                  offset: 0.55,
                  normalizedOffset: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    final clipPath =
        Path()..addOval(Rect.fromCircle(center: center, radius: radius));
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
    this.color = Colors.white,
    this.strokeWidth = 1.0,
    // ignore: unused_element_parameter
    this.colorBg = Colors.black45,
    // ignore: unused_element_parameter
    this.strokeWidthBg = 3.0,
    required this.currentCorner,
    required this.zoomSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cornerPoints.length < 4) return;
    final double radius = zoomSize / 2;

    final paintBg =
        Paint()
          ..color = colorBg
          ..strokeWidth = strokeWidthBg
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;

    final paint =
        Paint()
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

Future<bool> _pagesPopup(
  BuildContext callContext,
  List<int> pageIndexes,
  PopUpType type,
  int docIndex, {
  int? versionIndex,
}) async {
  bool confirmDelete = false;
  final bool isDocument = pageIndexes.isEmpty;
  late List<String> imagePaths;
  late int pagesCount;
  // version
  if (versionIndex != null && pageIndexes.length == 1) {
    if (type == PopUpType.delete) {
      imagePaths =
          (await g.filesHelper.getImagePathsForPage(
            docIndex,
            pageIndexes.first,
          )).$1;
    } else {
      imagePaths = [
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
    imagePaths = thumbs.$1;
    pagesCount = thumbs.$2;
  }
  final bool isSinglePage = pagesCount == 1;
  bool allPagesLoaded = !imagePaths.any((element) => element.isEmpty);

  bool docUnlocked = false;
  bool pageUnlocked = false;
  if (isDocument || !isSinglePage) {
    docUnlocked = await g.metadataHelper.readDocUnlocked(docIndex);
  } else if (isSinglePage && versionIndex != null) {
    pageUnlocked = await g.metadataHelper.readPageUnlocked(
      docIndex,
      pageIndexes.first,
    );
  }

  await showDialog(
    // ignore: use_build_context_synchronously
    context: callContext,
    builder: (BuildContext context) {
      return ValueListenableBuilder<NotifierEvent>(
        valueListenable: (globalNotifier as ValueListenable<NotifierEvent>),
        builder: (context, event, _) {
          if (event == NotifierEvent.loadDocsThumbnails ||
              event == NotifierEvent.loadPagesThumbnails) {
            if (versionIndex != null && pageIndexes.length == 1) {
              Future.microtask(() async {
                imagePaths = [
                  await g.filesHelper.getVersionPath(
                    docIndex,
                    pageIndexes.first,
                    versionIndex,
                  ),
                ];
                allPagesLoaded = !imagePaths.any((element) => element.isEmpty);
              });
            } else {
              Future.microtask(() async {
                var thumbs = await g.filesHelper.getPagesThumbnails(
                  docIndex,
                  pageIndexes: pageIndexes,
                  fullSized: true,
                );
                imagePaths = thumbs.$1;
                allPagesLoaded = !imagePaths.any((element) => element.isEmpty);
              });
            }
          }
          String sAction =
              type == PopUpType.share
                  ? "Share"
                  : type == PopUpType.save
                  ? "Save"
                  : "Delete";
          String sObject =
              isDocument
                  ? "Document ${docIndex + 1}"
                  : "${isSinglePage ? "" : "$pagesCount "}"
                      "Page${isSinglePage ? "" : "s"} ${isSinglePage ? "${pageIndexes.first + 1}"
                              "${versionIndex != null && type != PopUpType.delete ? ", \n${versionNames[versionIndex]}" : ""}" : ""}";
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: Text("$sAction $sObject"),

                actions: [
                  ImagesScrollPreview(pagePaths: imagePaths),
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
                              child: Text("Processing images..."),
                            ),
                          ],
                        ),
                      )
                      : SizedBox(),
                  type == PopUpType.delete
                      ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Are you sure you want to \npermanently delete ${isDocument ? ""
                                  "this document" : ""
                                  "${isSinglePage ? "this " : "these $pagesCount "}"
                                  "page${isSinglePage ? "" : "s"}"}?",
                        ),
                      )
                      : SizedBox(),
                  SizedBox(height: 24.0),

                  type == PopUpType.delete
                      ? SizedBox()
                      : Container(
                        decoration:
                            (g.proUnlocked == true ||
                                    pageUnlocked ||
                                    versionIndex != 3)
                                ? null
                                : BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [smallBoxShadow(context)],
                                ),
                        child: Column(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Image
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal:
                                        (g.proUnlocked == true ||
                                                pageUnlocked ||
                                                versionIndex != 3)
                                            ? 0
                                            : 4,
                                  ),
                                  // Image Export
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        allPagesLoaded &&
                                                (g.proUnlocked == true ||
                                                    pageUnlocked ||
                                                    versionIndex != 3)
                                            ? () async {
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
                                    label: Text(
                                      "${type == PopUpType.share ? "Share" : /*type == PopUpType.save
                                      ?*/ "Save"} Image${isSinglePage ? "" : "s"} "
                                      "${type == PopUpType.save ? "to Gallery" : ""}",
                                    ),
                                  ),
                                ),

                                // PDF
                                SizedBox(
                                  height:
                                      (g.proUnlocked == true ||
                                              (docUnlocked && !isSinglePage) ||
                                              isSinglePage)
                                          ? 0
                                          : 4,
                                ),
                                Container(
                                  decoration:
                                      (g.proUnlocked == true ||
                                              (docUnlocked &&
                                                  (isDocument ||
                                                      !isSinglePage)) ||
                                              isSinglePage)
                                          ? null
                                          : BoxDecoration(
                                            color:
                                                Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            boxShadow: [
                                              smallBoxShadow(context),
                                            ],
                                          ),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal:
                                              (g.proUnlocked == true ||
                                                      (docUnlocked &&
                                                          (isDocument ||
                                                              !isSinglePage)) ||
                                                      (pageUnlocked ||
                                                          versionIndex != 3 &&
                                                              isSinglePage))
                                                  ? 0
                                                  : 4,
                                        ),
                                        // PDF Export
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              allPagesLoaded &&
                                                      (g.proUnlocked == true ||
                                                          (docUnlocked &&
                                                              (isDocument ||
                                                                  !isSinglePage)) ||
                                                          (pageUnlocked ||
                                                              versionIndex !=
                                                                      3 &&
                                                                  isSinglePage))
                                                  ? () async {
                                                    Navigator.pop(context);
                                                    Future? afterExport;
                                                    switch (type) {
                                                      case PopUpType.share:
                                                        afterExport = g
                                                            .filesHelper
                                                            .shareImagesPdf(
                                                              context,
                                                              docIndex,
                                                              pageIndexes:
                                                                  pageIndexes,
                                                              versionIndex:
                                                                  versionIndex,
                                                            );
                                                        break;
                                                      case PopUpType.save:
                                                        afterExport = g
                                                            .filesHelper
                                                            .pickFolderForImagesPdf(
                                                              docIndex,
                                                              context,
                                                              pageIndexes:
                                                                  pageIndexes,
                                                              versionIndex:
                                                                  versionIndex,
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
                                          label: Text(
                                            "${type == PopUpType.share ? "Share" : /*type == PopUpType.save
                                      ?*/ "Save"} ${isSinglePage ? "" : "combined "}PDF"
                                            "${type == PopUpType.save ? " to Directory" : ""}",
                                          ),
                                        ),
                                      ),
                                      (g.proUnlocked == true ||
                                              (docUnlocked && !isSinglePage) ||
                                              isSinglePage)
                                          ? SizedBox()
                                          : Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              10,
                                              0,
                                              10,
                                              6,
                                            ),
                                            child: Column(
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: () async {
                                                    proPopup(context);
                                                  },
                                                  icon: Icon(Icons.lock),
                                                  label: Text("Unlock PRO"),
                                                ),
                                                (isDocument || !isSinglePage)
                                                    ? ElevatedButton.icon(
                                                      onPressed: () async {
                                                        docUnlocked =
                                                            await _unlockDocumentWithAd(
                                                              context,
                                                            );
                                                        setStateDialog(() {});
                                                        await g.metadataHelper
                                                            .writeDocUnlocked(
                                                              docIndex,
                                                              docUnlocked,
                                                            );
                                                      },
                                                      icon: Icon(
                                                        Icons.play_arrow,
                                                      ),
                                                      label: Text("Watch Ad"),
                                                    )
                                                    : SizedBox(),
                                              ],
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // Unlock PRO
                            (g.proUnlocked == true ||
                                    pageUnlocked ||
                                    versionIndex != 3)
                                ? SizedBox()
                                : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    0,
                                    10,
                                    6,
                                  ),
                                  child: Column(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          proPopup(context);
                                        },
                                        icon: Icon(Icons.lock),
                                        label: Text("Unlock PRO"),
                                      ),
                                      (isSinglePage && versionIndex != null)
                                          ? ElevatedButton.icon(
                                            onPressed: () async {
                                              pageUnlocked =
                                                  await _unlockPageWithAd(
                                                    context,
                                                  );
                                              setStateDialog(() {});
                                              await g.metadataHelper
                                                  .writePageUnlocked(
                                                    docIndex,
                                                    pageIndexes.first,
                                                    pageUnlocked,
                                                  );
                                              globalNotifier.triggerEvent(
                                                NotifierEvent.setState,
                                              );
                                            },
                                            icon: Icon(Icons.play_arrow),
                                            label: Text("Watch Ad"),
                                          )
                                          : SizedBox(),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cancel Button
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Cancel"),
                      ),
                      type == PopUpType.delete
                          ? Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ElevatedButton(
                              onPressed: () {
                                confirmDelete = true;
                                g.filesHelper.deleteImages(
                                  context,
                                  docIndex,
                                  pageIndexes: pageIndexes,
                                );
                                Navigator.pop(context);
                              },
                              child: Text(
                                "Delete",
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
  return confirmDelete;
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
      builder:
          (context) => AlertDialog(
            title: Text('Camera Permission Needed'),
            content: Text(
              'Please enable camera access from your device settings.',
            ),
            actions: [
              TextButton(
                child: Text('Cancel'),
                onPressed: () {
                  Navigator.pop(context, false);
                },
              ),
              ElevatedButton(
                child: Text('Open Settings'),
                onPressed: () {
                  openAppSettings();
                  Navigator.pop(context, true);
                },
              ),
            ],
          ),
    );
    if (settingsOpened != true && mounted && context.mounted) {
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
      dev.log("Error taking photo: $e");
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
      builder:
          (_) => StatefulBuilder(
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
          title: Text("Discard Photos"),
          content: Text(
            "Are you sure you want to discard the photos that you have taken?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Discard", style: TextStyle(color: Colors.red)),
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
          if (await _leaveConfirmationDialog() && mounted && context.mounted) {
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
            tooltip: 'Close Camera',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            CustomIconButton(
              tooltip: 'Process Photos',
              isDisabled: _capturedImages.isEmpty,
              onTap: () {
                allowPop = true;
                Navigator.pop(context, _capturedImages);
              },
              color: Theme.of(context).colorScheme.primaryContainer,
              icon: Icons.check,
              iconColor: Theme.of(context).colorScheme.onPrimaryContainer,
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
                    tooltip: _isFlashOn ? 'Disable Flash' : 'Enable Flash',
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
                      color:
                          _isPressingCaptureButton || _cameraFlash
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
                          color:
                              _isPressingCaptureButton || _cameraFlash
                                  ? Colors.transparent
                                  : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                Tooltip(
                  message: 'Preview Photos',
                  child: ThumbnailWithBadge(
                    image:
                        _capturedImages.isNotEmpty
                            ? File(_capturedImages.first.path)
                            : null,
                    count: _capturedImages.length,
                    onTap:
                        _capturedImages.isEmpty
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
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Delete Photo',
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
              //        tooltip: 'Delete Photo',
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

    final paint =
        Paint()
          ..color = Colors.white
          ..strokeWidth = crossThickness;
    final paintBg =
        Paint()
          ..color = Colors.black.withAlpha(70)
          ..strokeWidth = crossThickness + 2 * bgThickness;
    final paintBg2 =
        Paint()
          ..color = Colors.black.withAlpha(14)
          ..strokeWidth = crossThickness + 2 * bgThickness2;
    final paintBg3 =
        Paint()
          ..color = Colors.black.withAlpha(5)
          ..strokeWidth = crossThickness + 2 * bgThickness3;
    final paintBg4 =
        Paint()
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
              image:
                  image != null
                      ? DecorationImage(
                        image: FileImage(image!),
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
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white, //Theme.of(context).colorScheme.
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
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
  late Future<void> _loadFuture;
  AdsHelper() {
    _loadFuture = _loadRewardAd();
  }

  RewardedAd? _rewardAd;
  bool _isAdLoaded = false;

  Future<void> _loadRewardAd() async {
    final completer = Completer<void>();
    RewardedAd.load(
      adUnitId: "ca-app-pub-6739996186409182/8967462940",
      request: AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardAd = ad;
          _isAdLoaded = true;

          _rewardAd?.fullScreenContentCallback = FullScreenContentCallback(
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
          dev.log("Error: Failed to load reward ad: $error");
          Fluttertoast.showToast(msg: "Error: Failed to load ad.");
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<bool> showRewardAd() async {
    await _loadFuture;
    final completer = Completer<void>();
    bool watachedAd = false;
    if (_isAdLoaded && _rewardAd != null) {
      _rewardAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          dev.log('User earned reward: ${reward.type}'); //${reward.amount}
          //Fluttertoast.showToast(msg: "User earned reward: ${reward.type}");
          watachedAd = true;
          completer.complete();
        },
      );
    } else {
      dev.log("Error: Ad not loaded yet.");
      Fluttertoast.showToast(msg: "Error: Ad not loaded.");
      completer.complete();
    }
    await completer.future;
    return watachedAd;
  }
}
