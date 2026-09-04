import 'package:flutter_test/flutter_test.dart';
import 'package:aquamoon/models/playback_mode.dart';
import 'package:aquamoon/models/song.dart';

void main() {
  group('Queue Reordering & Index Shifting Logic Tests', () {
    test('simulates reorderQueue: moves item down and correctly updates active index', () {
      final playlist = ['song-0', 'song-1', 'song-2', 'song-3'];
      int currentIndex = 1; // song-1 is currently playing

      // Move song-0 (oldIndex 0) to newIndex 2
      const oldIndex = 0;
      const newIndex = 2;

      final item = playlist.removeAt(oldIndex);
      playlist.insert(newIndex, item);

      // Reorder index update algorithm as implemented in SoundCraftAudioHandler:
      if (currentIndex == oldIndex) {
        currentIndex = newIndex;
      } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
        currentIndex--;
      } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
        currentIndex++;
      }

      expect(playlist, ['song-1', 'song-2', 'song-0', 'song-3']);
      expect(currentIndex, 0);
      expect(playlist[currentIndex], 'song-1'); // Currently playing song preserved!
    });

    test('simulates reorderQueue: moves item up and correctly updates active index', () {
      final playlist = ['song-0', 'song-1', 'song-2', 'song-3'];
      int currentIndex = 1; // song-1 is currently playing

      // Move song-3 (oldIndex 3) to newIndex 0
      const oldIndex = 3;
      const newIndex = 0;

      final item = playlist.removeAt(oldIndex);
      playlist.insert(newIndex, item);

      if (currentIndex == oldIndex) {
        currentIndex = newIndex;
      } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
        currentIndex--;
      } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
        currentIndex++;
      }

      expect(playlist, ['song-3', 'song-0', 'song-1', 'song-2']);
      expect(currentIndex, 2);
      expect(playlist[currentIndex], 'song-1'); // Currently playing song preserved!
    });

    test('simulates reorderQueue: moves currently playing item itself', () {
      final playlist = ['song-0', 'song-1', 'song-2', 'song-3'];
      int currentIndex = 1; // song-1 is currently playing

      // Move currently playing item to index 3
      const oldIndex = 1;
      const newIndex = 3;

      final item = playlist.removeAt(oldIndex);
      playlist.insert(newIndex, item);

      if (currentIndex == oldIndex) {
        currentIndex = newIndex;
      } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
        currentIndex--;
      } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
        currentIndex++;
      }

      expect(playlist, ['song-0', 'song-2', 'song-3', 'song-1']);
      expect(currentIndex, 3);
      expect(playlist[currentIndex], 'song-1');
    });

    test('simulates removeSongFromQueue: removing item before, at, and after currentIndex', () {
      final playlist = ['song-0', 'song-1', 'song-2'];
      int currentIndex = 1; // song-1

      // 1. Remove song after currentIndex (index 2)
      playlist.removeAt(2);
      if (currentIndex > 2) {
        currentIndex--;
      }
      expect(playlist, ['song-0', 'song-1']);
      expect(currentIndex, 1);
      expect(playlist[currentIndex], 'song-1');

      // 2. Remove song before currentIndex (index 0)
      playlist.removeAt(0);
      if (currentIndex > 0) {
        currentIndex--;
      }
      expect(playlist, ['song-1']);
      expect(currentIndex, 0);
      expect(playlist[currentIndex], 'song-1');

      // 3. Remove current song (index 0)
      playlist.removeAt(0);
      if (playlist.isEmpty) {
        currentIndex = -1;
      } else {
        currentIndex = currentIndex.clamp(0, playlist.length - 1);
      }
      expect(playlist, isEmpty);
      expect(currentIndex, -1);
    });
  });

  group('Song & MediaItem Mapping Tests', () {
    test('correctly validates URI transformation logic for local and web art URIs', () {
      final webSong = Song(
        id: 'web-1',
        title: 'Web Song',
        artist: 'Web Artist',
        album: 'Web Album',
        durationMs: 180000,
        filePath: 'https://example.com/audio.mp3',
        albumArtUri: 'https://example.com/cover.jpg',
        dateAdded: DateTime.now(),
      );

      final localSong = Song(
        id: 'local-1',
        title: 'Local Song',
        artist: 'Local Artist',
        album: 'Local Album',
        durationMs: 240000,
        filePath: '/storage/emulated/0/Music/song.mp3',
        albumArtUri: '/storage/emulated/0/Music/cover.jpg',
        dateAdded: DateTime.now(),
      );

      // Web URI parsing
      final webUri = Uri.tryParse(webSong.albumArtUri!);
      expect(webUri?.scheme, 'https');

      // Local file path parsing
      final localUri = Uri.file(localSong.albumArtUri!);
      expect(localUri.scheme, 'file');
      expect(localUri.toFilePath(), '/storage/emulated/0/Music/cover.jpg');
    });

    test('PlaybackMode cycle covers all modes in exact order', () {
      var mode = PlaybackMode.sequence;
      expect(mode.label, '顺序播放');

      mode = mode.next();
      expect(mode, PlaybackMode.repeatAll);
      expect(mode.label, '列表循环');

      mode = mode.next();
      expect(mode, PlaybackMode.repeatOne);
      expect(mode.label, '单曲循环');

      mode = mode.next();
      expect(mode, PlaybackMode.shuffle);
      expect(mode.label, '随机播放');

      mode = mode.next();
      expect(mode, PlaybackMode.sequence);
    });
  });
}
