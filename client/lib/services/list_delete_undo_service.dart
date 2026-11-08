import 'dart:async';
import 'dart:convert';

import '../repositories/local_list_repository.dart';
import 'api_service.dart';
import 'cloud_sync_coordinator.dart';
import 'data_mode_manager.dart';
import 'deletion_undo_receipt.dart';
import 'http_util.dart';

/// A one-use undo for the original IDs, not a recreation of a lookalike list.
class ListDeletionUndo {
  ListDeletionUndo(this._restore);

  final Future<void> Function() _restore;
  bool _busy = false;
  bool _used = false;

  Future<void> restore() async {
    if (_busy || _used) throw StateError('这次撤销已执行或正在核对');
    _busy = true;
    try {
      await _restore();
      _used = true;
    } finally {
      _busy = false;
    }
  }
}

/// Reuses LocalListRepository and the existing authenticated Cloud API;
/// no separate task/list store or parallel sync queue is introduced.
class ListDeleteUndoService {
  Future<ListDeletionUndo> delete({
    required int localId,
    int? serverId,
    required int expectedTaskCount,
  }) async {
    if (DataModeManager().isLocal) {
      final repo = LocalListRepository();
      final receipt = await repo.deleteWithUndo(
        localId, expectedTaskCount: expectedTaskCount,
      );
      return ListDeletionUndo(() => repo.undoDelete(receipt));
    }
    final remoteId = serverId != null && serverId > 0
        ? serverId
        : localId > 0 ? localId : null;
    if (remoteId == null) {
      throw StateError('未同步清单暂不能安全删除，请先同步后重试');
    }
    final token = newDeletionUndoToken();
    final headers = await ApiService.authHeaders();
    final uri = Uri.parse('${ApiService.baseUrl}/lists/$remoteId')
        .replace(queryParameters: {
      'delete_tasks': 'true',
      'expected_tasks': expectedTaskCount.toString(),
      'undoable': 'true',
      'undo_token': token,
    });
    try {
      final response = await HttpUtil.delete(
        uri, headers: headers,
      ).timeout(ApiService.postTimeout);
      if (response.statusCode == 409) {
        throw StateError('清单关联任务已变化，请重新核对删除范围');
      }
      if (response.statusCode != 200) {
        throw StateError('清单删除回执未确认，请先核对');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['undo_token'] != token) {
        throw StateError('服务端未返回已核对的撤销凭据');
      }
    } catch (_) {
      // HTTP timeout/reset can occur AFTER the server committed the delete.
      // The caller knows the random key and verifies the durable receipt
      // via GET; do not send the DELETE again or manufacture success.
      if (!await deletionReceiptCommitted('list', token)) rethrow;
    }
    unawaited(CloudSyncCoordinator().syncNow());
    return ListDeletionUndo(() async {
      final restored = await HttpUtil.post(
        Uri.parse('${ApiService.baseUrl}/lists/undo'),
        headers: await ApiService.authHeaders(),
        body: jsonEncode({'token': token}),
      ).timeout(ApiService.postTimeout);
      if (restored.statusCode != 200) {
        throw StateError('恢复失败或撤销已过期，请刷新核对');
      }
      unawaited(CloudSyncCoordinator().syncNow());
    });
  }
}
