import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:provider/provider.dart';

import '../models/log_model.dart';

/// Bottom sheet displaying live SDK logs
class LogsBottomSheet extends StatefulWidget {
  const LogsBottomSheet({super.key});

  @override
  State<LogsBottomSheet> createState() => _LogsBottomSheetState();
}

class _LogsBottomSheetState extends State<LogsBottomSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  int _previousLogCount = 0;
  bool _isAutoScrolling = false;

  @override
  void initState() {
    super.initState();

    // Listen to scroll events to determine if user is manually scrolling
    _scrollController.addListener(() {
      // Don't update auto-scroll state while we're auto-scrolling
      if (_isAutoScrolling || !_scrollController.hasClients) {
        return;
      }

      // Check if we're at the bottom (within 50 pixels of max scroll extent)
      final position = _scrollController.position;
      final isAtBottom = position.pixels >= position.maxScrollExtent - 50;
      if (_autoScroll != isAtBottom) {
        setState(() {
          _autoScroll = isAtBottom;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients || !_autoScroll) {
      return;
    }

    _isAutoScrolling = true;

    // Use jumpTo for instant scroll without animation
    // This prevents the scroll listener from firing during animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      _isAutoScrolling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LogModel>(
      builder: (context, logVm, child) {
        // Auto-scroll to bottom when new logs arrive (if auto-scroll is enabled)
        if (_autoScroll && logVm.filteredLogs.length > _previousLogCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
        _previousLogCount = logVm.filteredLogs.length;

        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              _buildHeader(context, logVm),
              const Divider(height: 1),
              Expanded(
                child: logVm.filteredLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'No logs yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: logVm.filteredLogs.length,
                        itemBuilder: (context, index) {
                          // Show logs in chronological order, latest at bottom
                          final log = logVm.filteredLogs[index];
                          return _buildLogEntry(log);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, LogModel logVm) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.list_alt, size: 24),
          const SizedBox(width: 12),
          Text(
            'SDK Logs',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // Log level filter
          DropdownButton<LogLevel>(
            value: logVm.filterLevel,
            underline: const SizedBox(),
            items: LogLevel.values.map((level) {
              return DropdownMenuItem(
                value: level,
                child: Text(
                  level.name.toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
              );
            }).toList(),
            onChanged: (level) {
              if (level != null) logVm.setFilterLevel(level);
            },
          ),
          const SizedBox(width: 8),
          // Clear button
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: logVm.clearLogs,
            tooltip: 'Clear logs',
          ),
          // Close button
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(dynamic log) {
    final color = _getColorForLevel(log.level);
    final icon = _getIconForLevel(log.level);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.message, style: const TextStyle(fontSize: 12)),
                if (log.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Error: ${log.error}',
                      style: TextStyle(fontSize: 10, color: Colors.red[700]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('HH:mm:ss.SSS').format(log.timestamp),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Color _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Colors.red;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.none:
        return Colors.black;
    }
  }

  IconData _getIconForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Icons.error;
      case LogLevel.warning:
        return Icons.warning;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.debug:
        return Icons.bug_report;
      case LogLevel.none:
        return Icons.block;
    }
  }
}
