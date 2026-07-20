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

  // Text controllers for flag name inputs
  final _boolFlagController = TextEditingController(text: 'sample-bool-flag');
  final _variantValueController = TextEditingController(text: 'sample-flag');
  final _fullVariantController =
      TextEditingController(text: 'ww_advanced_experiments_qa_2');
  final _fallbackTestController =
      TextEditingController(text: 'non-existent-flag-12345');

  @override
  void initState() {
    super.initState();
    _initMixpanel();
  }

  @override
  void dispose() {
    _boolFlagController.dispose();
    _variantValueController.dispose();
    _fullVariantController.dispose();
    _fallbackTestController.dispose();
    super.dispose();
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
                  child: const Text("OK"),
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

  Widget _buildFlagInput(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              hintText: 'Enter flag name',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff4f44e0),
        title: const Text("Feature Flags"),
      ),
      body: Center(
          child: ListView(
        children: [
          const SizedBox(height: 40),
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
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Divider(),
          ),
          const SizedBox(height: 10),
          _buildFlagInput('Test Fallback Flag Name:', _fallbackTestController),
          const SizedBox(height: 10),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Test Fallback Reasons',
              onPressed: () async {
                final flagName = _fallbackTestController.text.trim();
                if (flagName.isEmpty) {
                  _showAlert(context, "Error", "Please enter a flag name");
                  return;
                }

                final fallback =
                    MixpanelFlagVariant.fallback(flagName, 'default-value');
                final variant = await _flags.getVariant(flagName, fallback);

                final src = variant.source;
                String reasonDetails = '';

                if (src is FallbackSource) {
                  reasonDetails =
                      '''Fallback Reason: ${(src.reason)}''';
                } else if (src is NetworkSource) {
                  reasonDetails = 'Flag was loaded from network successfully';
                } else if (src is PersistenceSource) {
                  reasonDetails =
                      'Flag was loaded from local cache (persisted at: ${src.persistedAt})';
                }

                final alertText = '''Flag: $flagName
Value: ${variant.value}
Source: ${src.runtimeType}

$reasonDetails''';

                _showAlert(context, "Fallback Reason Demo", alertText);
              },
            ),
          ),
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Divider(),
          ),
          const SizedBox(height: 10),
          _buildFlagInput('Boolean Flag Name:', _boolFlagController),
          const SizedBox(height: 10),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Boolean Flag (isEnabled)',
              onPressed: () async {
                final flagName = _boolFlagController.text.trim();
                if (flagName.isEmpty) {
                  _showAlert(context, "Error", "Please enter a flag name");
                  return;
                }

                const expected = true;
                final actual = await _flags.isEnabled(flagName, false);
                _showAlert(context, "Boolean Flag: $flagName",
                    _formatComparison('isEnabled', expected, actual));
              },
            ),
          ),
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Divider(),
          ),
          const SizedBox(height: 10),
          _buildFlagInput('Variant Value Flag Name:', _variantValueController),
          const SizedBox(height: 10),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Variant Value',
              onPressed: () async {
                final flagName = _variantValueController.text.trim();
                if (flagName.isEmpty) {
                  _showAlert(context, "Error", "Please enter a flag name");
                  return;
                }

                const expected = 'test';
                final actual = await _flags.getVariantValue(flagName, 'fallback');
                _showAlert(context, "Variant Value: $flagName",
                    _formatComparison('getVariantValue', expected, actual));
              },
            ),
          ),
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Divider(),
          ),
          const SizedBox(height: 10),
          _buildFlagInput('Full Variant Flag Name:', _fullVariantController),
          const SizedBox(height: 10),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Get Full Variant',
              onPressed: () async {
                final flagName = _fullVariantController.text.trim();
                if (flagName.isEmpty) {
                  _showAlert(context, "Error", "Please enter a flag name");
                  return;
                }

                final fallback = MixpanelFlagVariant.fallback(flagName, 'control');
                final variant = await _flags.getVariant(flagName, fallback);

                final src = variant.source;
                final sourceLabel = src is PersistenceSource
                    ? 'persistence (persistedAt: ${src.persistedAt})'
                    : src is NetworkSource
                        ? 'network'
                        : src is FallbackSource
                            ? 'fallback (reason: ${(src.reason)})'
                            : 'unknown';

                final alertText = '''Flag: $flagName

Details:
  key: ${variant.key}
  value: ${variant.value}
  experimentId: ${variant.experimentId ?? 'null'}
  isExperimentActive: ${variant.isExperimentActive ?? 'null'}
  isQaTester: ${variant.isQaTester ?? 'null'}
  source: $sourceLabel''';

                _showAlert(context, "Full Variant: $flagName", alertText);
              },
            ),
          ),
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Divider(),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: MixpanelButton(
              text: 'Load Flags',
              onPressed: () async {
                await _flags.loadFlags();
                _showAlert(
                    context, "Load Flags", "Flags reload triggered successfully");
              },
            ),
          ),
          const SizedBox(height: 40),
        ],
      )),
    );
  }
}
