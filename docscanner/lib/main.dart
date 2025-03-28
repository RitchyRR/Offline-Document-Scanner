// design:
import 'package:docscanner/image_prosessing_manager.dart';
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
late GlobalNotifier globalNotifier;

enum NotifierEvent {
  loadThumbnails,
  reloadThumbnails,
  loadDocThumbnails,
  reloadDocThumbnails,
}

void main() {
  globalNotifier = GlobalNotifier();
  runApp(ChangeNotifierProvider.value(value: globalNotifier, child: MyApp()));
}

class GlobalNotifier extends ValueNotifier<NotifierEvent?> {
  GlobalNotifier() : super(null);

  void triggerEvent(NotifierEvent event) {
    value = event;
    notifyListeners();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Route _pushPagesThenPreview(int docIndex, int pageIndex) {
    return MaterialPageRoute(
      builder: (context) {
        Future.microtask(() {
          Navigator.pushNamed(
            // ignore: use_build_context_synchronously
            context,
            '/pages',
            arguments: {'docIndex': docIndex},
          ).then((_) {
            Navigator.pushNamed(
              // ignore: use_build_context_synchronously
              context,
              '/preview',
              arguments: {'docIndex': docIndex, 'pageIndex': pageIndex},
            );
          });
        });

        return Pages(docIndex: docIndex);
      },
    );
  }

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
      lightScheme, //.copyWith(
      //  surface: lightScheme.surface,
      //  surfaceContainerLow: lightScheme.surfaceContainerLow.withOpacity(0.9),
      //  primary: lightScheme.primary,
      //  secondary: lightScheme.secondary,
      //),
      darkScheme.copyWith(
        //     surface: darkScheme.surface,
        //     surfaceContainerLow: darkScheme.surfaceContainerLow.withOpacity(0.8),
        //     primary: darkScheme.primary,
        //     secondary: darkScheme.secondary,
        //shadow: Color.fromARGB(255, 0, 0, 0),
      ),
    );
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
                      (_) => PreviewPage(
                        docIndex: args['docIndex'],
                        pageIndex: args['pageIndex'],
                      ),
                );

              case '/pages/preview':
                final args = settings.arguments as Map<String, dynamic>;
                return _pushPagesThenPreview(
                  args['docIndex'],
                  args['pageIndex'],
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
    var newDoc = await FilesHelper.getNewPaths(picturePaths.length);
    List<List<String>> newPaths = newDoc.$1;
    int docIndex = newDoc.$2;
    int firstPageIndex = newDoc.$3;
    // process pages individually
    for (var i = 0; i < picturePaths.length; i++) {
      ImageProcessingManager.processPage(picturePaths[i], newPaths[i]);
    }

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
    await Navigator.pushNamed(
      context,
      '/pages/preview',
      arguments: {'docIndex': docIndex, 'pageIndex': pageIndex},
    );
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
    await FilesHelper.deleteEmptyDirectories();
    _refreshDocsDisplay();
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
    super.dispose();
  }

  void _handleGlobalEvent() {
    if (globalNotifier.value == NotifierEvent.loadDocThumbnails) {
      _refreshDocsDisplay();
    }
    if (globalNotifier.value == NotifierEvent.reloadDocThumbnails) {
      _reloadDocsDisplay();
    }
  }

  List<int> _docPageCounts = [];
  final List<String> _docNames = [];
  final List<String> _docDates = [];
  Future<void> _refreshDocsDisplay() async {
    // Thumbnails
    List<String> thumbnailPaths = await FilesHelper.getDocThumbnails();
    // Page Counts
    _docPageCounts = [];
    for (var docIndex = 0; docIndex < thumbnailPaths.length; docIndex++) {
      _docPageCounts.add(await FilesHelper.getPagesCount(docIndex));
    }
    // Document Metadata (Names + Dates)
    fixMetadataLengths(thumbnailPaths.length);
    for (int docIndex = 0; docIndex < thumbnailPaths.length; docIndex++) {
      final docPath = await FilesHelper.getDocumentPath(docIndex);
      final metaDataPath = File('$docPath/metadata.json');

      if (await metaDataPath.exists()) {
        try {
          String content = await metaDataPath.readAsString();
          Map<String, dynamic> metadata = jsonDecode(content);

          _docNames[docIndex] = metadata["name"] ?? "";
          _docDates[docIndex] = metadata["date"] ?? "";
        } catch (e) {
          dev.log("Error reading metadata for doc $docIndex: $e");
        }
      } else {
        _saveDocName(docIndex);
      }
    }
    // Refresh Display
    setState(() {
      _docThumbnails = thumbnailPaths;
    });
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
    final docPath = await FilesHelper.getDocumentPath(docIndex);
    final file = File('$docPath/metadata.json');
    Map<String, dynamic> metadata = {};

    // Read
    if (await file.exists()) {
      try {
        String content = await file.readAsString();
        metadata = jsonDecode(content).cast<String, String>();
      } catch (e) {
        dev.log("Error reading existing metadata, creating new one: $e");
        metadata["date"] = "";
      }
    }

    fixMetadataLengths(docIndex + 1);
    // Write
    metadata["name"] = _docNames[docIndex];
    await file.writeAsString(jsonEncode(metadata));
  }

  Future<void> _saveDocDate(int docIndex) async {
    final docPath = await FilesHelper.getDocumentPath(docIndex);
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

  Future<void> _reloadDocsDisplay() async {
    dev.log("Reloading page thumbnails.");
    for (var path in _docThumbnails) {
      /*final evictRes = */
      imageCache.evict(FileImage(File(path)), includeLive: true);
      //dev.log("reordering evictRes: $evictRes");
    }
    setState(() {
      _docThumbnails = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDocsDisplay();
    });
  }

  Future<void> _openDocument(int docIndex) async {
    Navigator.pushNamed(context, '/pages', arguments: {'docIndex': docIndex});
  }

  Future<void> _shareDocumentPopup(
    BuildContext context,
    int docIndex,
    int pagesCount,
  ) async {
    final pagePaths = await FilesHelper.getPagesThumbnails(docIndex);
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Share Document"),
          actions: [
            ImagesScrollPreview(pagePaths: pagePaths),
            SizedBox(height: 36.0),
            // Share as Images
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                await FilesHelper.shareDocumentImages(context, docIndex);
              },
              icon: Icon(Icons.image),
              label: Text(
                "Share ${pagesCount == 1 ? "one Image" : "$pagesCount Images"}",
              ),
            ),

            // Share PDF
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                await FilesHelper.shareDocumentPdf(context, docIndex);
              },
              icon: Icon(Icons.picture_as_pdf),
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

  Future<void> _saveDocumentPopup(
    BuildContext context,
    int docIndex,
    int pagesCount,
  ) async {
    final pagePaths = await FilesHelper.getPagesThumbnails(docIndex);
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Save Document"),

          actions: [
            ImagesScrollPreview(pagePaths: pagePaths),
            SizedBox(height: 36.0),
            // Save as Images
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await FilesHelper.saveDocumentImagesToGallery(docIndex);
              },
              icon: Icon(Icons.image),
              label: Text(
                "Save ${pagesCount == 1 ? "one Image" : "$pagesCount Images"} to Gallery",
              ),
            ),

            // Save as PDF
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await FilesHelper.pickFolderForDocumentPdf(docIndex);
              },
              icon: Icon(Icons.picture_as_pdf),
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
      await FilesHelper.deleteDocument(docIndex);
      _reloadDocsDisplay();
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
                itemCount: _docThumbnails.length,
                itemBuilder: (BuildContext context, int index) {
                  String docName =
                      _docNames[index].isNotEmpty
                          ? _docNames[index]
                          : "Document ${index + 1}";
                  String creationDate = _docDates[index];
                  int pagesCount = _docPageCounts[index];
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
                                  InkWell(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12.0),
                                    ),
                                    onTap: () async {
                                      int?
                                      selectedIndex = await showDialog<int>(
                                        context: context,
                                        builder: (BuildContext context) {
                                          int currentIndex = index;
                                          TextEditingController nameController =
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
                                                      CrossAxisAlignment.start,
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
                                                      onChanged:
                                                          (value) => setState(
                                                            () {
                                                              nameController
                                                                      .text =
                                                                  value.trim();
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
                                                            "Swap Document Index",
                                                      ),
                                                      value: currentIndex,
                                                      items: List.generate(
                                                        _docThumbnails.length,
                                                        (i) => DropdownMenuItem(
                                                          value: i,
                                                          child: Text(
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
                                                        if (newValue != null) {
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
                                        await FilesHelper.changeDocumentIndex(
                                          index,
                                          selectedIndex,
                                        );
                                        _reloadDocsDisplay();
                                      }
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Column(
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
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            "Created: $creationDate",
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            "Pages: $pagesCount",
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
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
                                              pagesCount,
                                            ),
                                        icon: Icon(Icons.save),
                                      ),
                                      IconButton(
                                        onPressed:
                                            () => _shareDocumentPopup(
                                              context,
                                              index,
                                              pagesCount,
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
                            Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(
                                      context,
                                    ).shadowColor.withAlpha(125),
                                    blurRadius: 8,
                                    spreadRadius: -2,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Image.file(
                                    File(_docThumbnails[index]),
                                    width: 160.0,
                                    height: 160.0 * 1.414,
                                    fit: BoxFit.cover,
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
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).shadowColor.withAlpha(125),
                          blurRadius: 8,
                          spreadRadius: -2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Image.file(
                      File(path),
                      height: 160.0 * 1.414,
                      fit: BoxFit.contain,
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
  final List<double?> _thumbnailHeights = [];
  final List<GlobalKey> _imageKeys = [];

  @override
  void initState() {
    super.initState();
    globalNotifier.addListener(_handleGlobalEvent);
    _loadPageThumbnails();
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
    super.dispose();
  }

  void _handleGlobalEvent() {
    if (globalNotifier.value == NotifierEvent.loadThumbnails) {
      _loadPageThumbnails();
    } else if (globalNotifier.value == NotifierEvent.reloadThumbnails) {
      _reloadPageThumbnails();
    }
  }

  Future<void> _loadPageThumbnails() async {
    // ignore: unused_local_variable
    List<String> thumbnailPaths = await FilesHelper.getPagesThumbnails(
      widget.docIndex,
    ).then((thumbnailPaths) {
      if (thumbnailPaths.isEmpty) {
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
      }
      int tooShortBy = thumbnailPaths.length - _thumbnailHeights.length;
      for (var i = 0; i < tooShortBy; i++) {
        _thumbnailHeights.add(null);
        _imageKeys.add(GlobalKey());
      }
      setState(() {
        _pageThumbnails = thumbnailPaths;
      });
      return thumbnailPaths;
    });
  }

  Future<void> _reloadPageThumbnails() async {
    dev.log("Reloading page thumbnails.");
    for (var path in _pageThumbnails) {
      /*final evictRes = */
      imageCache.evict(FileImage(File(path)), includeLive: true);
      //dev.log("reordering evictRes: $evictRes");
    }
    setState(() {
      _pageThumbnails = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPageThumbnails();
    });
  }

  Future<void> _openPreviewPage(int docIndex, int pageIndex) async {
    Navigator.pushNamed(
      context,
      '/preview',
      arguments: {'docIndex': docIndex, 'pageIndex': pageIndex},
    );
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
    var newDoc = await FilesHelper.getNewPathsForDoc(
      widget.docIndex,
      picturePaths.length,
    );
    List<List<String>> newPaths = newDoc.$1;
    int firstPageIndex = newDoc.$2;
    //process pages individually
    for (var i = 0; i < picturePaths.length; i++) {
      ImageProcessingManager.processPage(picturePaths[i], newPaths[i]);
    }

    return firstPageIndex;
  }

  //double getAvailableAreaHeight(BuildContext context) {
  //  final mediaQuery = MediaQuery.of(context);
  //  final screenHeight = mediaQuery.size.height;
  //  final appBarHeight = Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight;
  //  final statusBarHeight = mediaQuery.padding.top;
  //  final bottomNavBarHeight =
  //      mediaQuery.padding.bottom; // System navigation bar
  //  return screenHeight - appBarHeight - statusBarHeight - bottomNavBarHeight;
  //}

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
                    itemCount: _pageThumbnails.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).shadowColor.withAlpha(125),
                                blurRadius: 8,
                                spreadRadius: -2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Sized Box for if image disappears from memory management
                              if (_thumbnailHeights[index] != null)
                                SizedBox(height: _thumbnailHeights[index]),
                              // Load and measure the image
                              MeasureSize(
                                key: _imageKeys[index],
                                onChange: (size) {
                                  setState(() {
                                    _thumbnailHeights[index] = size.height;
                                  });
                                },
                                child: Image.file(
                                  File(_pageThumbnails[index]),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              // Open PreviewPage
                              Positioned.fill(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap:
                                        () => _openPreviewPage(
                                          widget.docIndex,
                                          index,
                                        ),
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
                                  // Swap Page Index Dialog
                                  onTap: () async {
                                    int? selectedIndex = await showDialog<int>(
                                      context: context,
                                      builder: (BuildContext context) {
                                        int currentIndex = index;
                                        return AlertDialog(
                                          title: Text("Swap Page Index"),
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
                                      await FilesHelper.changePageIndex(
                                        widget.docIndex,
                                        index,
                                        selectedIndex,
                                      );
                                      _reloadPageThumbnails();
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color.fromARGB(255, 240, 240, 240),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(
                                            context,
                                          ).shadowColor.withAlpha(125),
                                          blurRadius: 12,
                                          spreadRadius: -2,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      "${index + 1}/${_pageThumbnails.length}",
                                      style: TextStyle(
                                        color: Colors.black,
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

class PreviewPage extends StatefulWidget {
  const PreviewPage({
    super.key,
    required this.docIndex,
    required this.pageIndex,
  });
  final int docIndex;
  final int pageIndex;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  final PageController _pageController = PageController();
  int _currentVersion = 0;
  bool _currentVersionSet = false;

  final List<bool> _imagesLoaded = List.filled(4, false);
  List<String> _imagePaths = [];

  @override
  void initState() {
    super.initState();
    initAsync();
  }

  Future<void> initAsync() async {
    _imagePaths = await FilesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    );
    _checkImagesPeriodically();
  }

  void _checkImagesPeriodically() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      bool anyChange = false;
      for (int i = 0; i < _imagePaths.length; i++) {
        if (!_imagesLoaded[i] && File(_imagePaths[i]).existsSync()) {
          _imagesLoaded[i] = true;
          anyChange = true;
        }
      }
      if (_imagesLoaded[3] && !_currentVersionSet) _currentVersion = 3;
      // Update UI when images are found
      if (anyChange && mounted) {
        _currentVersionSet = true;
        setState(() {});
      }
      // Stop checking if all images are loaded
      if (_imagesLoaded.every((loaded) => loaded)) {
        timer.cancel();
      }
    });
  }

  static List<String> versionNames = [
    "unprocessed",
    "warped",
    "filetred",
    "PRO",
  ];

  Future<void> _savePagePopup(BuildContext context, int versionIndex) async {
    final String imagePath = _imagePaths[_currentVersion];
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
                  docIndex: widget.docIndex,
                  pageIndex: widget.pageIndex,
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
    final String imagePath = _imagePaths[_currentVersion];
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
                await FilesHelper.shareImagesPdf(
                  context,
                  [imagePath],
                  docIndex: widget.docIndex,
                  pageIndex: widget.pageIndex,
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
      await FilesHelper.deletePage(widget.docIndex, widget.pageIndex);
      return true;
    }
    return false;
  }

  // Preview Page
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Top Bar
      appBar: AppBar(
        title: Text('Page ${widget.pageIndex + 1}'),
        actions: [
          PopupMenuButton(
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    enabled: _imagesLoaded.every((element) => element),
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
                  if (deleted && context.mounted) {
                    Navigator.pop(context);
                  }
                  break;
              }
            },
          ),
        ],
      ),
      // Page Versions
      body: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              height: MediaQuery.of(context).size.width * 1.414,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor.withAlpha(40),
                      blurRadius: 50,
                      spreadRadius: -20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PhotoViewGallery.builder(
            scrollPhysics: const PageScrollPhysics(),
            itemCount: _imagePaths.length,
            builder: (context, index) {
              if (!_imagesLoaded[_currentVersion]) {
                // Show loading indicator if image is not loaded
                return PhotoViewGalleryPageOptions.customChild(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text("Processing image..."),
                    ],
                  ),
                  disableGestures: true,
                );
              }
              // Show actual image when loaded
              return PhotoViewGalleryPageOptions(
                imageProvider: FileImage(File(_imagePaths[_currentVersion])),
                filterQuality: FilterQuality.high,
                minScale: PhotoViewComputedScale.contained,
                maxScale: 1.0,
              );
            },
            backgroundDecoration: BoxDecoration(color: Colors.transparent),
            pageController: _pageController,
            onPageChanged: (index) {
              setState(() => _currentVersion = index);
            },
          ),
        ],
      ),
      // Floating Buttons
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: FloatingActionButton(
              heroTag: "sharePageVersion",
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onPressed:
                  _imagesLoaded[_currentVersion]
                      ? () => _sharePagePopup(context, _currentVersion)
                      : null,
              tooltip:
                  _imagesLoaded[_currentVersion]
                      ? 'Share Image'
                      : 'Waiting for image to load...',
              backgroundColor:
                  _imagesLoaded[_currentVersion]
                      ? null
                      : Theme.of(context).disabledColor,
              elevation: _imagesLoaded[_currentVersion] ? null : 0.0,
              child: Icon(
                Icons.share,
                color:
                    _imagesLoaded[_currentVersion]
                        ? null
                        : Theme.of(context).disabledColor,
              ),
            ),
          ),
          SizedBox(height: 18.0),
          FloatingActionButton(
            heroTag: "savePageVersion",
            onPressed:
                _imagesLoaded[_currentVersion]
                    ? () => _savePagePopup(context, _currentVersion)
                    : null,
            tooltip:
                _imagesLoaded[_currentVersion]
                    ? 'Save Image'
                    : 'Waiting for image to load...',
            backgroundColor:
                _imagesLoaded[_currentVersion]
                    ? null
                    : Theme.of(context).disabledColor,
            elevation: _imagesLoaded[_currentVersion] ? null : 0.0,
            child: Icon(
              Icons.save,
              color:
                  _imagesLoaded[_currentVersion]
                      ? null
                      : Theme.of(context).disabledColor,
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
                  setState(() => _currentVersion = index);
                  _pageController.jumpToPage(index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          _currentVersion == index
                              ? Colors.white
                              : Colors.white54,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withAlpha(125),
                        blurRadius: 8,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child:
                        _imagesLoaded[index]
                            ? Image.file(
                              File(_imagePaths[index]),
                              width: _currentVersion == index ? 70 : 50,
                              height: _currentVersion == index ? 70 : 50,
                              fit: BoxFit.cover,
                            )
                            : Container(
                              width:
                                  _currentVersion == index && index != 0
                                      ? 70
                                      : 50,
                              height:
                                  _currentVersion == index && index != 0
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
