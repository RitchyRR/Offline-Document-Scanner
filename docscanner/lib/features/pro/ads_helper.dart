import 'dart:async';
import 'dart:developer' as dev;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

final AdsHelper adsHelper = AdsHelper();

Future<bool> unlockDocumentWithAd(BuildContext context) async {
  final bool adWatched = await adsHelper.showRewardAd();
  if (adWatched) {
    Fluttertoast.showToast(msg: tr("toast.tmp_combiPfd"));
  }
  return adWatched;
}

Future<bool> unlockPageWithAd(BuildContext context) async {
  final bool adWatched = await adsHelper.showRewardAd();
  if (adWatched) {
    Fluttertoast.showToast(msg: tr("toast.tmp_proFilter"));
  }
  return adWatched;
}

class AdsHelper {
  AdsHelper() {
    _loadAdFuture = _loadRewardAd();
  }

  late Future<void> _loadAdFuture;
  RewardedAd? _ad;

  Future<void> _loadRewardAd() async {
    final completer = Completer<void>();
    RewardedAd.load(
      adUnitId: "ca-app-pub-6739996186409182/8967462940",
      request: AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _ad?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _loadRewardAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _loadRewardAd();
            },
          );
          completer.complete();
        },
        onAdFailedToLoad: (error) {
          dev.log("Warning: Failed to load reward ad: $error");
          Fluttertoast.showToast(msg: tr("toast.e_ad"));
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<bool> showRewardAd() async {
    final completer = Completer<bool>();
    await _loadAdFuture;
    if (_ad != null) {
      _ad!.show(
        onUserEarnedReward: (ad, reward) {
          dev.log("User earned reward: ${reward.type}");
          completer.complete(true);
        },
      );
    } else {
      dev.log("Warning: Ad not loaded yet.");
      Fluttertoast.showToast(msg: tr("toast.e_noAd"));
      completer.complete(false);
    }
    return completer.future;
  }
}
