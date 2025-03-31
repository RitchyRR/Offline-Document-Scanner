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
late GlobalNotifier globalNotifier;

enum NotifierEvent {
  loadPagesThumbnails,
  reloadPagesThumbnails,
  loadDocsThumbnailsAndInfo,
  reloadDocsThumbnails,
  loadPageVersions,
  loadPageMetadata,
}

void main() {
  globalNotifier = GlobalNotifier();
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
  Route _pushPagesThenPreview(int docIndex, int pageIndex) {
    return MaterialPageRoute(
      builder: (context) {
        Future.microtask(() {
          Navigator.pushNamed(
            // ignore: use_build_context_synchronously
            context,
            '/preview',
            arguments: {'docIndex': docIndex, 'pageIndex': pageIndex},
          );
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
        //surface: darkScheme.surfaceContainerLow,
        //surfaceContainerLow: darkScheme.surfaceContainerHigh, // cards + elevated buttons
        //surfaceContainer: darkScheme.surfaceContainerHighest,
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
    var newDoc = await FilesHelper.getNewPaths(picturePaths.length);
    List<List<String>> newPaths = newDoc.$1;
    int docIndex = newDoc.$2;
    int firstPageIndex = newDoc.$3;
    // process pages individually
    for (var i = 0; i < picturePaths.length; i++) {
      ImageProcessingManager.processPage(
        picturePaths[i],
        newPaths[i],
        await FilesHelper.getPagePath(docIndex, i),
      );
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
    if (!mounted) return;
    switch (globalNotifier.value) {
      case NotifierEvent.loadDocsThumbnailsAndInfo:
        _refreshDocsDisplay();
        break;
      case NotifierEvent.reloadDocsThumbnails:
        _reloadDocsDisplay();
        break;
      default:
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
    final docPath = await FilesHelper.getDocumentPath(docIndex);
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
    //dev.log("Reloading documents thumbnails.");
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
                                          await FilesHelper.changeDocumentIndex(
                                            index,
                                            selectedIndex,
                                          );
                                          _reloadDocsDisplay();
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
                                    Image.file(
                                      File(_docThumbnails[index]),
                                      //width: 160.0,
                                      //height: 160.0 * 1.414,
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
                    decoration: BoxDecoration(boxShadow: [smallBoxShadow()]),
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
  bool popped = false;

  @override
  void initState() {
    super.initState();
    globalNotifier.addListener(_handleGlobalEvent);
    _loadPagesThumbnails(onFirstLoading: true);
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
      case NotifierEvent.reloadPagesThumbnails:
        _reloadPageThumbnails();
        break;
      default:
    }
  }

  Future<void> _loadPagesThumbnails({bool onFirstLoading = false}) async {
    List<String> thumbnailPaths = await FilesHelper.getPagesThumbnails(
      widget.docIndex,
    );
    if (thumbnailPaths.isEmpty) {
      if (popped) {
        dev.log("Error, can't Navigator.pop(context); twice.");
      } else if (!onFirstLoading && mounted && context.mounted) {
        Navigator.pop(context);
        popped = true;
      }
    } else {
      int tooShortBy = thumbnailPaths.length - _thumbnailHeights.length;
      for (var i = 0; i < tooShortBy; i++) {
        _thumbnailHeights.add(null);
        _imageKeys.add(GlobalKey());
      }
      setState(() {
        _pageThumbnails = thumbnailPaths;
      });
    }
  }

  Future<void> _reloadPageThumbnails() async {
    //dev.log("Reloading pages thumbnails.");
    for (var path in _pageThumbnails) {
      /*final evictRes = */
      imageCache.evict(FileImage(File(path)), includeLive: true);
      //dev.log("reordering evictRes: $evictRes");
    }
    setState(() {
      _pageThumbnails = [];
      _thumbnailHeights.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPagesThumbnails();
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
      ImageProcessingManager.processPage(
        picturePaths[i],
        newPaths[i],
        await FilesHelper.getPagePath(widget.docIndex, firstPageIndex + i),
      );
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
                            boxShadow: [bigBoxShadow(context)],
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
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceBright,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [smallBoxShadow()],
                                    ),
                                    child: Text(
                                      "${index + 1}/${_pageThumbnails.length}",
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
  int _selectedThumbnail = 0;
  bool _initialVersionSet = false;

  final List<bool> _imagesLoaded = List.filled(4, false);
  List<String> _imagePaths = [];

  // Reprocessing Parameters:
  int? _ratioIndex;
  int? _newRatioIndex;
  int? _orientationPortrait;
  int? _newOrientationPortrait;
  int _totalRotation = 0;

  @override
  void initState() {
    super.initState();
    globalNotifier.addListener(_handleGlobalEvent);
    initAsync();
  }

  @override
  void dispose() {
    globalNotifier.removeListener(_handleGlobalEvent);
    FilesHelper.deleteTmpDir();
    super.dispose();
  }

  Future<void> initAsync() async {
    _imagePaths = await FilesHelper.getImagePathsForPage(
      widget.docIndex,
      widget.pageIndex,
    );
    _checkImagesPeriodically();
    _loadPageMeatadata();
  }

  void _checkImagesPeriodically() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      bool anyChange = false;
      for (int i = 0; i < _imagePaths.length; i++) {
        if (!_imagesLoaded[i] && File(_imagePaths[i]).existsSync()) {
          _imagesLoaded[i] = true;
          anyChange = true;
        }
      }
      if (!_initialVersionSet && mounted) {
        if (_imagesLoaded[3]) {
          setState(() => _selectedThumbnail = 3);
          _pageController.jumpToPage(_selectedThumbnail);
        }
      }
      // Update UI when images are found
      if (anyChange && mounted) {
        _initialVersionSet = true;
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

  void _handleGlobalEvent() {
    if (!mounted) return;
    switch (globalNotifier.value) {
      case NotifierEvent.loadPageVersions:
        _refreshPageVersions();
        break;
      case NotifierEvent.loadPageMetadata:
        _loadPageMeatadata();
        break;
      default:
    }
  }

  void _refreshPageVersions() {
    for (var path in _imagePaths) {
      imageCache.evict(FileImage(File(path)), includeLive: true);
    }
  }

  Future<void> _loadPageMeatadata() async {
    String pagePath = await FilesHelper.getPagePath(
      widget.docIndex,
      widget.pageIndex,
    );
    _newRatioIndex =
        _ratioIndex = await ImageProcessingManager.readPageRatio(pagePath);
    _newOrientationPortrait =
        _orientationPortrait = await ImageProcessingManager.readPageOrientation(
          pagePath,
        );
    setState(() {
      _ratioIndex;
      _orientationPortrait;
    });
  }

  Future<void> _savePagePopup(BuildContext context, int versionIndex) async {
    final String imagePath = _imagePaths[_selectedThumbnail];
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
    final String imagePath = _imagePaths[_selectedThumbnail];
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

  void _reprocessingSetup() {
    _ratioIndex = null; // don't reset _new values, for display
    _orientationPortrait = null;
    _totalRotation = 0;
    for (var i = 0; i < _imagesLoaded.length; i++) {
      _imagesLoaded[i] = false;
    }
    FilesHelper.deleteProcessedVersionsOfPage(
      widget.docIndex,
      widget.pageIndex,
    );
    if (mounted) {
      _refreshPageVersions();
      setState(() {});
      _checkImagesPeriodically();
    }
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
                  if (deleted && mounted && context.mounted) {
                    Navigator.pop(context);
                  }
                  break;
              }
            },
          ),
        ],
      ),
      // Images (Page Versions)
      body: Stack(
        children: [
          // Bg Shadow
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
            wantKeepAlive: false,
            scrollPhysics: const PageScrollPhysics(),
            itemCount: _imagePaths.length,
            builder: (context, index) {
              if (!_imagesLoaded[index]) {
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
                imageProvider: FileImage(File(_imagePaths[index])),
                filterQuality: FilterQuality.high,
                minScale: PhotoViewComputedScale.contained,
                maxScale: 1.0,
              );
            },
            backgroundDecoration: BoxDecoration(color: Colors.transparent),
            pageController: _pageController,
            onPageChanged: (index) {
              setState(() => _selectedThumbnail = index);
            },
          ),
          _selectedThumbnail == 0
              ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Align(
                  alignment: Alignment.topCenter,

                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [smallBoxShadow()],
                    ),
                    child: Row(
                      spacing: 12,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          spacing: 12,
                          children: [
                            _aspectRatioDropDown(context),
                            _orientationDropDown(context),
                            CustomIconButton(
                              onTap: () async {
                                String rotatedImagePath =
                                    await FilesHelper.rotateImageInTmpDir(
                                      _imagePaths[0],
                                      angle: -90,
                                    );
                                _totalRotation = (_totalRotation - 90) % 360;
                                setState(() {
                                  _imagesLoaded[0] = false;
                                  _imagePaths[0] = rotatedImagePath;
                                  _checkImagesPeriodically();
                                });
                              },
                              isFlat: true,
                              isDisabled: _ratioIndex == null,
                              icon: Icons.rotate_left,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            ),
                            CustomIconButton(
                              onTap: () async {
                                String rotatedImagePath =
                                    await FilesHelper.rotateImageInTmpDir(
                                      _imagePaths[0],
                                      angle: 90,
                                    );
                                _totalRotation = (_totalRotation + 90) % 360;
                                setState(() {
                                  _imagesLoaded[0] = false;
                                  _imagePaths[0] = rotatedImagePath;
                                  _checkImagesPeriodically();
                                });
                              },
                              isFlat: true,
                              isDisabled: _ratioIndex == null,
                              icon: Icons.rotate_right,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            ),
                          ],
                        ),
                        _confirmReProcessingButton(context),
                      ],
                    ),
                  ),
                ),
              )
              : SizedBox(),
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
                  _imagesLoaded[_selectedThumbnail]
                      ? () => _sharePagePopup(context, _selectedThumbnail)
                      : null,
              tooltip:
                  _imagesLoaded[_selectedThumbnail]
                      ? 'Share Image'
                      : 'Waiting for image to load...',
              backgroundColor:
                  _imagesLoaded[_selectedThumbnail]
                      ? null
                      : Theme.of(context).disabledColor,
              elevation: _imagesLoaded[_selectedThumbnail] ? null : 0.0,
              child: Icon(
                Icons.share,
                color:
                    _imagesLoaded[_selectedThumbnail]
                        ? null
                        : Theme.of(context).disabledColor,
              ),
            ),
          ),
          SizedBox(height: 18.0),
          FloatingActionButton(
            heroTag: "savePageVersion",
            onPressed:
                _imagesLoaded[_selectedThumbnail]
                    ? () => _savePagePopup(context, _selectedThumbnail)
                    : null,
            tooltip:
                _imagesLoaded[_selectedThumbnail]
                    ? 'Save Image'
                    : 'Waiting for image to load...',
            backgroundColor:
                _imagesLoaded[_selectedThumbnail]
                    ? null
                    : Theme.of(context).disabledColor,
            elevation: _imagesLoaded[_selectedThumbnail] ? null : 0.0,
            child: Icon(
              Icons.save,
              color:
                  _imagesLoaded[_selectedThumbnail]
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
                  setState(() => _selectedThumbnail = index);
                  _pageController.jumpToPage(index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          _selectedThumbnail == index
                              ? Colors.white
                              : Colors.white54,
                      width: 3,
                    ),
                    boxShadow: [bigBoxShadow(context)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child:
                        _imagesLoaded[index]
                            ? Image.file(
                              File(_imagePaths[index]),
                              width: _selectedThumbnail == index ? 70 : 50,
                              height: _selectedThumbnail == index ? 70 : 50,
                              fit: BoxFit.cover,
                            )
                            : Container(
                              width:
                                  _selectedThumbnail == index && index != 0
                                      ? 70
                                      : 50,
                              height:
                                  _selectedThumbnail == index && index != 0
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

  CustomIconButton _confirmReProcessingButton(BuildContext context) {
    return CustomIconButton(
      constraints: BoxConstraints(maxHeight: 36, maxWidth: 36),
      color: Theme.of(context).colorScheme.primaryContainer,
      icon: Icons.check,
      isDisabled: _ratioIndex == null,
      isHidden:
          ((_ratioIndex == _newRatioIndex) &&
              (_orientationPortrait == _newOrientationPortrait) &&
              _totalRotation == 0),
      tooltip: "Confirm changes",
      onTap: () async {
        await ImageProcessingManager.writePageMetadata(
          _newRatioIndex ?? 0,
          (_newOrientationPortrait ?? 0) == 0,
          await FilesHelper.getPagePath(widget.docIndex, widget.pageIndex),
        );
        _reprocessingSetup();
        await ImageProcessingManager.processPage(
          _imagePaths[0], // potentially rotated image
          await FilesHelper.getImagePathsForPage(
            widget.docIndex,
            widget.pageIndex,
          ), // correct paths, without potentially rotated image in _imagePaths[0]
          await FilesHelper.getPagePath(widget.docIndex, widget.pageIndex),
          inRatioIndex: _newRatioIndex,
          orientation: (_newOrientationPortrait ?? 0) == 0,
        );
      },
    );
  }

  Container _aspectRatioDropDown(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color:
            Theme.of(context)
                .colorScheme
                .surfaceContainerHighest, //fromARGB(255, 220, 220, 220),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [smallBoxShadow()],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          //dropdownColor: Color.fromARGB(255, 220, 220, 220),
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
                style: TextStyle(
                  //color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          onChanged: (int? newValue) async {
            if (newValue != null && newValue != _newRatioIndex) {
              setState(() => _newRatioIndex = newValue);
            }
          },
        ),
      ),
    );
  }

  Container _orientationDropDown(BuildContext context) {
    List<String> orientationsList = ["portrait", "landscape"];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:
            Theme.of(context)
                .colorScheme
                .surfaceContainerHighest, //fromARGB(255, 220, 220, 220),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [smallBoxShadow()],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          //dropdownColor: Color.fromARGB(255, 220, 220, 220),
          isDense: true,
          isExpanded: false,
          alignment: Alignment.center,
          icon:
              SizedBox.shrink(), //Icon((_orientationPortrait ?? true)? Icons.crop_portrait: Icons.crop_landscape,),
          value: _newOrientationPortrait,
          items: List.generate(
            orientationsList.length,
            (j) => DropdownMenuItem(
              alignment: Alignment.center,
              value: j,
              child: Text(
                orientationsList[j],
                style: TextStyle(
                  //color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          onChanged: (int? newValue) async {
            if (newValue != null && newValue != _newOrientationPortrait) {
              setState(() => _newOrientationPortrait = newValue);
            }
          },
        ),
      ),
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
                        boxShadow: [smallBoxShadow()],
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
                    child: Center(
                      child: Icon(
                        icon,
                        color:
                            isDisabled ? Theme.of(context).disabledColor : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
  }
}
