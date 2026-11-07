import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

/// Slika s mreže dekodirana kroz `createImageBitmap`, mimo `<img>` puta
/// Flutter web enginea.
///
/// Zašto: na iOS WebKitu (Safari, iOS Chrome, WhatsApp preglednik) engine i
/// `NetworkImage` i dekodiranje bajtova vodi kroz `<img>` + `decode()`, a
/// ondje pri PONOVNOM dekodiranju iste slike `naturalWidth` zna biti 0 →
/// CanvasKit vrati null → `ImageCodecException: Failed to create image from
/// Image.decode`. Izmjereno 7.11.2026.: 149/149 i 434/434 grešaka su ta, prvi
/// prikaz uredan, svaki povratak na ekran crn ili s ikonom. Engine ima
/// zaobilazak za 0×0 samo za Firefox (`html_image_element_codec.dart`).
///
/// `ImageBitmap` nosi stvarne dimenzije i usput se smanji na [targetWidth]
/// (`resizeWidth`), pa i `memCacheWidth` napokon vrijedi na webu. Bajtove
/// cachira HTTP cache preglednika (`fetch`).
@immutable
class WebBitmapImage extends ImageProvider<WebBitmapImage> {
  const WebBitmapImage(this.url, {this.targetWidth});

  final String url;

  /// Širina u fizičkim pikselima na koju se slika smanjuje; `null` = izvorna.
  final int? targetWidth;

  @override
  Future<WebBitmapImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<WebBitmapImage>(this);

  @override
  ImageStreamCompleter loadImage(
    WebBitmapImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      _load(key),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
      ],
    );
  }

  static Future<ImageInfo> _load(WebBitmapImage key) async {
    final response = await web.window.fetch(key.url.toJS).toDart;
    if (!response.ok) {
      throw NetworkImageLoadException(
        statusCode: response.status,
        uri: Uri.parse(key.url),
      );
    }
    final blob = await response.blob().toDart;
    final bitmap = await _bitmap(blob, key.targetWidth);
    final image = await ui_web.createImageFromImageBitmap(bitmap);
    return ImageInfo(image: image);
  }

  static Future<web.ImageBitmap> _bitmap(web.Blob blob, int? width) async {
    if (width != null && width > 0) {
      try {
        return await web.window
            .createImageBitmap(
              blob,
              web.ImageBitmapOptions(
                resizeWidth: width,
                resizeQuality: 'high',
                premultiplyAlpha: 'premultiply',
              ),
            )
            .toDart;
      } catch (_) {
        // Stariji WebKit bez `resizeWidth` — dekodiraj u izvornoj veličini.
      }
    }
    return web.window
        .createImageBitmap(
          blob,
          web.ImageBitmapOptions(premultiplyAlpha: 'premultiply'),
        )
        .toDart;
  }

  @override
  bool operator ==(Object other) =>
      other is WebBitmapImage &&
      other.url == url &&
      other.targetWidth == targetWidth;

  @override
  int get hashCode => Object.hash(url, targetWidth);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'WebBitmapImage')}("$url", w: $targetWidth)';
}
