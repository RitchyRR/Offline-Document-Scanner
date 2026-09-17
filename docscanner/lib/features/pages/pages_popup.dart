import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../app/app_globals.dart';
import '../../app/feedback_helper.dart';
import '../../app/filter_names.dart';
import '../../app/global_notifier.dart';
import '../../app/metadata_helper.dart';
import '../../widgets/app_shadows.dart';
import '../../widgets/indicator_processing_image.dart';
import '../pro/ads_helper.dart';
import '../pro/pro_purchase.dart';

class _PdfPopupPreview extends StatefulWidget {
  const _PdfPopupPreview({required this.path});

  final String path;

  @override
  State<_PdfPopupPreview> createState() => _PdfPopupPreviewState();
}

class _PdfPopupPreviewState extends State<_PdfPopupPreview> {
  late Future<Uint8List> _previewFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture = _renderPreview();
  }

  @override
  void didUpdateWidget(covariant _PdfPopupPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _previewFuture = _renderPreview();
    }
  }

  Future<Uint8List> _renderPreview() async {
    final document = await pdfrx.PdfDocument.openFile(widget.path);
    try {
      final page = document.pages.first;
      const width = 320.0;
      final renderedPage = await page.render(
        fullWidth: width,
        fullHeight: width * page.height / page.width,
        backgroundColor: 0xffffffff,
      );
      if (renderedPage == null) {
        throw StateError("Could not render PDF preview");
      }
      try {
        return Uint8List.fromList(img.encodePng(renderedPage.createImageNF()));
      } finally {
        renderedPage.dispose();
      }
    } finally {
      document.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _previewFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(snapshot.data!, fit: BoxFit.cover);
        }
        if (snapshot.hasError) {
          return const Center(child: Icon(Icons.broken_image));
        }
        return const IndicatorProcessingImage();
      },
    );
  }
}

