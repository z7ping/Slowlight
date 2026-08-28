/// Slowlight 固定的长期观察维度。
///
/// Dimension 是产品坐标，不是用户标签；用户可编辑的 SystemTag 只负责分类，
/// 可通过 dimension_key 归属到某个维度。
enum DimensionKey {
  body,
  cognition,
  output,
  relationship;

  static DimensionKey? fromValue(String? value) {
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }
}

class DimensionDefinition {
  final DimensionKey key;
  final String name;
  final String icon;
  final String color;

  const DimensionDefinition({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
  });

  String get keyValue => key.name;

  Map<String, dynamic> toJson() => {
        'key': keyValue,
        'name': name,
        'icon': icon,
        'color': color,
      };
}

class DimensionCatalog {
  const DimensionCatalog._();

  static const all = <DimensionDefinition>[
    DimensionDefinition(
      key: DimensionKey.body,
      name: '身体',
      icon: '💪',
      color: '#52c41a',
    ),
    DimensionDefinition(
      key: DimensionKey.cognition,
      name: '认知',
      icon: '🧠',
      color: '#1890ff',
    ),
    DimensionDefinition(
      key: DimensionKey.output,
      name: '产出',
      icon: '🎯',
      color: '#722ed1',
    ),
    DimensionDefinition(
      key: DimensionKey.relationship,
      name: '关系',
      icon: '❤️',
      color: '#eb2f96',
    ),
  ];

  static DimensionDefinition? byKey(String? key) {
    for (final item in all) {
      if (item.keyValue == key) return item;
    }
    return null;
  }

  /// 旧版本把四维度直接实现成 SystemTag；这里只用于一次性兼容迁移。
  static String? legacyKeyForTagName(String? name) {
    for (final item in all) {
      if (item.name == name) return item.keyValue;
    }
    return null;
  }
}
