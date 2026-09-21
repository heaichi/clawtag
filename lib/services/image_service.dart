import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final _picker = ImagePicker();

/// 启用 Android 系统 Photo Picker。
///
/// image_picker 默认 useAndroidPhotoPicker=false，会走传统相册 Intent，
/// 部分厂商相册会忽略 limit（如 Vivo 显示 0/100 且可超选）。
/// 开启后使用 Android Photo Picker，才能让系统按 limit 限制可选数量。
void _enableAndroidPhotoPicker() {
  // ImagePicker.platform 被标记为 @visibleForTesting，
  // 但这是不新增依赖情况下访问 Android 平台实现的唯一入口。
  // ignore: invalid_use_of_visible_for_testing_member
  final dynamic platform = ImagePicker.platform;
  try {
    platform.useAndroidPhotoPicker = true;
  } catch (_) {
    // 非 Android 或平台不支持时忽略
  }
}

/// Pick a photo from camera. Returns null if user cancels or on error.
Future<String?> pickImageFromCamera() async {
  try {
    final result = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (result == null) return null;
    return _saveToAppDir(result.path, 'jpg');
  } catch (e) {
    debugPrint('pickImageFromCamera error: $e');
    return null;
  }
}

/// Pick photos from gallery.
Future<List<String>> pickImagesFromGallery({int maxCount = 9}) async {
  try {
    if (maxCount <= 0) return [];
    _enableAndroidPhotoPicker();
    // image_picker 的 multi limit 在 Android 上不允许小于 2；
    // 只剩 1 个名额时改用单选，避免抛 ArgumentError。
    if (maxCount == 1) {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (file == null) return [];
      final saved = await _saveToAppDir(file.path, 'jpg');
      return saved == null ? [] : [saved];
    }

    final result = await _picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
      limit: maxCount,
    );
    final paths = <String>[];
    for (final file in result) {
      if (paths.length >= maxCount) break; // 遵守上限，防止突破 9 张
      final saved = await _saveToAppDir(file.path, 'jpg');
      if (saved != null) paths.add(saved);
    }
    return paths;
  } catch (e) {
    debugPrint('pickImagesFromGallery error: $e');
    return [];
  }
}

/// Record a video from camera.
Future<String?> pickVideoFromCamera() async {
  try {
    final result = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 5),
      preferredCameraDevice: CameraDevice.rear,
    );
    if (result == null) return null;
    return _saveToAppDir(result.path, 'mp4');
  } catch (e) {
    debugPrint('pickVideoFromCamera error: $e');
    return null;
  }
}

/// Pick a video from gallery.
Future<String?> pickVideoFromGallery() async {
  try {
    final result = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (result == null) return null;
    return _saveToAppDir(result.path, 'mp4');
  } catch (e) {
    debugPrint('pickVideoFromGallery error: $e');
    return null;
  }
}

Future<String?> _saveToAppDir(String sourcePath, String ext) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dest = p.join(mediaDir.path, name);
    await File(sourcePath).copy(dest);
    return dest;
  } catch (e) {
    debugPrint('_saveToAppDir error: $e');
    return null;
  }
}
