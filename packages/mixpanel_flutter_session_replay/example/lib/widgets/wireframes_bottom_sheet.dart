import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:provider/provider.dart';

import '../models/wireframe_model.dart';

/// Bottom sheet showing the most recent wireframe frame delivered to
/// [DebugOptions.wireframeEmitter].
///
/// This is the on-device answer to "what text is wireframe capture actually
/// sending for this screen, and why was each element kept or masked?" — the
/// per-element [MaskDecision] is what makes a masking regression visible
/// without reading a console.
class WireframesBottomSheet extends StatelessWidget {
  const WireframesBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WireframeModel>(
      builder: (context, wireframeVm, child) {
        final snapshot = wireframeVm.latest;

        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              _buildHeader(context, wireframeVm, snapshot),
              const Divider(height: 1),
              if (snapshot != null) _buildSummary(context, snapshot),
              Expanded(
                child: snapshot == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'No wireframe frames yet.\n\n'
                            'Enable "Enable Wireframes" and "Wireframe Debug '
                            'Emitter" on the config screen, then start '
                            'recording.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      )
                    : snapshot.elements.isEmpty
                    ? const Center(
                        child: Text(
                          'Frame captured, but no elements',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: snapshot.elements.length,
                        itemBuilder: (context, index) {
                          return _buildElement(snapshot.elements[index]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WireframeModel wireframeVm,
    WireframeSnapshot? snapshot,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.grid_on, size: 24),
          const SizedBox(width: 12),
          Text(
            'Wireframes',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // Copy the raw debug JSON — the same string the emitter debugPrints.
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: snapshot == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: snapshot.toJson()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Snapshot JSON copied')),
                    );
                  },
            tooltip: 'Copy JSON',
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: wireframeVm.clear,
            tooltip: 'Clear',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, WireframeSnapshot snapshot) {
    final time = DateFormat(
      'HH:mm:ss.SSS',
    ).format(DateTime.fromMillisecondsSinceEpoch(snapshot.timestamp));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '${snapshot.elements.length} elements  ·  '
            '${snapshot.viewport[0]}×${snapshot.viewport[1]}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildElement(WireframeSnapshotElement element) {
    final color = _colorForDecision(element.maskDecision);
    final text = element.text;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                element.role.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _decisionLabel(element.maskDecision),
                style: TextStyle(fontSize: 10, color: color),
              ),
              const Spacer(),
              Text(
                '[${element.bounds.join(', ')}]',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            text == null ? '(no text)' : '"$text"',
            style: TextStyle(
              fontSize: 12,
              fontStyle: text == null ? FontStyle.italic : FontStyle.normal,
              color: text == null ? Colors.grey : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// Green = text shipped untouched, blue = developer-authored, orange =
  /// rewritten by a rule, red = text removed. Scanning the sheet for anything
  /// green that should not be is the fastest masking check available.
  Color _colorForDecision(MaskDecision decision) {
    switch (decision) {
      case MaskDecision.none:
        return Colors.green;
      case MaskDecision.declared:
        return Colors.blue;
      case MaskDecision.ruleRedact:
        return Colors.orange;
      case MaskDecision.explicit:
      case MaskDecision.auto:
      case MaskDecision.textEntry:
      case MaskDecision.geometric:
      case MaskDecision.ruleStrip:
        return Colors.red;
    }
  }

  String _decisionLabel(MaskDecision decision) {
    switch (decision) {
      case MaskDecision.none:
        return 'NONE';
      case MaskDecision.declared:
        return 'DECLARED';
      case MaskDecision.explicit:
        return 'EXPLICIT';
      case MaskDecision.auto:
        return 'AUTO';
      case MaskDecision.textEntry:
        return 'TEXT_ENTRY';
      case MaskDecision.geometric:
        return 'GEOMETRIC';
      case MaskDecision.ruleStrip:
        return 'RULE_STRIP';
      case MaskDecision.ruleRedact:
        return 'RULE_REDACT';
    }
  }
}
