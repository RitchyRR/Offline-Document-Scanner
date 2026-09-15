import 'dart:async';
import 'dart:developer' as dev;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app/app_globals.dart';
import '../../app/feedback_helper.dart';
import '../../app/global_notifier.dart';
import '../settings/default_thumbnail_filter.dart';

final InAppPurchase _iap = InAppPurchase.instance;
final List<ProductDetails> _products = [];
Future<void> initStoreInfo() async {
  final bool available = await _iap.isAvailable();
  if (!available) {
    dev.log("Warning, initStoreInfo: In-App-Purchases not available");
    return;
  }
  _listenToPurchaseUpdates();

  const Set<String> productNames = {"pro_upgrade"};
  final ProductDetailsResponse response = await _iap.queryProductDetails(
    productNames,
  );

  if (response.notFoundIDs.isNotEmpty) {
    dev.log(
      "Warning, initStoreInfo: Product IDs not forund: ${response.notFoundIDs}",
    );
  }

  if (!available || response.notFoundIDs.contains("pro_upgrade")) {
    await _deactivateProAfterWeekOffline();
  }

  _products.addAll(response.productDetails);
  _iap.restorePurchases(); // activate _listenToPurchaseUpdates() // does not work for license testing
}

Future<void> _deactivateProAfterWeekOffline() async {
  final sStorage = FlutterSecureStorage();

  final bool isSaved = "true" == await sStorage.read(key: "proUnlocked");
  final String? savedDate = await sStorage.read(key: "proUnlockedDate");

  if (isSaved && savedDate != null) {
    final unlockTime = DateTime.tryParse(savedDate);
    final now = DateTime.now();

    if (unlockTime != null && now.difference(unlockTime).inDays < 7) {
      _setPro(true); // still within grace period
    } else {
      _setPro(false); // expired or unreadable
    }
  } else {
    _setPro(false); // no record
  }
}

StreamSubscription<List<PurchaseDetails>>? _subscription;
void _listenToPurchaseUpdates() {
  _subscription = _iap.purchaseStream.listen(
    (purchases) async {
      if (!await feedbackHelper.isAppValid()) _setPro(false);
      for (var purchase in purchases) {
        switch (purchase.productID) {
          case "pro_upgrade":
            switch (purchase.status) {
              case PurchaseStatus.purchased:
              case PurchaseStatus.restored:
                if (purchase.pendingCompletePurchase) {
                  await _iap.completePurchase(purchase);
                }
                if (purchase.verificationData.source == "google_play") {
                  _setPro(true);
                }
                break;
              case PurchaseStatus.error:
                if (purchase.error != null) {
                  if (purchase.error!.message ==
                          "BillingResponse.itemAlreadyOwned" &&
                      purchase.verificationData.source == "google_play") {
                    _setPro(true);
                  } else {
                    _setPro(false);
                  }
                }
              case PurchaseStatus.pending:
                break;
              case PurchaseStatus.canceled:
                _setPro(false);
                break;
            }
            break;
          default:
            switch (purchase.status) {
              case PurchaseStatus.error:
                if (purchase.error != null) {
                  if (purchase.error!.message ==
                          "BillingResponse.itemAlreadyOwned" &&
                      purchase.verificationData.source == "google_play") {
                    _setPro(true);
                  }
                }
                break;
              default:
                break;
            }
            break;
        }
      }
    },
    onDone: () => _subscription?.cancel(),
    onError: (error) {
      dev.log("purchaseStream error: $error");
    },
  );
}

Future<bool> _buyPro() async {
  ProductDetails proUpgrade;
  try {
    proUpgrade = _products[0];
  } catch (e) {
    dev.log("Warning, buyPro: proUpgrade not available: $e");
    return false;
  }
  final PurchaseParam purchaseParam = PurchaseParam(productDetails: proUpgrade);
  if (!await _iap.buyNonConsumable(purchaseParam: purchaseParam)) {
    dev.log("Warning, buyPro: Request not sent successfully.");
    return false;
  }
  return true;
}

Future<String?> _getProPrice() async {
  ProductDetails proUpgrade;
  try {
    proUpgrade = _products[0];
  } catch (e) {
    dev.log("Warning, getProPrice: proUpgrade not available: $e");
    return null;
  }
  return proUpgrade.price;
}

Future<bool> proPopup(BuildContext context) async {
  String? proPrice = await _getProPrice();
  if (!context.mounted) return false;
  bool? selectBuyPro = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              g.proUnlocked ? Icons.verified : Icons.lock,
              color: Theme.of(context).colorScheme.onSurface,
              size: 30,
            ),
            SizedBox(width: 12),
            Flexible(
              child: Text(
                g.proUnlocked
                    ? tr("documents.menu.pro1")
                    : tr("documents.menu.pro2"),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  " •  ",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                Expanded(child: Text(tr("popup.pro.bp1"))),
              ],
            ),
            SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  " •  ",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                Expanded(child: Text(tr("popup.pro.bp2"))),
              ],
            ),
            SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  " •  ",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                Expanded(child: Text(tr("popup.pro.bp3"))),
              ],
            ),

            g.proUnlocked
                ? Text(tr("popup.pro.thanksText"))
                : Center(
                    child: SizedBox(
                      width: 200,
                      child: Text(
                        textAlign: TextAlign.center,
                        "\n${proPrice ?? ""}\n\n${tr("popup.pro.priceText")}",
                      ),
                    ),
                  ),
          ],
        ),
        actions: [
          g.proUnlocked
              ? ElevatedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    tr("popup.ok"),
                    style: TextStyle(color: Colors.green),
                  ),
                )
              : TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr("popup.cancel")),
                ),
          g.proUnlocked
              ? SizedBox()
              : ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    tr("popup.purchase"),
                    style: TextStyle(color: Colors.green),
                  ),
                ),
        ],
      );
    },
  );
  if (selectBuyPro == true) {
    if (await _buyPro()) {
      await Future.delayed(Duration(milliseconds: 400));
      if (context.mounted && g.proUnlocked) {
        showDefaultThumbnailVersionDialog(context, unlockPro: proPopup);
      }
      return true;
    }
  }
  return false;
}

Future<void> _setPro(final bool proUnlockedIn) async {
  if (proUnlockedIn && !await feedbackHelper.isAppValid()) {
    _setPro(false);
    return;
  }

  bool showMessages = true;
  if (g.proUnlocked == proUnlockedIn) showMessages = false;
  g.proUnlocked = proUnlockedIn;

  final sStorage = FlutterSecureStorage();
  sStorage.write(
    key: "proUnlocked",
    value: proUnlockedIn == true ? "true" : "false",
  );

  if (proUnlockedIn) {
    final now = DateTime.now().toIso8601String();
    sStorage.write(key: "proUnlockedDate", value: now);
  }

  if (showMessages) {
    Fluttertoast.showToast(
      msg: proUnlockedIn ? tr("toast.proUnlocked") : tr("toast.proDisabled"),
    );
  }
  globalNotifier.triggerEvent(NotifierEvent.setState);
  await loadDefaultThumbnailVersion();
}
