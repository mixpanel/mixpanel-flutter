import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Screen comparing Material and Cupertino widgets
class PlatformWidgetsScreen extends StatefulWidget {
  const PlatformWidgetsScreen({super.key});

  @override
  State<PlatformWidgetsScreen> createState() => _PlatformWidgetsScreenState();
}

class _PlatformWidgetsScreenState extends State<PlatformWidgetsScreen> {
  bool _switchValue = false;
  double _sliderValue = 0.5;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Widgets Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Current Platform: ${_getPlatformName()}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildComparisonCard(
            'Buttons',
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Material', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Material'),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Cupertino', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    CupertinoButton.filled(
                      onPressed: () {},
                      child: const Text('Cupertino'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildComparisonCard(
            'Switches',
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Material', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Switch(
                      value: _switchValue,
                      onChanged: (value) =>
                          setState(() => _switchValue = value),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Cupertino', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    CupertinoSwitch(
                      value: _switchValue,
                      onChanged: (value) =>
                          setState(() => _switchValue = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildComparisonCard(
            'Sliders',
            Column(
              children: [
                const Text('Material', style: TextStyle(fontSize: 12)),
                Slider(
                  value: _sliderValue,
                  onChanged: (value) => setState(() => _sliderValue = value),
                ),
                const SizedBox(height: 16),
                const Text('Cupertino', style: TextStyle(fontSize: 12)),
                CupertinoSlider(
                  value: _sliderValue,
                  onChanged: (value) => setState(() => _sliderValue = value),
                ),
              ],
            ),
          ),
          _buildComparisonCard(
            'Activity Indicators',
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Material', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    const CircularProgressIndicator(),
                  ],
                ),
                Column(
                  children: [
                    const Text('Cupertino', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    const CupertinoActivityIndicator(),
                  ],
                ),
              ],
            ),
          ),
          _buildComparisonCard(
            'Date/Time Pickers',
            Column(
              children: [
                ElevatedButton(
                  onPressed: _showMaterialDatePicker,
                  child: const Text('Material Date Picker'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _showMaterialTimePicker,
                  child: const Text('Material Time Picker'),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: _showCupertinoDatePicker,
                  child: const Text('Cupertino Date Picker'),
                ),
              ],
            ),
          ),
          _buildComparisonCard(
            'Alerts/Dialogs',
            Column(
              children: [
                ElevatedButton(
                  onPressed: _showMaterialDialog,
                  child: const Text('Material Alert Dialog'),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: _showCupertinoDialog,
                  child: const Text('Cupertino Alert Dialog'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard(String title, Widget content) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }

  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  Future<void> _showMaterialDatePicker() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _showMaterialTimePicker() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  void _showCupertinoDatePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 250,
        color: Colors.white,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.dateAndTime,
          initialDateTime: _selectedDate,
          onDateTimeChanged: (date) => setState(() => _selectedDate = date),
        ),
      ),
    );
  }

  void _showMaterialDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Material Dialog'),
        content: const Text('This is a Material Design alert dialog.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCupertinoDialog() {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Cupertino Dialog'),
        content: const Text('This is a Cupertino-style alert dialog.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
