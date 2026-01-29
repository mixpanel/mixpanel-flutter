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

  String _formatComparison(String label, dynamic expected, dynamic actual) {
    final match = expected == actual ? '✓' : '✗';
    return '$label:\n  Expected: $expected\n  Actual: $actual  $match';
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
                const expected = true;
                final actual = await _flags.isEnabled('sample-bool-flag', false);
                _showAlert(
                    context,
                    "Boolean Flag: sample-bool-flag",
                    _formatComparison('isEnabled', expected, actual));
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
                const expected = true;
                final actual = await _flags.isEnabledSync('sample-bool-flag', false);
                _showAlert(
                    context,
                    "Boolean Flag Sync: sample-bool-flag",
                    _formatComparison('isEnabledSync', expected, actual));
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
                const expected = 'test';
                final actual =
                    await _flags.getVariantValue('sample-flag', 'fallback');
                _showAlert(
                    context,
                    "Variant Value: sample-flag",
                    _formatComparison('getVariantValue', expected, actual));
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
                const expected = 'test';
                final actual =
                    await _flags.getVariantValueSync('sample-flag', 'fallback');
                _showAlert(
                    context,
                    "Variant Value Sync: sample-flag",
                    _formatComparison('getVariantValueSync', expected, actual));
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
                const flagName = 'ww_advanced_experiments_qa_2';
                const expectedKey = 'treatment';
                const expectedExperimentId =
                    'e6f697b4-2f23-4e9d-b772-49dd9103733c';
                const expectedIsExperimentActive = true;
                final fallback =
                    MixpanelFlagVariant.fallback(flagName, 'control');
                final variant = await _flags.getVariant(flagName, fallback);
                final keyMatch = variant.key == expectedKey ? '✓' : '✗';
                final expIdMatch =
                    variant.experimentId == expectedExperimentId ? '✓' : '✗';
                final activeMatch =
                    variant.isExperimentActive == expectedIsExperimentActive
                        ? '✓'
                        : '✗';
                final alertText = '''Expected:
  key: $expectedKey
  experimentId: $expectedExperimentId
  isExperimentActive: $expectedIsExperimentActive

Actual:
  key: ${variant.key}  $keyMatch
  value: ${variant.value}
  experimentId: ${variant.experimentId}  $expIdMatch
  isExperimentActive: ${variant.isExperimentActive}  $activeMatch
  isQaTester: ${variant.isQaTester}''';
                _showAlert(context, "Full Variant: $flagName", alertText);
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
                const flagName = 'ww_advanced_experiments_qa_2';
                const expectedKey = 'treatment';
                const expectedExperimentId =
                    'e6f697b4-2f23-4e9d-b772-49dd9103733c';
                const expectedIsExperimentActive = true;
                final fallback =
                    MixpanelFlagVariant.fallback(flagName, 'control');
                final variant = await _flags.getVariantSync(flagName, fallback);
                final keyMatch = variant.key == expectedKey ? '✓' : '✗';
                final expIdMatch =
                    variant.experimentId == expectedExperimentId ? '✓' : '✗';
                final activeMatch =
                    variant.isExperimentActive == expectedIsExperimentActive
                        ? '✓'
                        : '✗';
                final alertText = '''Expected:
  key: $expectedKey
  experimentId: $expectedExperimentId
  isExperimentActive: $expectedIsExperimentActive

Actual:
  key: ${variant.key}  $keyMatch
  value: ${variant.value}
  experimentId: ${variant.experimentId}  $expIdMatch
  isExperimentActive: ${variant.isExperimentActive}  $activeMatch
  isQaTester: ${variant.isQaTester}''';
                _showAlert(context, "Full Variant Sync: $flagName", alertText);
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
