class Farm {
  final String id;
  final String name;
  final String location;
  final String? topicId; // MAC address / kurnik_id dla MQTT

  const Farm({
    required this.id,
    required this.name,
    required this.location,
    this.topicId,
  });

  factory Farm.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    if (rawId == null) {
      throw Exception('Farm.fromJson: brak pola "id"');
    }

    final name = json['name']?.toString();
    final location = json['location']?.toString()
        ?? json['address']?.toString()
        ?? json['city']?.toString();
    final topicId = json['topic_id']?.toString();

    return Farm(
      id: rawId.toString(),
      name: name == null || name.isEmpty ? '—' : name,
      location: location ?? '',
      topicId: topicId,
    );
  }
}