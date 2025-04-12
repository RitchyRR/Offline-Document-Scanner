// design:
import 'package:docscanner/image_prosessing_manager.dart';
import 'package:docscanner/opencv_helper.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
// function:
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // Timer
import 'dart:convert'; // json
import 'dart:developer' as dev;
// my packages:
import 'package:docscanner/files_helper.dart';

// global variables:
final GlobalNotifier globalNotifier = GlobalNotifier();
final ImageProcessingManager imageProcessingManager = ImageProcessingManager();
final FilesHelper filesHelper = FilesHelper();

enum NotifierEvent {
  loadPagesThumbnails,
  loadDocsThumbnails,
  loadPageVersions,
  loadPageMetadata,
  pictureSaved,
  warpSaved,
  processed1Saved,
  processed2Saved,
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    //DeviceOrientation.portraitDown,
  ]);
  runApp(ChangeNotifierProvider.value(value: globalNotifier, child: MyApp()));
}

class GlobalNotifier extends ValueNotifier<NotifierEvent?> {
  GlobalNotifier() : super(null);

  void triggerEvent(NotifierEvent event) {
    value = event;
    value = null; // reset, so that multiple triggers of the same type can work
  }
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
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        filesHelper.calculateScreenWidth(context);
      } else {
        dev.log("Error, _MyAppState, initAsync(): not mounted");
      }
    });
    initAsync();
  }

  Future<void> initAsync() async {}

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
          title: 'Offline Document Scanner',
          initialRoute: '/',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/':
                return MaterialPageRoute(builder: (_) => MyHomePage());

              case '/pages':
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder: (_) => Pages(docIndex: args['docIndex']),
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

              case '/pages/preview':
                final args = settings.arguments as Map<String, dynamic>;
                return MaterialPageRoute(
                  builder: (context) {
                    Future.microtask(() async {
                      Future<void> future = Navigator.pushNamed(
                        // ignore: use_build_context_synchronously
                        context,
                        '/preview',
                        arguments: {
                          'docIndex': args['docIndex'],
                          'pageIndex': args['pageIndex'],
                        },
                      );
                      future.whenComplete(() async {
                        // evict Preview cache
                        List<String> pageImages = await filesHelper
                            .getImagePathsForPage(
                              args['docIndex'],
                              args['pageIndex'],
                            );
                        for (var path in pageImages) {
                          imageCache.evict(
                            FileImage(File(path)),
                            includeLive: true,
                          );
                        }
                      });
                    });

                    return Pages(docIndex: args['docIndex']);
                  },
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
                return MaterialPageRoute(builder: (_) => MyHomePage());
            }
          },
          builder: FToastBuilder(),
          theme: ThemeData(
            colorScheme: lightTheme,
            useMaterial3: true,
            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                systemNavigationBarColor: Colors.transparent, // Navigation bar
                statusBarColor: Colors.transparent, // Status bar
                statusBarIconBrightness: Brightness.dark,
              ),
            ),
            //cardTheme: CardTheme(color: lightTheme.surfaceContainerHigh),
            popupMenuTheme: PopupMenuThemeData(
              color: lightTheme.primaryContainer,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: darkTheme,
            useMaterial3: true,
            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                systemNavigationBarColor: Colors.transparent, // Navigation bar
                statusBarColor: Colors.transparent, // Status bar
                statusBarIconBrightness: Brightness.light,
              ),
            ),
            cardTheme: CardTheme(color: darkTheme.surfaceContainerHigh),
            popupMenuTheme: PopupMenuThemeData(
              color: darkTheme.primaryContainer,
            ),
          ),
          themeMode: ThemeMode.system, // device controls theme
          home: const MyHomePage(title: 'Documents'),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title});

  final String? title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Future<(int, int)> _processDocument(List<String> picturePaths) async {
    var newDoc = await filesHelper.createNewDocument(picturePaths.length);
    int docIndex = newDoc.$1;
    int firstPageIndex = newDoc.$2;

    imageProcessingManager.processPages(docIndex, 0, picturePaths);

    // Creation Date
    final now = DateTime.now();
    _docDates.add("${now.year}-${now.month}-${now.day}");
    _saveDocDate(docIndex);

    return (docIndex, firstPageIndex);
  }

  Future<void> _openImagePicker(
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
    List<String> picturePaths = await FilesHelper.pickImage(
      source,
      isMultiImage: isMultiImage,
    );
    if (picturePaths.isEmpty) return;

    final newIndexes = await _processDocument(picturePaths);
    int docIndex = newIndexes.$1;
    int firstPageIndex = newIndexes.$2;
    // only open PreviewPage for first page
    _openNewPreviewPage(docIndex, firstPageIndex);
  }

  Future<void> _openNewPreviewPage(int docIndex, int pageIndex) async {
    Future<void> future = Navigator.pushNamed(
      context,
      '/pages/preview',
      arguments: {'docIndex': docIndex, 'pageIndex': pageIndex},
    );
    future.whenComplete(() async {
      _loadDocsDisplay();
    });
  }

  final ImagePicker _picker = ImagePicker();

  List<String> _docThumbnails = [];

  @override
  void initState() {
    super.initState();
    globalNotifier.addListener(_handleGlobalEvent);
    initAsync();
  }

  Future<void> initAsync() async {
    await filesHelper.repairDirectoryStructure();
    _loadDocsDisplay();
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
    super.dispose();
  }

  void _handleGlobalEvent() {
    if (!mounted) return;
    switch (globalNotifier.value) {
      case NotifierEvent.loadDocsThumbnails:
        _loadDocsDisplay();
        break;
      default:
    }
  }

  List<int> _docPageCounts = [];
  final List<String> _docNames = [];
  final List<String> _docDates = [];
  int _docsCount = 0;
  Future<void> _loadDocsDisplay() async {
    // Thumbnails
    var thumbs = await filesHelper.getDocThumbnails();
    List<String> thumbnailPaths = thumbs.$1;
    _docsCount = thumbs.$2;
    // Page Counts
    _docPageCounts = [];
    for (var docIndex = 0; docIndex < thumbnailPaths.length; docIndex++) {
      _docPageCounts.add(await filesHelper.getPagesCount(docIndex));
    }
    // Document Metadata (Names + Dates)
    fixMetadataLengths(thumbnailPaths.length);
    for (int docIndex = 0; docIndex < thumbnailPaths.length; docIndex++) {
      final docPath = await filesHelper.getDocumentPath(docIndex);
      final metaDataPath = File('$docPath/metadata.json');

      if (await metaDataPath.exists()) {
        try {
          String content = await metaDataPath.readAsString();
          Map<String, dynamic> metadata = jsonDecode(content);

          _docNames[docIndex] = metadata["name"] ?? "";
          _docDates[docIndex] = metadata["date"] ?? "";
        } catch (e) {
          dev.log(
            "Error, _refreshDocsDisplay: Reading metadata for doc $docIndex: $e",
          );
        }
      } else {
        _saveDocName(docIndex);
      }
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
  }

  Future<void> _saveDocName(int docIndex) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    if (!Directory(docPath).existsSync()) {
      dev.log(
        "Error, _saveDocName: Trying to save metadata into empty Document $docIndex",
      );
      return;
    }
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
      } catch (e) {
        dev.log("Error,_saveDocName: Reading metadata: $e");
      }
    }

    // Write
    if (!await file.exists()) {
      dev.log("Warning,_saveDocName: Metadata file missing, creating new one");
      metadata = {};
      metadata["date"] = "";
    }
    metadata["name"] = _docNames[docIndex];
    fixMetadataLengths(docIndex + 1);

    await file.writeAsString(jsonEncode(metadata));
  }

  Future<void> _saveDocDate(int docIndex) async {
    final docPath = await filesHelper.getDocumentPath(docIndex);
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
      } catch (e) {
        dev.log("Error reading existing metadata, creating new one: $e");
        metadata["name"] = "";
      }
    }

    fixMetadataLengths(docIndex + 1);
    // Write
    metadata["date"] = _docDates[docIndex];
    await file.writeAsString(jsonEncode(metadata));
  }

  Future<void> _openDocument(int docIndex) async {
    Future<void> future = Navigator.pushNamed(
      context,
      '/pages',
      arguments: {'docIndex': docIndex},
    );
    future.whenComplete(() async {
      _loadDocsDisplay();
    });
  }

  Future<void> _shareDocumentPopup(BuildContext context, int docIndex) async {
    final pThumbs = await filesHelper.getPagesThumbnails(docIndex);
    final List<String> pagePaths = pThumbs.$1;
    final int pagesCount = pThumbs.$2;
    final bool allPagesLoaded = !pagePaths.any((element) => element.isEmpty);

    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Share Document"),
          actions: [
            ImagesScrollPreview(pagePaths: pagePaths),
            SizedBox(height: 36.0),
            !allPagesLoaded
                ? Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 36),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info, color: Colors.red),
                      SizedBox(width: 8.0),
                      SizedBox(
                        width: 190,
                        child: Text(
                          "Try again, when all images are done processing.",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                )
                : Row(),

            // Share as Images
            ElevatedButton.icon(
              onPressed:
                  allPagesLoaded
                      ? () async {
                        Navigator.pop(context); // Close dialog
                        await filesHelper.shareDocumentImages(
                          context,
                          docIndex,
                        );
                      }
                      : null,
              icon: Icon(allPagesLoaded ? Icons.image : Icons.broken_image),
              label: Text(
                "Share ${pagesCount == 1 ? "one Image" : "$pagesCount Images"}",
              ),
            ),

            // Share PDF
            ElevatedButton.icon(
              onPressed:
                  allPagesLoaded
                      ? () async {
                        Navigator.pop(context); // Close dialog
                        await filesHelper.shareDocumentPdf(context, docIndex);
                      }
                      : null,
              icon: Icon(
                allPagesLoaded ? Icons.picture_as_pdf : Icons.broken_image,
              ),
              label: Text("Share combined PDF"),
            ),

            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveDocumentPopup(BuildContext context, int docIndex) async {
    final pThumbs = await filesHelper.getPagesThumbnails(docIndex);
    final List<String> pagePaths = pThumbs.$1;
    final int pagesCount = pThumbs.$2;
    final bool allPagesLoaded = !pagePaths.any((element) => element.isEmpty);

    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Save Document"),
          actions: [
            ImagesScrollPreview(pagePaths: pagePaths),
            SizedBox(height: 36.0),
            !allPagesLoaded
                ? Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 36),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info, color: Colors.red),
                      SizedBox(width: 8.0),
                      SizedBox(
                        width: 190,
                        child: Text(
                          "Try again, when all images are done processing.",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                )
                : Row(),

            // Save as Images
            ElevatedButton.icon(
              onPressed:
                  allPagesLoaded
                      ? () async {
                        Navigator.pop(context);
                        await filesHelper.saveDocumentImagesToGallery(docIndex);
                      }
                      : null,
              icon: Icon(allPagesLoaded ? Icons.image : Icons.broken_image),
              label: Text(
                "Save ${pagesCount == 1 ? "one Image" : "$pagesCount Images"} to Gallery",
              ),
            ),

            // Save as PDF
            ElevatedButton.icon(
              onPressed:
                  allPagesLoaded
                      ? () async {
                        Navigator.pop(context);
                        await filesHelper.pickFolderForDocumentPdf(docIndex);
                      }
                      : null,
              icon: Icon(
                allPagesLoaded ? Icons.picture_as_pdf : Icons.broken_image,
              ),
              label: Text("Save combined PDF to Directory"),
            ),

            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteDocumentPopup(BuildContext context, int docIndex) async {
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Delete Document"),
          content: Text(
            "Are you sure you want to permanently delete this document?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (confirmDelete == true) {
      await filesHelper.deleteDocument(docIndex);
      _loadDocsDisplay();
    }
  }

  // Documents
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Documents")),
      body:
          _docThumbnails.isNotEmpty
              // Documents Cards
              ? ListView.builder(
                itemCount: _docsCount,
                itemBuilder: (BuildContext context, int index) {
                  String docName =
                      _docNames[index].isNotEmpty
                          ? _docNames[index]
                          : "Document ${index + 1}";
                  String creationDate = _docDates[index];
                  int pagesCount =
                      _docPageCounts.isNotEmpty ? _docPageCounts[index] : -1;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2.0,
                      child: SizedBox(
                        height: 160.0 * 1.414,
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
                                      onTap: () async {
                                        int?
                                        selectedIndex = await showDialog<int>(
                                          context: context,
                                          builder: (BuildContext context) {
                                            int currentIndex = index;
                                            TextEditingController
                                            nameController =
                                                TextEditingController(
                                                  text: _docNames[index],
                                                );

                                            return AlertDialog(
                                              title: Text("Edit Document"),
                                              content: StatefulBuilder(
                                                builder: (context, setState) {
                                                  return Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      // TextField for custom document name
                                                      TextField(
                                                        controller:
                                                            nameController,
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              "Document Name",
                                                          hintText:
                                                              "Document ${index + 1}",
                                                        ),
                                                        clipBehavior:
                                                            Clip.hardEdge,
                                                        onChanged:
                                                            (value) => setState(
                                                              () {
                                                                nameController
                                                                        .text =
                                                                    value;
                                                              },
                                                            ),
                                                      ),
                                                      SizedBox(height: 16),
                                                      // Dropdown for changing the index
                                                      DropdownButtonFormField<
                                                        int
                                                      >(
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              "Change Document Index",
                                                        ),
                                                        value: currentIndex,
                                                        isExpanded: true,
                                                        items: List.generate(
                                                          _docThumbnails.length,
                                                          (
                                                            i,
                                                          ) => DropdownMenuItem(
                                                            value: i,
                                                            child: Text(
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              (i == index)
                                                                  ? (nameController
                                                                          .text
                                                                          .trim()
                                                                          .isNotEmpty)
                                                                      ? nameController
                                                                          .text
                                                                          .trim()
                                                                      : "Document ${i + 1}"
                                                                  : _docNames[i]
                                                                      .isNotEmpty
                                                                  ? _docNames[i]
                                                                  : "Document ${i + 1}",
                                                            ),
                                                          ),
                                                        ),
                                                        onChanged: (
                                                          int? newValue,
                                                        ) {
                                                          if (newValue !=
                                                              null) {
                                                            setState(
                                                              () =>
                                                                  currentIndex =
                                                                      newValue,
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        context,
                                                      ), // Close popup
                                                  child: Text("Cancel"),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    // Save changes and close
                                                    setState(() {
                                                      _docNames[index] =
                                                          nameController.text
                                                              .trim();
                                                    });
                                                    _saveDocName(index);
                                                    Navigator.pop(
                                                      context,
                                                      currentIndex,
                                                    );
                                                  },
                                                  child: Text("OK"),
                                                ),
                                              ],
                                            );
                                          },
                                        );

                                        // Handle the result after the popup closes
                                        if (selectedIndex != null &&
                                            selectedIndex != index) {
                                          await filesHelper.changeDocumentIndex(
                                            index,
                                            selectedIndex,
                                          );
                                          _loadDocsDisplay();
                                        }
                                      },
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
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Save Button
                                      IconButton(
                                        onPressed:
                                            () => _saveDocumentPopup(
                                              context,
                                              index,
                                            ),
                                        icon: Icon(Icons.save),
                                      ),
                                      IconButton(
                                        onPressed:
                                            () => _shareDocumentPopup(
                                              context,
                                              index,
                                            ),
                                        icon: Icon(Icons.share),
                                      ),
                                      // Delete Button with Confirmation Dialog
                                      IconButton(
                                        onPressed:
                                            () => _deleteDocumentPopup(
                                              context,
                                              index,
                                            ),
                                        icon: Icon(Icons.delete),
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
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: [bigBoxShadow(context)],
                                ),
                                child: Stack(
                                  children: [
                                    (_docThumbnails[index].isNotEmpty)
                                        ? Image.file(
                                          File(_docThumbnails[index]),
                                          fit: BoxFit.cover,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return const Icon(
                                              Icons.broken_image,
                                            );
                                          },
                                        )
                                        : AspectRatio(
                                          aspectRatio: 1.0 / 1.414,
                                          child: Builder(
                                            builder: (context) {
                                              return Material(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.surfaceBright,
                                                child:
                                                    IndicatorProcessingImage(),
                                              );
                                            },
                                          ),
                                        ),
                                    Positioned.fill(
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => _openDocument(index),
                                          splashColor: Colors.black26,
                                          highlightColor: Colors.black26,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ), // Pages Skeleton
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )
              : const Center(
                child: Text(
                  textAlign: TextAlign.center,
                  'To add a new document,\nuse the floating buttons\nin the bottom right corner.',
                ),
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
                heroTag: "pickImage",
                onPressed: () {
                  _openImagePicker(ImageSource.gallery, isMultiImage: true);
                },
                tooltip: 'Pick multiple Images from Gallery',
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
                heroTag: "pickImages",
                onPressed: () {
                  _openImagePicker(ImageSource.gallery);
                },
                tooltip: 'Pick an Image from Gallery',
                child: const Icon(Icons.photo),
              ),
            ),
            SizedBox(height: 18.0),
            if (_picker.supportsImageSource(ImageSource.camera))
              FloatingActionButton(
                heroTag: "makePhoto",
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

class ImagesScrollPreview extends StatelessWidget {
  const ImagesScrollPreview({super.key, required this.pagePaths});

  final List<String> pagePaths;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
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
                    decoration: BoxDecoration(boxShadow: [smallBoxShadow()]),
                    child: Image.file(
                      File(path),
                      height: 160.0 * 1.414,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.broken_image);
                      },
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
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

class _PagesState extends State<Pages> {
  final ImagePicker _picker = ImagePicker();
  List<String> _pageThumbnails = [];
  int _pagesCount = 0;
  final List<double?> _thumbnailHeights = [];
  final List<GlobalKey> _imageKeys = [];

  @override
  void initState() {
    super.initState();
    globalNotifier.addListener(_handleGlobalEvent);
    _loadPagesThumbnails(onInit: true);
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
    super.dispose();
  }

  void _handleGlobalEvent() {
    if (!mounted) return;
    switch (globalNotifier.value) {
      case NotifierEvent.loadPagesThumbnails:
        _loadPagesThumbnails();
        break;
      default:
    }
  }

  Future<void> _loadPagesThumbnails({bool onInit = false}) async {
    var thumbs = await filesHelper.getPagesThumbnails(widget.docIndex);
    List<String> thumbnailPaths = thumbs.$1;
    _pagesCount = thumbs.$2;

    if (thumbnailPaths.isEmpty) {
      if (!onInit && mounted && context.mounted) {
        Navigator.pop(context);
      }
    } else {
      if (_pageThumbnails != thumbnailPaths) {
        _thumbnailHeights.clear();
      }
      int tooShortBy = thumbnailPaths.length - _thumbnailHeights.length;
      for (var i = 0; i < tooShortBy; i++) {
        _thumbnailHeights.add(null);
        _imageKeys.add(GlobalKey());
      }
      if (mounted) {
        setState(() {
          _pageThumbnails = thumbnailPaths;
        });
      }
    }
  }

  Future<void> _openPreviewPage(int docIndex, int pageIndex) async {
    Future<void> future = Navigator.pushNamed(
      context,
      '/preview',
      arguments: {'docIndex': docIndex, 'pageIndex': pageIndex},
    );
    future.whenComplete(() async {
      // evict Preview cache
      List<String> pageImages = await filesHelper.getImagePathsForPage(
        docIndex,
        pageIndex,
      );
      for (var path in pageImages) {
        imageCache.evict(FileImage(File(path)), includeLive: true);
      }
    });
  }

  Future<void> _openImagePicker(
    ImageSource source, {
    bool isMultiImage = false,
  }) async {
    List<String> picturePaths = await FilesHelper.pickImage(
      source,
      isMultiImage: isMultiImage,
    );
    if (picturePaths.isEmpty) return;

    int firstPageIndex = await _processNewPages(picturePaths);

    // Only open PreviewPage for first page
    _openPreviewPage(widget.docIndex, firstPageIndex);
  }

  Future<int> _processNewPages(List<String> picturePaths) async {
    int firstPageIndex = await filesHelper.reserveNewPagesInDocment(
      widget.docIndex,
      picturePaths.length,
    );

    imageProcessingManager.processPages(
      widget.docIndex,
      firstPageIndex,
      picturePaths,
    );

    return firstPageIndex;
  }

  // Pages
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Document ${widget.docIndex + 1}")),
      body:
          _pageThumbnails.isNotEmpty
              // Pages
              ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: Scrollbar(
                  thumbVisibility: true,
                  interactive: true,
                  trackVisibility: false,
                  thickness: 9.0,
                  radius: Radius.circular(4.0),
                  child: ListView.builder(
                    //cacheExtent: 1000,
                    itemCount: _pagesCount,
                    itemBuilder: (BuildContext context, int index) {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [bigBoxShadow(context)],
                          ),
                          child: Stack(
                            children: [
                              // Sized Box for if image disappears from memory management
                              if (_thumbnailHeights.length > index &&
                                  _thumbnailHeights[index] != null)
                                SizedBox(height: _thumbnailHeights[index]),
                              // Load and measure the image
                              (_pageThumbnails[index].isNotEmpty)
                                  ? MeasureSize(
                                    key: _imageKeys[index],
                                    onChange: (size) {
                                      setState(() {
                                        _thumbnailHeights[index] = size.height;
                                      });
                                    },
                                    child: Image.file(
                                      File(_pageThumbnails[index]),
                                      fit: BoxFit.cover,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return const Icon(Icons.broken_image);
                                      },
                                    ),
                                  )
                                  // Pages Skeleton
                                  : _thumbnailHeights[index] != null
                                  ? SizedBox(
                                    height: _thumbnailHeights[index],
                                    child: Material(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceBright,
                                      child: Center(
                                        child: IndicatorProcessingImage(),
                                      ),
                                    ),
                                  )
                                  : AspectRatio(
                                    aspectRatio: 1.0 / 1.414,
                                    child: Material(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceBright,
                                      child: IndicatorProcessingImage(),
                                    ),
                                  ),
                              // Open PreviewPage
                              Positioned.fill(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap:
                                        (_pageThumbnails[index].isNotEmpty)
                                            ? () => _openPreviewPage(
                                              widget.docIndex,
                                              index,
                                            )
                                            : null,
                                    splashColor: Colors.black26,
                                    highlightColor: Colors.black26,
                                  ),
                                ),
                              ),
                              // Page Index Indicator
                              Positioned(
                                top: 18,
                                left: 12,
                                child: GestureDetector(
                                  // Change Page Index Dialog
                                  onTap: () async {
                                    int? selectedIndex = await showDialog<int>(
                                      context: context,
                                      builder: (BuildContext context) {
                                        int currentIndex = index;
                                        return AlertDialog(
                                          title: Text("Change Page Index"),
                                          content: StatefulBuilder(
                                            builder: (context, setState) {
                                              return DropdownButton<int>(
                                                value: currentIndex,
                                                items: List.generate(
                                                  _pageThumbnails.length,
                                                  (i) => DropdownMenuItem(
                                                    value: i,
                                                    child: Text(
                                                      "Page ${i + 1}",
                                                    ),
                                                  ),
                                                ),
                                                onChanged: (int? newValue) {
                                                  if (newValue != null) {
                                                    setState(
                                                      () =>
                                                          currentIndex =
                                                              newValue,
                                                    );
                                                  }
                                                },
                                              );
                                            },
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(context),
                                              child: Text("Cancel"),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(
                                                  context,
                                                  currentIndex,
                                                );
                                              },
                                              child: Text("OK"),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (selectedIndex != null &&
                                        selectedIndex != index) {
                                      await filesHelper.changePageIndex(
                                        widget.docIndex,
                                        index,
                                        selectedIndex,
                                      );
                                      _loadPagesThumbnails();
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceBright,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [smallBoxShadow()],
                                    ),
                                    child: Text(
                                      "${index + 1}/$_pagesCount",
                                      style: TextStyle(
                                        //color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
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
                ),
              )
              : const Center(child: Text('No images to display.')),
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
                heroTag: "pickImage",
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onPressed: () {
                  _openImagePicker(ImageSource.gallery, isMultiImage: true);
                },
                tooltip: 'Pick multiple Images from Gallery',
                child: const Icon(Icons.photo_library),
              ),
            ),
            SizedBox(height: 18.0),
            SizedBox(
              width: 40,
              height: 40,
              child: FloatingActionButton(
                heroTag: "pickImages",
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onPressed: () {
                  _openImagePicker(ImageSource.gallery);
                },
                tooltip: 'Pick an Image from Gallery',
                child: const Icon(Icons.photo),
              ),
            ),
            SizedBox(height: 18.0),
            if (_picker.supportsImageSource(ImageSource.camera))
              FloatingActionButton(
                heroTag: "makePhoto",
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
  static List<String> versionNames = [
    "unprocessed",
    "warped",
    "filetred",
    "PRO",
  ];
  // Widget
  int _selectedVersion = 0;
  List<String> _versionPaths = ["", "", "", ""];
  String _picturePath = "";
  // Reprocessing Parameters
  int? _ratioIndex;
  int? _newRatioIndex;
  int? _orientation;
  int? _newOrientation;
  int _totalRotation = 0;
  // Corner Points
  List<List<int>> _cornerPoints = [];
  int _imagePixelWidth = 0;
  int _imagePixelHeight = 0;
  // Status
  bool _rotationOngoing = false;
  bool _metadataBlocked = true;
  // PageView
  final PageController _pageController = PageController();
  bool _hideOverlay = false;

  @override
  void initState() {
    super.initState();
    globalNotifier.addListener(_handleGlobalEvent);
    _initAsync();
  }

  Future<void> _initAsync() async {
    _versionPaths = await filesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    );
    _picturePath = _versionPaths.first;
    _showAllImages();
    _loadPageMeatadata(supressWarning: true);
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
    FilesHelper.deleteCachedRoatedImages();
    // new thumbnail
    ImageProcessingManager.writePageThumbnailIndex(
      widget.docIndex,
      widget.pageIndex,
      _selectedVersion,
    );
    super.dispose();
  }

  Future<void> _handleGlobalEvent() async {
    if (!mounted) return;
    switch (globalNotifier.value) {
      case NotifierEvent.loadPageVersions:
        _clearPageVersionsCache();
        break;
      case NotifierEvent.loadPageMetadata:
        _loadPageMeatadata();
        break;
      case NotifierEvent.pictureSaved:
        _versionPaths = await filesHelper.getImagePathsForPage(
          widget.docIndex,
          widget.pageIndex,
        );
        _picturePath = _versionPaths.first;
        setState(() => _versionPaths);
        FilesHelper.deleteCachedRoatedImages();
        break;
      case NotifierEvent.warpSaved:
        _versionPaths = await filesHelper.getImagePathsForPage(
          widget.docIndex,
          widget.pageIndex,
        );
        setState(() => _versionPaths);
        break;
      case NotifierEvent.processed1Saved:
        _versionPaths = await filesHelper.getImagePathsForPage(
          widget.docIndex,
          widget.pageIndex,
        );
        setState(() => _versionPaths);
        break;
      case NotifierEvent.processed2Saved:
        _versionPaths = await filesHelper.getImagePathsForPage(
          widget.docIndex,
          widget.pageIndex,
        );
        setState(() => _versionPaths);
        break;
      default:
    }
  }

  _showAllImages() async {
    if (!mounted || _versionPaths.isEmpty) return;
    for (var versionPath in _versionPaths) {
      if (versionPath.isEmpty) return;
    }
    int? versionIndex = await ImageProcessingManager.readPageThumbnailIndex(
      widget.docIndex,
      widget.pageIndex,
    );
    setState(() => _selectedVersion = versionIndex);
    _pageController.jumpToPage(_selectedVersion);
  }

  void _clearPageVersionsCache() {
    for (var path in _versionPaths) {
      imageCache.evict(FileImage(File(path)), includeLive: true);
    }
    imageCache.evict(FileImage(File(_picturePath)), includeLive: true);
  }

  Future<void> _loadPageMeatadata({bool supressWarning = false}) async {
    _newRatioIndex =
        _ratioIndex = await ImageProcessingManager.readPageRatioIndex(
          widget.docIndex,
          widget.pageIndex,
          supressWarning: supressWarning,
        );
    _newOrientation =
        _orientation = await ImageProcessingManager.readPageOrientationIndex(
          widget.docIndex,
          widget.pageIndex,
          supressWarning: supressWarning,
        );
    _loadCornerPoints();
    if (mounted) {
      setState(() {
        _newRatioIndex;
        //dev.log("Updated _newRatioIndex: $_newRatioIndex");
        _newOrientation;
        //dev.log("Updated _newOrientation: $_newOrientation");
        _metadataBlocked = false;
      });
    }
  }

  Future<void> _loadCornerPoints({bool supressWarning = false}) async {
    if (_versionPaths[0].isEmpty) return;
    _cornerPoints = await ImageProcessingManager.readPageCornerPoints(
      widget.docIndex,
      widget.pageIndex,
      supressWarning: supressWarning,
    );
    final image = await decodeImageFromList(
      (File(_versionPaths[0]).readAsBytesSync()),
    );
    _imagePixelWidth = image.width;
    _imagePixelHeight = image.height;
    if (mounted) {
      setState(() {
        _cornerPoints;
        _hideOverlay = false;
      });
    }
  }

  Future<void> _savePagePopup(BuildContext context, int versionIndex) async {
    final String imagePath = _versionPaths[_selectedVersion];
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            "Save Page ${widget.pageIndex + 1}, \n${versionNames[versionIndex]}",
          ),

          actions: [
            ImagesScrollPreview(pagePaths: [imagePath]),
            SizedBox(height: 36.0),
            // Save Image
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                FilesHelper.saveImageToGallery(imagePath);
              },
              icon: Icon(Icons.image),
              label: Text("Save Image to Gallery"),
            ),
            // Save as PDF
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await FilesHelper.pickFolderForImagePdf(
                  imagePath,
                  widget.docIndex,
                  widget.pageIndex,
                  versionName: versionNames[versionIndex],
                );
              },
              icon: Icon(Icons.picture_as_pdf),
              label: Text("Save PDF to Directory"),
            ),

            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sharePagePopup(BuildContext context, int versionIndex) async {
    final String imagePath = _versionPaths[_selectedVersion];
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            "Share Page ${widget.pageIndex + 1}, \n${versionNames[versionIndex]}",
          ),
          actions: [
            ImagesScrollPreview(pagePaths: [imagePath]),
            SizedBox(height: 36.0),
            // Share Image
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await FilesHelper.shareImages([imagePath]);
              },
              icon: Icon(Icons.image),
              label: Text("Share Image"),
            ),

            // Share PDF
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await filesHelper.shareImagesPdf(
                  context,
                  [imagePath],
                  widget.docIndex,
                  widget.pageIndex,
                  versionName: versionNames[versionIndex],
                );
              },
              icon: Icon(Icons.picture_as_pdf),
              label: Text("Share PDF"),
            ),

            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _deletePagePopup(BuildContext context) async {
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Delete Page"),
          content: Text(
            "Are you sure you want to permanently delete this page?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (confirmDelete != null && confirmDelete == true) {
      await filesHelper.deletePage(widget.docIndex, widget.pageIndex);
      return true;
    }
    return false;
  }

  Future<void> _reprocessingSetup() async {
    _metadataBlocked = true;
    _ratioIndex = null; // don't reset _new values, for uninterrupted display
    _orientation = null;
    _totalRotation = 0;
    filesHelper.deleteProcessedVersionsOfPage(
      widget.docIndex,
      widget.pageIndex,
    );
  }

  void _reprocessingCleanup() {
    _versionPaths = ["", "", "", ""];
    _clearPageVersionsCache();
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

  int _imageRetry = 0;
  // Preview Page
  @override
  Widget build(BuildContext context) {
    bool enableFAB0 =
        _versionPaths.first.isNotEmpty &&
        (!_metadataBlocked && !_rotationOngoing);
    bool enableFABs =
        _selectedVersion == 0
            ? enableFAB0
            : _versionPaths[_selectedVersion].isNotEmpty;
    return Scaffold(
      // Top Bar
      appBar: AppBar(
        title: Text('Page ${widget.pageIndex + 1}'),
        actions: [
          PopupMenuButton(
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    //enabled: _imagesLoaded.every((element) => element),
                    value: "del",
                    child: Row(
                      children: [
                        SizedBox(width: 12),
                        Icon(Icons.delete),
                        SizedBox(width: 10),
                        Text("Delete Page"),
                      ],
                    ),
                  ),
                ],
            onSelected: (String value) async {
              switch (value) {
                case "del":
                  bool deleted = await _deletePagePopup(context);
                  if (deleted && mounted && context.mounted) {
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
                      ? 1.0 / commonAspectRatios[_ratioIndex ?? 0].value
                      : commonAspectRatios[_ratioIndex ?? 0].value),
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
            wantKeepAlive: false,
            scrollPhysics: const PageScrollPhysics(),
            itemCount: _versionPaths.length,
            builder: (context, index) {
              // Loading indicator
              if (_versionPaths[index].isEmpty) {
                // Loading indicator
                return PhotoViewGalleryPageOptions.customChild(
                  child: IndicatorProcessingImage(),
                );
              }
              // Picture
              if (index == 0) {
                bool isZoomed = false;
                return PhotoViewGalleryPageOptions.customChild(
                  child: Stack(
                    children: [
                      PhotoView(
                        imageProvider: FileImage(File(_versionPaths[0])),
                        filterQuality: FilterQuality.high,
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: 1.0,
                        key: ValueKey(_imageRetry),
                        errorBuilder: (context, error, stackTrace) {
                          _refreshAfterBrokenImage(index);
                          return IndicatorProcessingImage();
                        },
                        backgroundDecoration: BoxDecoration(
                          color: Colors.transparent,
                        ),
                        scaleStateChangedCallback: (scaleState) async {
                          isZoomed = scaleState != PhotoViewScaleState.initial;
                          if (!isZoomed) {
                            await Future.delayed(Duration(milliseconds: 300));
                          } // delay becuase of zoom animation
                          setState(() => _hideOverlay = isZoomed);
                        },
                      ),
                      // Corner Points
                      (_cornerPoints.isNotEmpty && !_hideOverlay)
                          ? _displayCornerOverlay(context)
                          : SizedBox(),
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
                key: ValueKey(_imageRetry),
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
                  boxShadow: [smallBoxShadow()],
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
                  heroTag: "warpManually",
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onPressed: enableFAB0 ? () => _openWarpManuallyPage() : null,
                  tooltip:
                      enableFAB0
                          ? 'Adjust Corner Points'
                          : 'Waiting for image to load...',
                  backgroundColor:
                      enableFAB0 ? null : Theme.of(context).disabledColor,
                  elevation: enableFAB0 ? null : 0.0,
                  child: Icon(
                    Icons.crop_free,
                    color: enableFAB0 ? null : Theme.of(context).disabledColor,
                  ),
                ),
              )
              : SizedBox(),
          SizedBox(height: 18.0),
          SizedBox(
            width: 40,
            height: 40,
            child: FloatingActionButton(
              heroTag: "sharePageVersion",
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onPressed:
                  enableFABs
                      ? () => _sharePagePopup(context, _selectedVersion)
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
          ),
          SizedBox(height: 18.0),
          FloatingActionButton(
            heroTag: "savePageVersion",
            onPressed:
                enableFABs
                    ? () => _savePagePopup(context, _selectedVersion)
                    : null,
            tooltip: enableFABs ? 'Save Image' : 'Waiting for image to load...',
            backgroundColor:
                enableFABs ? null : Theme.of(context).disabledColor,
            elevation: _selectedVersion < _versionPaths.length ? null : 0.0,
            child: Icon(
              Icons.save,
              color: enableFABs ? null : Theme.of(context).disabledColor,
            ),
          ),
          SizedBox(height: 20.0),
        ],
      ),
      // Thumbnail Bar
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 50),
        child: SizedBox(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedVersion = index);
                  _pageController.jumpToPage(index);
                },
                child: AnimatedContainer(
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
                              width: _selectedVersion == index ? 70 : 50,
                              height: _selectedVersion == index ? 70 : 50,
                              fit: BoxFit.cover,
                              key: ValueKey(_imageRetry),
                              errorBuilder: (context, error, stackTrace) {
                                _refreshAfterBrokenImage(index);
                                return const SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Icon(Icons.broken_image),
                                );
                              },
                            )
                            : Container(
                              width:
                                  _selectedVersion == index && index != 0
                                      ? 70
                                      : 50,
                              height:
                                  _selectedVersion == index && index != 0
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
      imageCache.evict(
        FileImage(File(_versionPaths[index])),
        includeLive: true,
      );
      if (mounted) {
        setState(() {
          _imageRetry = (_imageRetry - 1) * (-1);
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
          _newOrientation = ((_newOrientation ?? 0) - 1) * (-1); // toggle
        });
        _totalRotation = (_totalRotation + rotation) % 360;
        if (_totalRotation == 0) {
          setState(() {
            _versionPaths[0] = _picturePath;
            _rotationOngoing = false;
          });
        } else {
          _versionPaths[0] = await FilesHelper.rotateImageInTmpDir(
            _picturePath,
            _totalRotation,
          );
          if (mounted) {
            setState(() => _rotationOngoing = false);
          }
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
      isDisabled:
          _versionPaths.isEmpty ||
          _versionPaths.first.isEmpty ||
          _metadataBlocked ||
          _rotationOngoing,
      isHidden:
          ((_ratioIndex == _newRatioIndex) &&
              (_orientation == _newOrientation) &&
              _totalRotation == 0),
      tooltip: "Confirm changes",
      onTap: () async {
        await reprocessPicture();
      },
    );
  }

  Future<void> reprocessPicture({List<List<int>>? newCornerPoints}) async {
    if (mounted) {
      setState(() {
        _hideOverlay = true;
      });
    }
    imageProcessingManager.killPrimaryIsolateOfPage(
      widget.docIndex,
      widget.pageIndex,
    );
    newCornerPoints ??= await ImageProcessingManager.readPageCornerPoints(
      widget.docIndex,
      widget.pageIndex,
    );
    // rotate newCornerPoints
    newCornerPoints = rotateCornerPoints(newCornerPoints);

    await ImageProcessingManager.writePageMetadata(
      widget.docIndex,
      widget.pageIndex,
      _newRatioIndex ?? 0,
      _newOrientation ?? 0,
      null,
      newCornerPoints,
    );
    _reprocessingSetup();
    imageProcessingManager.processPage(
      widget.docIndex,
      widget.pageIndex,
      _versionPaths[0], // potentially rotated image
      _newRatioIndex ?? 0,
      _newOrientation ?? 0,
      newCornerPoints,
    );
    _reprocessingCleanup();
  }

  List<List<int>>? rotateCornerPoints(List<List<int>>? cornerPoints) {
    if (cornerPoints == null) return null;

    int quarterTurns = (_totalRotation ~/ 90) % 4;

    // Apply rotation logic to each point
    List<List<int>> rotated =
        cornerPoints.map((p) {
          int row = p[0];
          int col = p[1];

          switch (quarterTurns) {
            case 1: // 90° CW
              return [col, _imagePixelHeight - row];
            case 2: // 180°
              return [_imagePixelHeight - row, _imagePixelWidth - col];
            case 3: // 270° CW
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
    return Container(
      constraints: const BoxConstraints(maxHeight: height, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [smallBoxShadow()],
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
          value: _newRatioIndex,
          items: List.generate(
            commonAspectRatios.length,
            (i) => DropdownMenuItem(
              alignment: Alignment.center,
              value: i,
              child: Text(
                commonAspectRatios[i].name,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          onChanged:
              _versionPaths.first.isEmpty || _metadataBlocked
                  ? null
                  : (int? newValue) {
                    if (newValue != null && newValue != _newRatioIndex) {
                      setState(() => _newRatioIndex = newValue);
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
        boxShadow: [smallBoxShadow()],
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
          value: _newOrientation,
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
                    if (newValue != null && newValue != _newOrientation) {
                      setState(() => _newOrientation = newValue);
                    }
                  },
        ),
      ),
    );
  }

  Widget _displayCornerOverlay(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    // Handle rotation
    int quarterTurns = _totalRotation ~/ 90;
    double scale;
    double displayHeight;
    if (_imagePixelWidth < 1 ||
        !_imagePixelWidth.isFinite ||
        _imagePixelHeight < 1 ||
        !_imagePixelHeight.isFinite) {
      _imagePixelWidth = _imagePixelHeight = 1;
    }
    if (quarterTurns.isEven) {
      scale = screenWidth / _imagePixelWidth;
      displayHeight = _imagePixelHeight * scale;
    } else {
      scale = screenWidth / _imagePixelHeight;
      displayHeight = _imagePixelWidth * scale;
    }

    // Apply rotation to corner points visually
    List<Offset> scaledPoints =
        _cornerPoints.map((point) {
          double x = point[1] * scale;
          double y = point[0] * scale;
          return Offset(x, y);
        }).toList();

    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: screenWidth,
          height: displayHeight,
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(screenWidth, displayHeight),
                  painter: _FrameLinePainter(points: scaledPoints),
                ),
                CustomPaint(
                  size: Size(screenWidth, displayHeight),
                  painter: _CornerLinePainter(
                    points: scaledPoints,
                    strokeWidth: 2.0,
                    offset: 0.1,
                    normalizedOffset: false,
                  ),
                ),
                CustomPaint(
                  size: Size(screenWidth, displayHeight),
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

BoxShadow smallBoxShadow() {
  return BoxShadow(blurRadius: 6, spreadRadius: -4, offset: const Offset(0, 2));
}

class MeasureSize extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onChange;

  const MeasureSize({super.key, required this.child, required this.onChange});

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  final GlobalKey _key = GlobalKey();
  Size _oldSize = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_afterBuild);
  }

  @override
  Widget build(BuildContext context) {
    return Container(key: _key, child: widget.child);
  }

  void _afterBuild(_) {
    final context = _key.currentContext;
    if (context == null) return;

    final newSize = context.size;
    if (newSize != null && newSize != _oldSize) {
      _oldSize = newSize;
      widget.onChange(newSize);
    }
  }
}

class CustomIconButton extends StatelessWidget {
  final VoidCallback? onTap;
  final BoxConstraints constraints;
  final Color color;
  final IconData icon;
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
    this.color = Colors.blue, // Default color if not provided
    this.icon = Icons.check, // Default icon
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
                        boxShadow: isDisabled ? null : [smallBoxShadow()],
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
                                  : null,
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
  List<Offset> _scaledPoints = [];
  double _screenWidth = 0;
  double _displayHeigth = 0;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _initImageDimensions();
  }

  void _initImageDimensions() async {
    final image = await decodeImageFromList(
      (File(widget.imagePath).readAsBytesSync()),
    );
    int imagePixelWidth = image.width;
    int imagePixelHeight = image.height;
    if (mounted) {
      _screenWidth = MediaQuery.of(context).size.width;
    }
    _scale = _screenWidth / imagePixelWidth;
    _displayHeigth = imagePixelHeight * _scale;
    _scaledPoints =
        widget.cornerPoints.map((point) {
          double x = point[1] * _scale;
          double y = point[0] * _scale;
          return Offset(x, y);
        }).toList();

    if (mounted) {
      setState(() {});
    }
  }

  final GlobalKey _imageAreaKey = GlobalKey();
  bool _allowPop = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,

      child: Scaffold(
        body: Scaffold(
          appBar: AppBar(
            title: const Text("Adjust Corners"),
            leading: BackButton(
              onPressed: () {
                _allowPop = true;
                Navigator.pop(context);
              },
            ),
          ),
          body: Scaffold(
            body: Stack(
              alignment: Alignment.center,
              children: [
                Center(child: Image.file(File(widget.imagePath))),
                _draggableCornerOverlay(),
              ],
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
                  widget.pagePreviewState.reprocessPicture(
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
        ),
      ),
    );
  }

  Widget _draggableCornerOverlay() {
    if (_screenWidth == 0) {
      return SizedBox();
    }
    double circleSize = 30;
    int quarterTurns = widget.rotation ~/ 90;

    return Center(
      child: SizedBox(
        key: _imageAreaKey,
        width: _screenWidth,
        height: _displayHeigth,
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: Stack(
            children: [
              // dark frame
              CustomPaint(
                size: Size(_screenWidth, _displayHeigth),
                painter: _MiddleLinePainter(
                  points: _scaledPoints,
                  color: Colors.black38,
                  normalizedOffset: true,
                ),
              ),

              // Draggable corner points
              ..._scaledPoints.asMap().entries.map((entry) {
                final index = entry.key;
                final offset = entry.value;

                return Positioned(
                  left: offset.dx - circleSize / 2,
                  top: offset.dy - circleSize / 2,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final box =
                          _imageAreaKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null) return;

                      Offset localPosition = box.globalToLocal(
                        details.globalPosition,
                      );

                      setState(() {
                        double newX = localPosition.dx.clamp(0.0, _screenWidth);
                        double newY = localPosition.dy.clamp(
                          0.0,
                          _displayHeigth,
                        );
                        _scaledPoints[index] = Offset(newX, newY);
                      });
                    },
                    child: Container(
                      width: circleSize,
                      height: circleSize,
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
                    strokeWidth: 1.0,
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
      ),
    );
  }
}
