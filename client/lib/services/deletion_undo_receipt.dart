import 'dart:math';

import 'api_service.dart';
import 'http_util.dart';

/// A 128-bit random receipt key. It identifies one destructive request,
/// allowing read-only verification when the HTTP DELETE response was lost.
String newDeletionUndoToken() {
  const hex = '0123456789abcdef';
  final random = Random.secure();
  return List.generate(32, (_) => hex[random.nextInt(16)]).join();
}

/// The server creates this receipt in the same transaction as deletion.
/// A successful GET proves that deletion was committed for the current user.
/// Errors and missing receipts are inconclusive, never proof of no write.
Future<bool> deletionReceiptCommitted(String kind, String token) async {
  try {
    final uri = Uri.parse('${ApiService.baseUrl}/undo-receipt').replace(
      queryParameters: {'kind': kind, 'token': token},
    );
    final response = await HttpUtil.get(
      uri,
      headers: await ApiService.authHeaders(),
    ).timeout(ApiService.getTimeout);
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}
