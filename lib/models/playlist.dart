class Playlist {
  final String id;
  final String name;
  final String description;
  final List<String> songIds;
  final DateTime createdAt;
  final String? coverArtUri;

  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    required this.songIds,
    required this.createdAt,
    this.coverArtUri,
  });

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? songIds,
    DateTime? createdAt,
    String? coverArtUri,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      songIds: songIds ?? this.songIds,
      createdAt: createdAt ?? this.createdAt,
      coverArtUri: coverArtUri ?? this.coverArtUri,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'songIds': songIds,
      'createdAt': createdAt.toIso8601String(),
      'coverArtUri': coverArtUri,
    };
  }

  factory Playlist.fromMap(Map<dynamic, dynamic> map) {
    return Playlist(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '新歌单',
      description: map['description'] as String? ?? '',
      songIds: (map['songIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      coverArtUri: map['coverArtUri'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
