import 'package:flutter/material.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

import '../../models/test_content.dart';
import '../../services/test_data_service.dart';

/// Screen displaying mixed content loaded from JSON
class MixedContentScreen extends StatefulWidget {
  const MixedContentScreen({super.key});

  @override
  State<MixedContentScreen> createState() => _MixedContentScreenState();
}

class _MixedContentScreenState extends State<MixedContentScreen> {
  late Future<TestData> _testDataFuture;

  @override
  void initState() {
    super.initState();
    _testDataFuture = TestDataService.loadTestData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mixed Content Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FutureBuilder<TestData>(
        future: _testDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.indigo, size: 48),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final testData = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: testData.sections.length,
            itemBuilder: (context, index) {
              final section = testData.sections[index];
              return _buildSection(section);
            },
          );
        },
      ),
    );
  }

  Widget _buildSection(TestSection section) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              section.description,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ...section.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildItem(item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(TestItem item) {
    Widget widget;

    if (item is TextItem) {
      widget = _buildTextItem(item);
    } else if (item is ImageItem) {
      widget = _buildImageItem(item);
    } else if (item is ContainerItem) {
      widget = _buildContainerItem(item);
    } else if (item is ListItem) {
      widget = _buildListItem(item);
    } else {
      widget = const Text('Unknown item type');
    }

    // Wrap with MixpanelMask or MixpanelUnmask based on masked property
    return item.masked ? MixpanelMask(child: widget) : widget;
  }

  Widget _buildTextItem(TextItem item) {
    return Text(
      item.content,
      style: TextStyle(
        fontSize: item.fontSize,
        fontWeight: item.fontWeight == 'bold'
            ? FontWeight.bold
            : FontWeight.normal,
        color: item.color != null
            ? Color(int.parse(item.color!.replaceFirst('#', '0xFF')))
            : Colors.black,
      ),
    );
  }

  Widget _buildImageItem(ImageItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: item.width ?? 200,
          height: item.height ?? 150,
          decoration: BoxDecoration(
            color: Color(int.parse(item.color.replaceFirst('#', '0xFF'))),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              item.label ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (item.label != null) ...[
          const SizedBox(height: 4),
          Text(
            item.label!,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _buildContainerItem(ContainerItem item) {
    return Container(
      padding: EdgeInsets.all(item.padding),
      decoration: BoxDecoration(
        color: item.backgroundColor != null
            ? Color(int.parse(item.backgroundColor!.replaceFirst('#', '0xFF')))
            : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: item.children
            .map(
              (child) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildItem(child),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildListItem(ListItem item) {
    return ListTile(
      leading: item.imageColor != null
          ? Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(
                  int.parse(item.imageColor!.replaceFirst('#', '0xFF')),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            )
          : null,
      title: Text(item.title),
      subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
      tileColor: Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
