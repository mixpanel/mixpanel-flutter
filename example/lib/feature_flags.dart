import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_example/widget.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import 'analytics.dart';

class FeatureFlagsScreen extends StatefulWidget {
  @override
  _FeatureFlagsScreenState createState() => _FeatureFlagsScreenState();
}

class _FeatureFlagsScreenState extends State<FeatureFlagsScreen> {
  late final Mixpanel _mixpanel;
  late final FeatureFlags _flags;

  @override
  initState() {
    super.initState();
    _initMixpanel();
  }

  Future<void> _initMixpanel() async {
    _mixpanel = await MixpanelManager.init();
    _flags = _mixpanel.getFeatureFlags();
  }

  void _showAlert(BuildContext context, String title, String alertText) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Text(alertText),
              ),
              actions: [
                TextButton(
                  child: Text("OK"),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xff4f44e0),
        title: Text("Feature Flags"),
      ),
      body: Center(
          child: ListView(
        children: [
          SizedBox(
            height: 40,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Check Flags Ready',
              onPressed: () async {
                final ready = await _flags.areFlagsReady();
                _showAlert(context, "Flags Ready", "areFlagsReady: $ready");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Boolean Flag (isEnabled)',
              onPressed: () async {
                final enabled = await _flags.isEnabled('new_feature', false);
                _showAlert(
                    context, "Boolean Flag", "new_feature enabled: $enabled");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Boolean Flag Sync',
              onPressed: () async {
                final enabled = await _flags.isEnabledSync('new_feature', false);
                _showAlert(context, "Boolean Flag Sync",
                    "new_feature enabled (sync): $enabled");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Variant Value',
              onPressed: () async {
                final value =
                    await _flags.getVariantValue('button_color', 'blue');
                _showAlert(
                    context, "Variant Value", "button_color value: $value");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Variant Value Sync',
              onPressed: () async {
                final value =
                    await _flags.getVariantValueSync('button_color', 'blue');
                _showAlert(context, "Variant Value Sync",
                    "button_color value (sync): $value");
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Full Variant',
              onPressed: () async {
                final fallback =
                    MixpanelFlagVariant.fallback('experiment_variant', 'control');
                final variant =
                    await _flags.getVariant('experiment_variant', fallback);
                final jsonString = jsonEncode({
                  'key': variant.key,
                  'value': variant.value,
                  'experimentId': variant.experimentId,
                  'isExperimentActive': variant.isExperimentActive,
                  'isQaTester': variant.isQaTester,
                });
                _showAlert(context, "Full Variant", jsonString);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Full Variant Sync',
              onPressed: () async {
                final fallback =
                    MixpanelFlagVariant.fallback('experiment_variant', 'control');
                final variant =
                    await _flags.getVariantSync('experiment_variant', fallback);
                final jsonString = jsonEncode({
                  'key': variant.key,
                  'value': variant.value,
                  'experimentId': variant.experimentId,
                  'isExperimentActive': variant.isExperimentActive,
                  'isQaTester': variant.isQaTester,
                });
                _showAlert(context, "Full Variant Sync", jsonString);
              },
            ),
          ),
          SizedBox(
            height: 20,
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Update Context',
              onPressed: () async {
                await _flags.updateContext({
                  'user_tier': 'premium',
                  'country': 'US',
                });
                _showAlert(context, "Context Updated",
                    "Context updated with user_tier: premium, country: US");
              },
            ),
          ),
          SizedBox(
            height: 40,
          ),
        ],
      )),
    );
  }
}
