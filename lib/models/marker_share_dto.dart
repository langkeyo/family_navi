class MarkerShareDto {
  final int shareId;
  final int userId;
  final String username;
  final bool canEdit;

  const MarkerShareDto({
    required this.shareId,
    required this.userId,
    required this.username,
    required this.canEdit,
  });

  factory MarkerShareDto.fromJson(Map<String, dynamic> json) {
    return MarkerShareDto(
      shareId: json['share_id'] as int,
      userId: json['user_id'] as int,
      username: json['username'] as String,
      canEdit: (json['can_edit'] as bool?) ?? false,
    );
  }
}
