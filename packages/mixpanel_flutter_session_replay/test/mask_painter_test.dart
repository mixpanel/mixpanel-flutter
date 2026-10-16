import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('should release the masking picture after producing an image', () async {
    // GIVEN an image and a listener for picture disposal
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    final sourcePicture = recorder.endRecording();
    final original = await sourcePicture.toImage(2, 2);
    sourcePicture.dispose();
    addTearDown(original.dispose);
    final previousOnDispose = ui.Picture.onDispose;
    final disposedPictures = <ui.Picture>[];
    ui.Picture.onDispose = (picture) {
      disposedPictures.add(picture);
      previousOnDispose?.call(picture);
    };
    addTearDown(() => ui.Picture.onDispose = previousOnDispose);

    // WHEN masking produces its output
    final masked = await MaskPainter().applyMasks(original, []);
    addTearDown(masked.dispose);

    // THEN the temporary picture is released and the image remains usable
    expect(disposedPictures, hasLength(1));
    expect(await masked.toByteData(), isNotNull);
  });
}
