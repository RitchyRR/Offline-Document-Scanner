import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart' show Fluttertoast;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
import 'package:url_launcher/url_launcher.dart' show canLaunchUrl, launchUrl;

class FeedbackHelper {
  late SharedPreferences _prefs;
  FeedbackHelper() {
    initAsync();
  }
  initAsync() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool _ratingGiven = false;
  bool getRatingGiven() {
    return _ratingGiven;
  }

  bool showRatingPopupAfterExport() {
    return !(_prefs.getBool("firstExportHappendedSinceRatingActive") ?? false);
  }

  bool showRatingPopupWhileProcessing() {
    return !(_prefs.getBool("furtherProcessingHappendedSinceRatingActive") ??
            false) &&
        !showRatingPopupAfterExport(); // don't show processing popup and export popup right afeter one another
  }

  Future<void> _saveRatingGiven(int rating) async {
    _prefs.setBool("ratingGiven", _ratingGiven);
    _prefs.setInt("rating", rating);
    // Save date
    if (_ratingGiven) {
      String now = DateTime.now().toIso8601String();
      _prefs.setString("ratingGivenDate", now);
    }
  }

  Future<void> loadRatingGiven() async {
    _ratingGiven = _prefs.getBool("ratingGiven") ?? false;
    // Read date -> reenable ratings
    _reenableRatingsAfterTwoWeeks(_prefs);
    //_ratingGiven = false; //todo remove
  }

  _reenableRatingsAfterTwoWeeks(SharedPreferences prefs) async {
    bool reactivate = false;
    int? rating = prefs.getInt("rating");
    // only reenable if rating was not 5 stars
    if (_ratingGiven && rating != 5) {
      final String? ratingGivenDate = prefs.getString("ratingGivenDate");
      if (ratingGivenDate != null) {
        final unlockTime = DateTime.tryParse(ratingGivenDate);
        final now = DateTime.now();

        if (unlockTime != null && now.difference(unlockTime).inDays >= 14) {
          reactivate = true;
        }
      } else {
        reactivate = true;
      }
    }
    if (reactivate) {
      _ratingGiven = false;
      _saveRatingGiven(rating ?? 0);
      _activatePopupFlags();
    }
  }

  Future<void> _activatePopupFlags() async {
    _prefs.setBool("firstExportHappendedSinceRatingActive", false);
    _prefs.setBool("furtherProcessingHappendedSinceRatingActive", false);
  }

  Future<void> _disablePopupFlags() async {
    if (showRatingPopupAfterExport()) {
      _prefs.setBool("firstExportHappendedSinceRatingActive", true);
    } else if (showRatingPopupWhileProcessing()) {
      _prefs.setBool("furtherProcessingHappendedSinceRatingActive", true);
    }
  }

  void showRatingDialog(BuildContext context) {
    _disablePopupFlags();
    int rating = 0;
    showDialog(
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
                              _ratingGiven = true;
                              _saveRatingGiven(rating);
                              Navigator.pop(context);
                              if (rating == 5) {
                                _ratingGiven = true;
                                if (!await _redirectToPlayStore()) {
                                  Fluttertoast.showToast(
                                    msg: "Error: No connection :(",
                                  );
                                }
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
                        controller.text.isEmpty
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
    }
    return false;
  }
}
