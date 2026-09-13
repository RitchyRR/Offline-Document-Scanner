Offline Dokumenten-Scanner
https://play.google.com/store/apps/details?id=com.rrapps.docscanner 

* Fotos aufnehmen, Fotos importieren, PDFs importieren
* Bessere Filter als alle anderen Dokumentenscanner
* Teilen / Speichern: Bilder exportieren, als PDF exportieren
* Einstellen von DPI für kleinere Dateigrößen
* Speichern / Teilen gesamter Dokumente, einzelner Seiten oder mehrerer ausgewählter Seiten
* Fotos / PDFs an App teilen / mit App öffnen

Diese App berechnet alles auf dem Gerät und verwendet keine Server. Bei der Bildverarbeitung werden Schatten uns die Papiertextur entfernt, während Farben und Details erhalten bleiben.

* Adaptive dunkle / helle Farbschema
* Wählen Sie die zu nutzenden Seitenverhältnisse
* Wählen Sie die standardmäßig zu verwendenden Filter

Sie können Ihre gescannten Dokumente als PDFs oder Bilder exportieren und mit anderen Apps wie WhatsApp teilen.

Die Ecken und Kanten der Bilder werden automatisch erkannt und dem automatisch erkannten Seitenverhältnis entsprechend angepasst. Das Format, sowie die Verarbeitung (Drehung, Seitenverhältnis, der Projektionsausschnitt und der verwendete Filter) können manuell bearbeitet werden.

### OpenCV-GPU-Beschleunigung auf Android

Die native Verarbeitung verwendet für unterstützte OpenCV-Operationen `cv::UMat`.
Beim Start wird OpenCL einmalig aktiviert; falls das Gerät oder die OpenCV-Bibliothek
kein OpenCL bereitstellt, fällt die Verarbeitung automatisch auf den bisherigen
optimierten CPU-Pfad zurück. Dadurch bleiben Reads, Writes und Verarbeitungsergebnisse
funktional gleich.

Für tatsächliche GPU-Ausführung muss `OPENCV_ANDROID_SDK` auf eine Android-OpenCV-
Build zeigen, die mit `WITH_OPENCL=ON` erstellt wurde. Das bisher verwendete offizielle
Android-SDK ist ohne OpenCL gebaut und kann deshalb nur den CPU-Fallback verwenden:

```bash
OPENCV_ANDROID_SDK=/path/to/opencv-android-sdk-opencl \
  ./android/gradlew -p android assembleRelease
```

Alternativ kann der Pfad in `android/app/src/main/cpp/CMakeLists.txt` gesetzt werden.
Auf Android-Geräten ohne OpenCL-Treiber wird weiterhin automatisch der CPU-Pfad
verwendet.
