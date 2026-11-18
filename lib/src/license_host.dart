// What the licence check needs from the platform: sending a request and
// keeping a small record. What is sent and what the answer means is decided
// in the compiled core; nothing here interprets it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class LicenseResponse {
  const LicenseResponse(this.status, this.body);

  final int status;
  final Uint8List body;
}

/// Sends a request with a JSON body and returns the answer. Throws when no
/// answer comes.
typedef LicenseTransport = Future<LicenseResponse> Function(
    String method, String address, String body);

/// Keeps one record per device between app runs.
abstract class LicenseStore {
  Future<Uint8List?> read(String key);

  /// [value] null removes the record.
  Future<void> write(String key, Uint8List? value);
}

Future<LicenseResponse> sendWithHttpClient(
    String method, String address, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.openUrl(method, Uri.parse(address));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(body));
    final response = await request.close();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > 65536) break;
    }
    return LicenseResponse(response.statusCode, bytes.takeBytes());
  } finally {
    client.close(force: true);
  }
}

/// Records as files in the app's support directory.
class FileLicenseStore implements LicenseStore {
  Future<File> _file(String key) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}emoconnect_$key.lic');
  }

  @override
  Future<Uint8List?> read(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return bytes.length <= 64 ? bytes : null;
  }

  @override
  Future<void> write(String key, Uint8List? value) async {
    final file = await _file(key);
    if (value == null) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsBytes(value, flush: true);
    }
  }
}
