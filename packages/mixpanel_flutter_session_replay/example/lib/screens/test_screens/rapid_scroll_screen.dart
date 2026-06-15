import 'package:flutter/material.dart';

/// Screen with 1000+ items for performance testing
class RapidScrollScreen extends StatelessWidget {
  const RapidScrollScreen({super.key});

  static const int itemCount = 1000;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapid Scroll / Performance Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _getColor(index),
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            title: Text('Item ${index + 1}'),
            subtitle: Text('Subtitle for item ${index + 1} - Index: $index'),
            trailing: _getTrailingIcon(index),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Tapped item ${index + 1}'),
                  duration: const Duration(milliseconds: 500),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.info),
        label: Text('$itemCount Items'),
      ),
    );
  }

  Color _getColor(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.cyan,
      Colors.lime,
      Colors.purple,
      Colors.teal,
      Colors.lightGreen,
      Colors.indigo,
    ];
    return colors[index % colors.length];
  }

  Icon _getTrailingIcon(int index) {
    final icons = [
      Icons.star,
      Icons.favorite,
      Icons.check_circle,
      Icons.bookmark,
      Icons.thumb_up,
      Icons.message,
    ];
    return Icon(icons[index % icons.length]);
  }
}
