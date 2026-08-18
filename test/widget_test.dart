import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/views/widgets/song_artwork.dart';
import 'package:aquamoon/models/song.dart';

void main() {
  testWidgets('SongArtwork renders placeholder properly when no artwork URI is given',
      (WidgetTester tester) async {
    final song = Song(
      id: 's1',
      title: '测试曲目',
      artist: '测试歌手',
      album: '测试专辑',
      durationMs: 180000,
      filePath: '/dummy/path.mp3',
      dateAdded: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongArtwork(
            song: song,
            size: 60,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });
}
