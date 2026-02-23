class MarkerDto {
  final int id;
  final String title;
  final String note;
  final double lat;
  final double lng;
  final bool visible;
  final bool canEdit;
  final bool canDelete;
  final String ownerUsername;

  const MarkerDto({
    required this.id,
    required this.title,
    required this.note,
    required this.lat,
    required this.lng,
    required this.visible,
    required this.canEdit,
    required this.canDelete,
    required this.ownerUsername,
  });

  factory MarkerDto.fromJson(Map<String, dynamic> json) {
    return MarkerDto(
      id: json['id'] as int,
      title: json['title'] as String,
      note: (json['note'] as String?) ?? '',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      visible: (json['visible'] as bool?) ?? true,
      canEdit: (json['can_edit'] as bool?) ?? true,
      canDelete: (json['can_delete'] as bool?) ?? true,
      ownerUsername: (json['owner_username'] as String?) ?? '',
    );
  }
}
