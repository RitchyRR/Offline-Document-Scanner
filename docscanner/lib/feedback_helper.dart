import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:developer' as dev;
import 'dart:io' show Platform;
import 'package:easy_localization/easy_localization.dart' show tr;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart' show Fluttertoast;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
import 'package:url_launcher/url_launcher.dart' show canLaunchUrl, launchUrl;
import 'package:crypto/crypto.dart';

enum FeedbackState { init, afterFirstExport, afterFirstProcessing, hidden }

class FeedbackHelper {
  FeedbackState state = FeedbackState.init;
  FeedbackHelper() {
    initAsync();
  }
  initAsync() async {
    await _readFeedbackState();
    _reenableRatingsAfterTwoWeeks();
  }

  Future<void> _readFeedbackState() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString("FeedbackState")) {
      case "afterFirstExport":
        state = FeedbackState.afterFirstExport;
        break;
      case "afterFirstProcessing":
        state = FeedbackState.afterFirstProcessing;
        break;
      case "hidden":
        state = FeedbackState.hidden;
        break;
      default:
        state = FeedbackState.init;
    }
  }

  _writeFeedbackState() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("FeedbackState", state.name);
  }

  bool isHidden() {
    return state == FeedbackState.hidden;
  }

  bool canShowExportPopup() {
    if (state == FeedbackState.init) {
      state = FeedbackState.afterFirstExport;
      _writeFeedbackState();
      return true;
    }
    return false;
  }

  bool canShowProcessingPopup() {
    if (state == FeedbackState.afterFirstExport) {
      state = FeedbackState.afterFirstProcessing;
      _writeFeedbackState();
      return true;
    }
    return false;
  }

  bool canShowInAppbar() {
    if (state == FeedbackState.hidden) return false;
    return state == FeedbackState.afterFirstExport ||
        state == FeedbackState.afterFirstProcessing;
  }

  Future<void> _writeRating(int newRating) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt("rating", newRating);
    String now = DateTime.now().toIso8601String();
    prefs.setString("ratingDate", now);
    state = FeedbackState.hidden;

    _writeFeedbackState();
  }

  _reenableRatingsAfterTwoWeeks() async {
    if (state != FeedbackState.hidden) return;
    final prefs = await SharedPreferences.getInstance();
    int? rating = prefs.getInt("rating");
    if (rating == 5) return; // only reenable if rating was not 5 stars

    final String? ratingDateString = prefs.getString("ratingDate");
    final now = DateTime.now();
    if (ratingDateString != null) {
      final ratingDate = DateTime.tryParse(ratingDateString);

      if (ratingDate != null && now.difference(ratingDate).inDays < 14) {
        return;
      }
    } else {
      dev.log(
        "Warning, _reenableRatingsAfterTwoWeeks: ratingDate was unknown, setting to now.",
      );
      prefs.setString("ratingDate", now.toIso8601String());
    }

    state = FeedbackState.init;
    _writeFeedbackState();
  }

  Future<void> showRatingDialog(BuildContext context) async {
    int rating = 0;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(tr("popup.feedback.title1")),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                  onPressed: () {
                    setState(() {
                      rating = index + 1;
                    });
                  },
                );
              }),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(tr("popup.cancel")),
              ),
              ElevatedButton(
                onPressed: rating == 0
                    ? null
                    : () async {
                        state = FeedbackState.hidden;
                        _writeRating(rating);
                        Navigator.pop(context);
                        if (rating == 5) {
                          _redirectToPlayStore();
                        } else {
                          _showFeedbackDialog(context, rating);
                        }
                      },
                child: Text(tr("popup.next")),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFeedbackDialog(BuildContext context, int rating) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(tr("popup.feedback.title2")),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: InputDecoration(hintText: tr("popup.feedback.hint")),
              onChanged: (text) {
                setState(() {});
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr("popup.cancel")),
              ),
              ElevatedButton(
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () {
                        final feedback = controller.text;
                        dev.log("User feedback: $feedback");
                        _sendFeedbackByEmail(feedback, rating);
                        Navigator.pop(context);
                      },
                child: Text(tr("popup.send")),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendFeedbackByEmail(String message, int rating) async {
    final String subject = Uri.encodeComponent("App Feedback");
    final String body = Uri.encodeComponent(
      "User rating:\n\n"
      "$rating/5\n\n"
      "User feedback:\n\n"
      "$message\n\n",
    );
    final String email = "R.R.appdev.public@gmail.com";

    final Uri emailUri = Uri.parse("mailto:$email?subject=$subject&body=$body");

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      Fluttertoast.showToast(msg: tr("toast.feedback"));
      dev.log("To $email: $message");
    } else {
      Fluttertoast.showToast(msg: tr("toast.e_connection"));
      throw StateError("Error, sendFeedbackByEmail: No connection :(");
    }
  }

  Future<bool> _redirectToPlayStore() async {
    //import 'package:in_app_review/in_app_review.dart';
    // in app popup
    //final InAppReview inAppReview = InAppReview.instance;
    //if (await inAppReview.isAvailable()) {
    //  inAppReview.requestReview();
    //  return true;
    //}

    // open store page
    final url = Uri(
      scheme: "https",
      host: "play.google.com",
      path: "/store/apps/details",
      queryParameters: {"id": "com.rrapps.docscanner"},
    );
    dev.log("Opening URL: $url");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
      return true;
    } else {
      Fluttertoast.showToast(msg: tr("toast.e_playStore"));
    }
    return false;
  }

  Future<bool> isAppValid() async {
    final info = await PackageInfo.fromPlatform();
    final installer = info.installerStore; // Other: com.amazon.venezia
    final signature = info.buildSignature; // SHA-256

    // calculate to obfuscate
    const int multiplier = 40949411; // prime number
    var sigBigInt = BigInt.parse(signature.replaceAll(":", ""), radix: 16);
    // add integers from signature
    for (var char in signature.characters) {
      final int? anInt = int.tryParse(char);
      if (anInt != null) {
        sigBigInt = sigBigInt + BigInt.from(anInt);
      }
    }
    final multiplied = sigBigInt * BigInt.from(multiplier);
    final hashed = sha256
        .convert(utf8.encode(multiplied.toString()))
        .toString();

    bool valid = false;
    if (Platform.isAndroid && installer == "com.android.vending") {
      // Play Store signature
      const expectedHash =
          "9e440b786b5307cc4cbf6747b4371100d575c78ea338047741a432d65eb7b49a";
      valid = hashed == expectedHash;
    } else if (Platform.isAndroid && installer == "com.android.shell") {
      // Debugging signature
      const debuggingHash =
          "fd88070c8836e7d47bffcf6ac66e6480d0b590cf0f151cece83e0a0701570585";
      // APK signature
      const apkHash =
          "56de66521c56319ace6f42464131d97819f693744ef19e11002a2ef9a2019eaf";
      valid = hashed == debuggingHash || hashed == apkHash;
    }

    // open store if invalid
    if (!valid) {
      if (Platform.isAndroid) {
        _redirectToPlayStore();
      }
    }

    return valid;
  }
}
