import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:developer' as dev;
import 'dart:io' show Platform;
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
    _readFeedbackState();
    if (state == FeedbackState.init) {
      _reenableRatingsAfterTwoWeeks();
    }
  }

  _readFeedbackState() async {
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
    bool can = state == FeedbackState.init;
    state = FeedbackState.afterFirstExport;
    _writeFeedbackState();
    return can;
  }

  bool canShowProcessingPopup() {
    bool can = state == FeedbackState.afterFirstExport;
    state = FeedbackState.afterFirstProcessing;
    _writeFeedbackState();
    return can;
  }

  bool canShowInAppbar() {
    return state == FeedbackState.afterFirstExport ||
        state == FeedbackState.afterFirstProcessing;
  }

  Future<void> _writeRating(int? newRating) async {
    final prefs = await SharedPreferences.getInstance();

    // Save date
    if (newRating != null) {
      prefs.setInt("rating", newRating);
      String now = DateTime.now().toIso8601String();
      prefs.setString("ratingDate", now);
      state = FeedbackState.hidden;
    } else {
      state = FeedbackState.init;
    }
    _writeFeedbackState();
  }

  _reenableRatingsAfterTwoWeeks() async {
    final prefs = await SharedPreferences.getInstance();
    bool reactivate = false;
    int? rating = prefs.getInt("rating");
    // only reenable if rating was not 5 stars
    if (state == FeedbackState.hidden && rating != 5) {
      final String? ratingDate = prefs.getString("ratingDate");
      if (ratingDate != null) {
        final unlockTime = DateTime.tryParse(ratingDate);
        final now = DateTime.now();

        if (unlockTime != null && now.difference(unlockTime).inDays >= 14) {
          reactivate = true;
        }
      } else {
        reactivate = true;
      }
    }
    if (reactivate) {
      _writeRating(null);
    }
    _writeFeedbackState();
  }

  Future<void> showRatingDialog(BuildContext context) async {
    int rating = 0;
    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('Rate our App'),
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
                    child: Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed:
                        rating == 0
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
                    child: Text('Next'),
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
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('Give Feedback'),
                content: TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText:
                        "What would you like to see?\n"
                        "What is missing?\n"
                        "What went wrong?\n",
                  ),
                  onChanged: (text) {
                    setState(() {});
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed:
                        controller.text.trim().isEmpty
                            ? null
                            : () {
                              final feedback = controller.text;
                              dev.log('User feedback: $feedback');
                              _sendFeedbackByEmail(feedback, rating);
                              Navigator.pop(context);
                            },
                    child: Text('Send'),
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
    final String email = 'R.R.appdev.public@gmail.com';

    final Uri emailUri = Uri.parse('mailto:$email?subject=$subject&body=$body');

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      Fluttertoast.showToast(msg: "Thank you for your feedback!");
      dev.log('To $email: $message');
    } else {
      Fluttertoast.showToast(msg: "Error: No connection :(");
      dev.log('Error, sendFeedbackByEmail: No connection :(');
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
      scheme: 'https',
      host: 'play.google.com',
      path: '/store/apps/details',
      queryParameters: {'id': 'com.rrapps.docscanner'},
    );
    dev.log("Opening URL: $url");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
      return true;
    } else {
      Fluttertoast.showToast(msg: "Error: Can't launch Play Store.");
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
    for (var char in signature.characters) {
      final int? firstInt = int.tryParse(char);
      if (firstInt != null) {
        sigBigInt = sigBigInt - BigInt.from(firstInt);
        break;
      }
    }
    final multiplied = sigBigInt * BigInt.from(multiplier);
    final hashed =
        sha256.convert(utf8.encode(multiplied.toString())).toString();

    bool valid = false;
    if (Platform.isAndroid && installer == "com.android.vending") {
      // Play Store signature
      const expectedHash =
          "9a2176b17a7b4a5bd02bd00645eb16d38dd2343a8723458df3b75be796cb34c4";
      valid = hashed == expectedHash;
    } else if (Platform.isAndroid && installer == "com.android.shell") {
      // Debugging signature
      const expectedHash =
          "301e6db07d6bae3b8cfd4d0a0a5f5ee523e0938bd0cc6dedde5515ef32b90ec2";
      valid = hashed == expectedHash;
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
