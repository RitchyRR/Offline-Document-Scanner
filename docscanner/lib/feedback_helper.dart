import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart' show Fluttertoast;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
import 'package:url_launcher/url_launcher.dart' show canLaunchUrl, launchUrl;

enum FeedbackState { init, afterFirstExport, afterFirstProcessing, hidden }

class FeedbackHelper {
  FeedbackState state = FeedbackState.init;
  FeedbackHelper() {
    initAsync();
  }
  initAsync() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool("ratingGiven") ?? false == true) {
      state = FeedbackState.hidden;
      _reenableRatingsAfterTwoWeeks(prefs);
    }
  }

  bool getFeedbackHidden() {
    return state == FeedbackState.hidden;
  }

  bool getShowRatingPopupAfterExport() {
    bool show = state == FeedbackState.init;
    _getShowRatingPopupAfterExport(show);
    return show;
  }

  _getShowRatingPopupAfterExport(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    if (show) {
      prefs.setBool("firstExportHappendedSinceRatingActive", true);
    }
    updateState();
  }

  bool getShowRatingPopupWhileProcessing() {
    bool show = state == FeedbackState.afterFirstExport;
    _getShowRatingPopupWhileProcessing(show);
    return show;
  }

  _getShowRatingPopupWhileProcessing(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    if (show) {
      prefs.setBool("furtherProcessingHappendedSinceRatingActive", true);
    }
    updateState();
  }

  getShowRatingInAppbar() {
    return state == FeedbackState.afterFirstExport ||
        state == FeedbackState.afterFirstProcessing;
  }

  updateState() async {
    final prefs = await SharedPreferences.getInstance();
    if (state == FeedbackState.hidden) return;
    state = FeedbackState.init;
    if (prefs.getBool("firstExportHappendedSinceRatingActive") ?? false) {
      state = FeedbackState.afterFirstExport;
    }
    if (prefs.getBool("furtherProcessingHappendedSinceRatingActive") ?? false) {
      state = FeedbackState.afterFirstProcessing;
    }
  }

  Future<void> _saveRatingGiven(bool ratingGivenIn, int ratingIn) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("ratingGiven", ratingGivenIn);
    prefs.setInt("rating", ratingIn);
    // Save date
    if (ratingGivenIn) {
      String now = DateTime.now().toIso8601String();
      prefs.setString("ratingGivenDate", now);
      _disablePopupFlags();
    }
    updateState();
  }

  _reenableRatingsAfterTwoWeeks(SharedPreferences prefs) async {
    bool reactivate = false;
    int? rating = prefs.getInt("rating");
    // only reenable if rating was not 5 stars
    if (state == FeedbackState.hidden && rating != 5) {
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
      _saveRatingGiven(false, rating ?? 0);
      _resetState();
    }
    updateState();
  }

  Future<void> _resetState() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("firstExportHappendedSinceRatingActive", false);
    prefs.setBool("furtherProcessingHappendedSinceRatingActive", false);
    state = FeedbackState.init;
  }

  Future<void> _disablePopupFlags() async {
    final prefs = await SharedPreferences.getInstance();
    if (getShowRatingPopupAfterExport()) {
      prefs.setBool("firstExportHappendedSinceRatingActive", true);
    } else if (getShowRatingPopupWhileProcessing()) {
      prefs.setBool("furtherProcessingHappendedSinceRatingActive", true);
    }
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
                              _saveRatingGiven(true, rating);
                              Navigator.pop(context);
                              if (rating == 5) {
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
