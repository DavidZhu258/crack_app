import 'dart:async';

import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/jci_detection/services/foreground_auto_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not sync when the production server is unreachable', () async {
    var syncCalls = 0;
    final service = ForegroundAutoSyncService(
      canReachServer: () async => false,
      readSession: () async => _session(),
      syncRecords: () async {
        syncCalls++;
        return const ForegroundAutoSyncResult.synced(
          uploaded: 1,
          failed: 0,
          downloaded: 0,
        );
      },
      debounce: Duration.zero,
    );

    final result = await service.syncNow();

    expect(result.status, equals(ForegroundAutoSyncStatus.offline));
    expect(syncCalls, equals(0));
  });

  test('requires login before uploading local records', () async {
    var syncCalls = 0;
    final service = ForegroundAutoSyncService(
      canReachServer: () async => true,
      readSession: () async => null,
      syncRecords: () async {
        syncCalls++;
        return const ForegroundAutoSyncResult.synced(
          uploaded: 1,
          failed: 0,
          downloaded: 0,
        );
      },
      debounce: Duration.zero,
    );

    final result = await service.syncNow();

    expect(result.status, equals(ForegroundAutoSyncStatus.needsLogin));
    expect(syncCalls, equals(0));
  });

  test('offline attempt does not debounce the next online sync', () async {
    var reachable = false;
    var syncCalls = 0;
    final service = ForegroundAutoSyncService(
      canReachServer: () async => reachable,
      readSession: () async => _session(),
      syncRecords: () async {
        syncCalls++;
        return const ForegroundAutoSyncResult.synced(
          uploaded: 1,
          failed: 0,
          downloaded: 0,
        );
      },
    );

    final offline = await service.syncNow();
    reachable = true;
    final online = await service.syncNow();

    expect(offline.status, equals(ForegroundAutoSyncStatus.offline));
    expect(online.status, equals(ForegroundAutoSyncStatus.synced));
    expect(syncCalls, equals(1));
  });

  test('syncs once and skips concurrent foreground triggers', () async {
    final syncGate = Completer<ForegroundAutoSyncResult>();
    var syncCalls = 0;
    final service = ForegroundAutoSyncService(
      canReachServer: () async => true,
      readSession: () async => _session(),
      syncRecords: () {
        syncCalls++;
        return syncGate.future;
      },
      debounce: Duration.zero,
    );

    final first = service.syncNow();
    await Future<void>.delayed(Duration.zero);
    final second = await service.syncNow();

    expect(second.status, equals(ForegroundAutoSyncStatus.skipped));
    expect(syncCalls, equals(1));

    syncGate.complete(
      const ForegroundAutoSyncResult.synced(
        uploaded: 2,
        failed: 0,
        downloaded: 1,
      ),
    );
    final firstResult = await first;

    expect(firstResult.uploaded, equals(2));
    expect(firstResult.downloaded, equals(1));
  });
}

AuthSession _session() {
  return AuthSession(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.utc(2026, 5, 11, 12),
    user: const AuthUser(
      id: 'u1',
      username: 'miner01',
      displayName: '矿工 01',
      role: 'operator',
    ),
  );
}
