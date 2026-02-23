import 'package:latlong2/latlong.dart';
import 'package:tencent_map_flutter/tencent_map_flutter.dart';

class Station {
  final String id;
  final String title;
  final String note;
  final LatLng position;
  final Bitmap? icon;
  final bool isCustom;
  final int? remoteId;
  final bool visible;
  final bool canEdit;
  final bool canDelete;
  final String ownerUsername;

  const Station({
    required this.id,
    required this.title,
    required this.note,
    required this.position,
    this.icon,
    this.isCustom = false,
    this.remoteId,
    this.visible = true,
    this.canEdit = true,
    this.canDelete = true,
    this.ownerUsername = '',
  });

  Station copyWith({
    String? id,
    String? title,
    String? note,
    LatLng? position,
    Bitmap? icon,
    bool? isCustom,
    int? remoteId,
    bool? visible,
    bool? canEdit,
    bool? canDelete,
    String? ownerUsername,
  }) {
    return Station(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      position: position ?? this.position,
      icon: icon ?? this.icon,
      isCustom: isCustom ?? this.isCustom,
      remoteId: remoteId ?? this.remoteId,
      visible: visible ?? this.visible,
      canEdit: canEdit ?? this.canEdit,
      canDelete: canDelete ?? this.canDelete,
      ownerUsername: ownerUsername ?? this.ownerUsername,
    );
  }
}
