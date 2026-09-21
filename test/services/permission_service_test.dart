import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/services/permission_service.dart';

/// 通知权限接口的降级与"查询/申请分离"契约测试。
///
/// 背景（docs/代码审计待办.md P1-9）：启动阶段必须只**查询**，不能申请；
/// 申请只在用户主动触发时发生。两个接口在无插件环境都必须降级返回 false。
void main() {
  // 让平台通道有测试 binding 可走（否则插件会打印一大堆 binding 警告）
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PermissionService 通知权限', () {
    test('查询接口在测试环境降级为 false（不抛异常）', () async {
      expect(await PermissionService.isNotificationGranted(), isFalse);
    });

    test('申请接口在测试环境同样降级为 false（不抛异常）', () async {
      expect(await PermissionService.requestNotification(), isFalse);
    });
  });
}