class _ImagesScrollPreview extends StatelessWidget {
  const _ImagesScrollPreview({
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
                                  child:
                                      imagePath.toLowerCase().endsWith(".pdf")
                                      ? _PdfPopupPreview(path: imagePath)
                                      : Image.file(
                                          File(imagePath),
                                          fit: BoxFit.cover,
                                          key: ValueKey(imagePath),
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

Future<void> showChangingThumbnailsSnackbar(
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

Future<bool> showPagesPopup(
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
  final effectivePageIndexes = pageIndexes.isEmpty
      ? List.generate(pagesCount, (index) => index)
      : pageIndexes;
  final bool hasPdfPages = (await Future.wait(
    effectivePageIndexes.map(
      (pageIndex) => g.filesHelper.hasPdfPage(docIndex, pageIndex),
    ),
  )).any((value) => value);
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
  List<int> pagesDpis = hasPdfPages
      ? []
      : (await g.filesHelper.getPdfPageDpis(
          docIndex,
          pageIndexes: pageIndexes,
          versionIndex: versionIndex,
        )).$1;
  int? selectedDpi;
  // Loading...
  List<bool> loadingImages = await _loadLoadingImages(
    docIndex,
    pageIndexes,
    thumbnailPaths,
    supressWarnings: true,
  );
  bool allImagesLoaded = loadingImages.every((element) => !element);
  // Compressing...
  List<bool> uncompressedImages = await _loadUncompressedImages(thumbnailPaths);
  bool allImagesCompressed = uncompressedImages.every((element) => !element);
  // Aspect Ratios
  List<double> imageRatios = await _loadImageRatios(
    docIndex,
    pageIndexes,
    pagesCount,
  );
  // Pages exporte with same width
  bool sameWidth = false;
  // Document Name
  String? customDocName = await g.metadataHelper.readDocName(docIndex);

  await showDialog(
    // ignore: use_build_context_synchronously
    context: callContext,
    builder: (BuildContext context) {
      return StreamBuilder<NotifierEvent>(
        stream: globalNotifier.stream,
        builder: (context, snapshot) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              final event = snapshot.data;
              if (event == NotifierEvent.loadPagesThumbnails) {
                Future<void> afterThumbnailsLoaded() async {
                  loadingImages = await _loadLoadingImages(
                    docIndex,
                    pageIndexes,
                    thumbnailPaths,
                    supressWarnings: true,
                  );
                  allImagesLoaded = loadingImages.every((element) => !element);
                  uncompressedImages = await _loadUncompressedImages(
                    thumbnailPaths,
                  );
                  allImagesCompressed = uncompressedImages.every(
                    (element) => !element,
                  );
                  if (context.mounted) setStateDialog(() {});
                }

                if (versionIndex != null && pageIndexes.length == 1) {
                  Future.microtask(() async {
                    thumbnailPaths = [
                      await g.filesHelper.getVersionPath(
                        docIndex,
                        pageIndexes.first,
                        versionIndex,
                      ),
                    ];
                    afterThumbnailsLoaded();
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
                    afterThumbnailsLoaded();
                  });
                }
                Future.microtask(() async {
                  imageRatios = await _loadImageRatios(
                    docIndex,
                    pageIndexes,
                    pagesCount,
                  );
                });
                Future.microtask(() async {
                  imagesFilesizes = await g.filesHelper.getImagesFilesizes(
                    docIndex,
                    pageIndexes: pageIndexes,
                    versionIndex: versionIndex,
                  );
                });
                if (!hasPdfPages) {
                  Future.microtask(() async {
                    pagesDpis = (await g.filesHelper.getPdfPageDpis(
                      docIndex,
                      pageIndexes: pageIndexes,
                      versionIndex: versionIndex,
                    )).$1;
                  });
                }
              }
              String title;
              if (isDocument) {
                String docName =
                    customDocName ??
                    tr(
                      "documents.card.popup.title",
                      namedArgs: {"docIndex": "${docIndex + 1}"},
                    );
                switch (type) {
                  case PopUpType.share:
                    title = tr(
                      "popup.pagesPopup.document.share.title",
                      namedArgs: {"docName": docName},
                    );
                    break;
                  case PopUpType.save:
                    title = tr(
                      "popup.pagesPopup.document.save.title",
                      namedArgs: {"docName": docName},
                    );
                    break;
                  case PopUpType.delete:
                    title = tr(
                      "popup.pagesPopup.document.delete.title",
                      namedArgs: {"docName": docName},
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
              bool dpiLocked =
                  !g.proUnlocked &&
                  !docUnlocked &&
                  !(isSinglePage && pageUnlocked);
              bool lockAll =
                  (isSinglePage &&
                      !(pageUnlocked || g.proUnlocked) &&
                      g.proFilterIndexes.contains(versionIndex)) ||
                  (dpiLocked && selectedDpi != null);
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
                  _ImagesScrollPreview(
                    imagePaths: thumbnailPaths,
                    loadingImages: loadingImages,
                    imageRatios: imageRatios,
                  ),
                  SizedBox(height: 12.0),
                  !allImagesLoaded || !allImagesCompressed
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
                                child: Text(
                                  allImagesLoaded
                                      ? tr("loading.compressingImages")
                                      : tr("loading.processingImages"),
                                ),
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
                  if (type != PopUpType.delete && !hasPdfPages)
                    _DpiDropdown(
                      pagesDpis: pagesDpis,
                      imagesFilesizes: imagesFilesizes,
                      onChanged: (dpi) {
                        selectedDpi = dpi;
                        setStateDialog(() {});
                      },
                      dpiLocked: dpiLocked,
                      allPagesLoaded: allImagesLoaded,
                    ),
                  if (type != PopUpType.delete &&
                      !hasPdfPages &&
                      !isSinglePage &&
                      imageRatios.any((element) => element != imageRatios.last))
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: _PagesWidthDropdown(
                        allPagesLoaded: allImagesLoaded,
                        onChanged: (useSameWidth) {
                          sameWidth = useSameWidth;
                          setStateDialog(() {});
                        },
                      ),
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
                                  if (!hasPdfPages)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: lockAll ? 4 : 0,
                                      ),
                                      // Image Export
                                      child: ElevatedButton.icon(
                                        onPressed: allImagesLoaded && !lockAll
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
                                                          useSameWidth:
                                                              sameWidth,
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
                                                          useSameWidth:
                                                              sameWidth,
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
                                                allImagesLoaded && !lockPdf
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
                                                              useSameWidth:
                                                                  sameWidth,
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
                                                              useSameWidth:
                                                                  sameWidth,
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
                                                            await unlockDocumentWithAd(
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
                                                  await unlockPageWithAd(
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

Future<List<double>> _loadImageRatios(
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

Future<List<bool>> _loadLoadingImages(
  int docIndex,
  List<int> pageIndexes,
  List<String> thumbnailPaths, {
  bool supressWarnings = false,
}) async {
  if (pageIndexes.isEmpty) {
    pageIndexes = List.generate(thumbnailPaths.length, (index) => index);
  }
  List<bool> thumbnailsLoading = [];
  for (var (i, pageIndex) in pageIndexes.indexed) {
    bool thumbnailLoading = false;
    if (thumbnailPaths[i].toLowerCase().endsWith(".pdf")) {
      thumbnailLoading = false;
    } else if (thumbnailPaths[i].isEmpty) {
      thumbnailLoading = true;
    } else {
      final oldNames = await MetadataHelper.readOldPageFileNames(
        docIndex,
        pageIndex,
        supressWarnings: supressWarnings,
      );
      if (oldNames != null) {
        for (var oldName in oldNames) {
          if (oldName.isNotEmpty && thumbnailPaths[i].contains(oldName)) {
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

Future<List<bool>> _loadUncompressedImages(List<String> thumbnailPaths) async {
  final thumbnailsCount = thumbnailPaths.length;
  List<bool> thumbnailsUncompressed = [];
  for (int i = 0; i < thumbnailsCount; i++) {
    bool thumbnailUncompressed = false;
    if (!thumbnailPaths[i].toLowerCase().endsWith(".pdf") &&
        (thumbnailPaths[i].isEmpty ||
            thumbnailPaths[i].contains("_uncompressed"))) {
      thumbnailUncompressed = true;
    }
    thumbnailsUncompressed.add(thumbnailUncompressed);
  }
  return thumbnailsUncompressed;
}

class _PagesWidthDropdown extends StatefulWidget {
  final void Function(bool selectedDpi) onChanged;
  final bool allPagesLoaded;
  const _PagesWidthDropdown({
    required this.onChanged,
    required this.allPagesLoaded,
  });

  @override
  State<_PagesWidthDropdown> createState() => _PagesWidthDropdownState();
}

class _PagesWidthDropdownState extends State<_PagesWidthDropdown> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<String> menuEntryStrings = [
      tr("popup.pagesPopup.pagesWidth.individual"),
      tr("popup.pagesPopup.pagesWidth.same"),
    ];
    final double height = 30;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(height / 2),
          isDense: true,
          isExpanded: false,
          alignment: Alignment.centerRight,
          //icon: const SizedBox.shrink(), // to hide drop-down-arrow
          value: selectedIndex,
          items: List.generate(menuEntryStrings.length, (i) {
            return DropdownMenuItem(
              alignment: Alignment.centerRight,
              value: i,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 243),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    menuEntryStrings[i],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }),
          onChanged: widget.allPagesLoaded
              ? (int? newIndex) {
                  setState(() {
                    selectedIndex = newIndex ?? 0;
                  });

                  // Return useSameWidth to where Widget is used
                  final bool useSameWidth = newIndex == 1;
                  widget.onChanged(useSameWidth);
                }
              : null,
        ),
      ),
    );
  }
}

class _DpiDropdown extends StatefulWidget {
  final List<int> pagesDpis;
  final List<int> imagesFilesizes;
  final void Function(int? selectedDpi) onChanged;
  final bool dpiLocked;
  final bool allPagesLoaded;

  const _DpiDropdown({
    required this.pagesDpis,
    required this.imagesFilesizes,
    required this.onChanged,
    required this.dpiLocked,
    required this.allPagesLoaded,
  });

  @override
  State<_DpiDropdown> createState() => _DpiDropdownState();
}

class _DpiDropdownState extends State<_DpiDropdown> {
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
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [tinyBoxShadow(context)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          elevation: 8,
          borderRadius: BorderRadius.circular(height / 2),
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
                  : (widget.pagesDpis.length == 1 &&
                        widget.imagesFilesizes.length == 1)
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

              for (
                int i = 0;
                i < widget.imagesFilesizes.length &&
                    i < widget.pagesDpis.length;
                i++
              ) {
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
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 243),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
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
                      if (i != 0 && widget.dpiLocked)
                        Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.lock),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          onChanged: widget.pagesDpis.isEmpty || !widget.allPagesLoaded
              ? null
              : (int? newIndex) {
                  setState(() {
                    selectedIndex = newIndex ?? 0;
                  });

                  // Return selectedDPI to where Widget is used
                  final int? selectedDpi = newIndex == 0
                      ? null
                      : lowerDpis[newIndex! - 1];
                  widget.onChanged(selectedDpi);
                },
        ),
      ),
    );
  }
}
