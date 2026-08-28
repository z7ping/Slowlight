import 'dimension.dart';

class ObservationTag {
  final int id;
  final String name;
  final String icon;
  final String color;
  final String? dimensionKey;
  final bool isDefault;

  const ObservationTag({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.dimensionKey,
    this.isDefault = false,
  });

  DimensionDefinition? get dimension => DimensionCatalog.byKey(dimensionKey);

  factory ObservationTag.fromJson(Map<String, dynamic> json) {
    final rawDefault = json['is_default'];
    return ObservationTag(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '🏷️',
      color: json['color'] as String? ?? '#1890ff',
      dimensionKey: (json['dimension_key'] as String?)?.isEmpty == true
          ? null
          : json['dimension_key'] as String?,
      isDefault: rawDefault == true || rawDefault == 1,
    );
  }
}
