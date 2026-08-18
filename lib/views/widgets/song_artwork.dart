import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/song.dart';

class SongArtwork extends StatelessWidget {
  final Song? song;
  final String? artUri;
  final Uint8List? artBytes;
  final double size;
  final double borderRadius;
  final bool isRound;
  final bool showShadow;

  const SongArtwork({
    super.key,
    this.song,
    this.artUri,
    this.artBytes,
    this.size = 50,
    this.borderRadius = 8,
    this.isRound = false,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveUri = artUri ?? song?.albumArtUri;
    final effectiveBytes = artBytes ?? song?.albumArtBytes;

    Widget imageWidget = _buildPlaceholder(context);

    if (effectiveBytes != null && effectiveBytes.isNotEmpty) {
      imageWidget = Image.memory(
        effectiveBytes,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
      );
    } else if (effectiveUri != null && effectiveUri.isNotEmpty) {
      if (effectiveUri.startsWith('file://')) {
        final filePath = Uri.parse(effectiveUri).toFilePath();
        final file = File(filePath);
        imageWidget = Image.file(
          file,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
        );
      } else if (effectiveUri.startsWith('http://') || effectiveUri.startsWith('https://')) {
        imageWidget = CachedNetworkImage(
          imageUrl: effectiveUri,
          fit: BoxFit.cover,
          width: size,
          height: size,
          placeholder: (context, url) => _buildPlaceholder(context, isLoading: true),
          errorWidget: (context, url, error) => _buildPlaceholder(context),
        );
      } else {
        final file = File(effectiveUri);
        imageWidget = Image.file(
          file,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
        );
      }
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isRound ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isRound ? null : BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: size * 0.15,
                  offset: Offset(0, size * 0.08),
                )
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageWidget,
    );
  }

  Widget _buildPlaceholder(BuildContext context, {bool isLoading = false}) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: Center(
        child: isLoading
            ? SizedBox(
                width: size * 0.4,
                height: size * 0.4,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.music_note_rounded,
                size: size * 0.5,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
      ),
    );
  }
}
