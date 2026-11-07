import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Native nikad ne koristi ovaj provider (vidi `web_bitmap_image_web.dart`);
/// postoji samo da `CachedThumbnail` kompajlira bez `dart:ui_web`.
@immutable
class WebBitmapImage extends ImageProvider<WebBitmapImage> {
  const WebBitmapImage(this.url, {this.targetWidth});

  final String url;
  final int? targetWidth;

  @override
  Future<WebBitmapImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<WebBitmapImage>(this);

  @override
  ImageStreamCompleter loadImage(
    WebBitmapImage key,
    ImageDecoderCallback decode,
  ) =>
      throw UnsupportedError('WebBitmapImage postoji samo na webu');
}
