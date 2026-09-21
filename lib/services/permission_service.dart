import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Runtime permission check with user-friendly dialogs.
class PermissionService {
  /// Check and request camera permission.
  /// Returns true if granted, false otherwise.
  /// Shows dialog with settings redirect if permanently denied.
  static Future<bool> checkCamera(BuildContext context) async {
    var status = await ph.Permission.camera.status;

    if (status.isGranted) return true;

    // Show rationale before requesting
    if (status.isDenied) {
      status = await ph.Permission.camera.request();
      if (status.isGranted) return true;
    }

    // Permanently denied — show settings redirect
    if (status.isPermanentlyDenied && context.mounted) {
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要相机权限'),
          content: const Text(
            '拍摄照片和录制视频需要相机权限。\n\n'
            '请在设置中开启相机权限后重试。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
    }
    return false;
  }

  /// 仅**查询**通知权限（不弹系统弹窗）。
  ///
  /// 启动阶段只能用这个：在 runApp 之前弹权限框会阻塞首帧，且不符合
  /// "权限申请需结合使用场景"的商店要求（见 docs/代码审计待办.md P1-9）。
  static Future<bool> isNotificationGranted() async {
    try {
      return await ph.Permission.notification.isGranted;
    } catch (e) {
      debugPrint('isNotificationGranted failed: $e');
      return false;
    }
  }

  /// 主动**申请**通知权限（会弹系统弹窗，Android 13+）。
  ///
  /// 只在有明确使用场景且用户主动触发时调用（如"我的 → 通知权限"）。
  static Future<bool> requestNotification() async {
    try {
      if (await ph.Permission.notification.isGranted) return true;
      final status = await ph.Permission.notification.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('requestNotification failed: $e');
      return false;
    }
  }

  /// Open app settings page
  static Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }
}
