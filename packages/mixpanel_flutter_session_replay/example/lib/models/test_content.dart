/// Root test data structure
class TestData {
  TestData({required this.version, required this.sections});

  final String version;
  final List<TestSection> sections;

  factory TestData.fromJson(Map<String, dynamic> json) {
    return TestData(
      version: json['version'] as String,
      sections: (json['sections'] as List)
          .map((s) => TestSection.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'sections': sections.map((s) => s.toJson()).toList(),
  };
}

/// A section of test items
class TestSection {
  TestSection({
    required this.id,
    required this.title,
    required this.description,
    required this.items,
  });

  final String id;
  final String title;
  final String description;
  final List<TestItem> items;

  factory TestSection.fromJson(Map<String, dynamic> json) {
    return TestSection(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      items: (json['items'] as List)
          .map((item) => TestItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

/// Base class for test items
abstract class TestItem {
  TestItem({required this.type, required this.masked});

  final String type;
  final bool masked;

  factory TestItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'text':
        return TextItem.fromJson(json);
      case 'image':
        return ImageItem.fromJson(json);
      case 'container':
        return ContainerItem.fromJson(json);
      case 'list_item':
        return ListItem.fromJson(json);
      default:
        throw Exception('Unknown test item type: $type');
    }
  }

  Map<String, dynamic> toJson();
}

/// Text content item
class TextItem extends TestItem {
  TextItem({
    required this.content,
    required super.masked,
    this.fontSize = 16,
    this.fontWeight = 'normal',
    this.color,
  }) : super(type: 'text');

  final String content;
  final double fontSize;
  final String fontWeight;
  final String? color;

  factory TextItem.fromJson(Map<String, dynamic> json) {
    return TextItem(
      content: json['content'] as String,
      masked: json['masked'] as bool,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16,
      fontWeight: json['fontWeight'] as String? ?? 'normal',
      color: json['color'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'content': content,
    'masked': masked,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    if (color != null) 'color': color,
  };
}

/// Image/colored container item
class ImageItem extends TestItem {
  ImageItem({
    required this.color,
    required super.masked,
    this.width,
    this.height,
    this.label,
  }) : super(type: 'image');

  final String color; // Hex color
  final double? width;
  final double? height;
  final String? label;

  factory ImageItem.fromJson(Map<String, dynamic> json) {
    return ImageItem(
      color: json['color'] as String,
      masked: json['masked'] as bool,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      label: json['label'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'color': color,
    'masked': masked,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (label != null) 'label': label,
  };
}

/// Container with nested items
class ContainerItem extends TestItem {
  ContainerItem({
    required super.masked,
    required this.children,
    this.padding = 16,
    this.backgroundColor,
  }) : super(type: 'container');

  final List<TestItem> children;
  final double padding;
  final String? backgroundColor;

  factory ContainerItem.fromJson(Map<String, dynamic> json) {
    return ContainerItem(
      masked: json['masked'] as bool,
      children: (json['children'] as List)
          .map((child) => TestItem.fromJson(child as Map<String, dynamic>))
          .toList(),
      padding: (json['padding'] as num?)?.toDouble() ?? 16,
      backgroundColor: json['backgroundColor'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'masked': masked,
    'children': children.map((child) => child.toJson()).toList(),
    'padding': padding,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
  };
}

/// List item (for scrollable lists)
class ListItem extends TestItem {
  ListItem({
    required this.title,
    required super.masked,
    this.subtitle,
    this.imageColor,
  }) : super(type: 'list_item');

  final String title;
  final String? subtitle;
  final String? imageColor; // Hex color for leading image

  factory ListItem.fromJson(Map<String, dynamic> json) {
    return ListItem(
      title: json['title'] as String,
      masked: json['masked'] as bool,
      subtitle: json['subtitle'] as String?,
      imageColor: json['imageColor'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'masked': masked,
    if (subtitle != null) 'subtitle': subtitle,
    if (imageColor != null) 'imageColor': imageColor,
  };
}
