import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');
const _localUserIdKey = 'local_checkin_user_id';
const _apiRequestTimeout = Duration(seconds: 10);
const _checkinRequestTimeout = Duration(seconds: 180);

class Api {
  Api({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client() {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !const {'http', 'https'}.contains(uri.scheme)) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Must be an absolute HTTP or HTTPS URL.',
      );
    }
  }

  factory Api.forCurrentPlatform({http.Client? client}) {
    final baseUrl = _apiBaseUrlOverride.isNotEmpty
        ? _apiBaseUrlOverride
        : defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8080'
        : 'http://127.0.0.1:8080';
    return Api(baseUrl: baseUrl, client: client);
  }

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> getHealth() async {
    final response = await _request(() => _client.get(_uri('/api/health')));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> startServices() async {
    final javaServer = _decodeResponse(
      await _request(() => _client.get(_uri('/api/health'))),
    );
    final aiServer = _decodeResponse(
      await _request(() => _client.post(_uri('/api/ai/start'))),
    );
    return {'java': javaServer, 'python': aiServer};
  }

  Future<Map<String, dynamic>> processCheckins(String text) async {
    final userId = await getUserID();
    final response = await _request(
      () => _client.post(
        _uri('/api/checkins/process'),
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'X-User-ID': userId,
          'X-Time-Zone-Offset-Minutes': DateTime.now().timeZoneOffset.inMinutes
              .toString(),
        },
        body: text,
      ),
      timeout: _checkinRequestTimeout,
    );
    return _decodeResponse(response);
  }

  Future<List<Map<String, dynamic>>> getProgressHistory() async {
    final userId = await getUserID();
    final response = await _request(
      () => _client.get(
        _uri('/api/progress/history'),
        headers: {'X-User-ID': userId},
      ),
    );
    final data = _decodeResponse(response);
    final raw = data['records'];
    if (raw is! List) {
      throw const FormatException('History response has no records list.');
    }

    return raw.map((record) {
      if (record is! Map) {
        throw const FormatException('History contains an invalid record.');
      }
      return Map<String, dynamic>.from(record);
    }).toList();
  }

  String _createLocalUserId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Map<String, dynamic>> getMemory() async {
    final response = await _request(
      () => _client.get(_uri('/api/checkins/memory')),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> updateMemory() async {
    final response = await _request(
      () => _client.post(_uri('/api/checkins/memory/update')),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> getSupportPrompts() async {
    final response = await _request(
      () => _client.get(_uri('/api/checkins/support')),
    );
    return _decodeResponse(response);
  }

  Future<String> getUserID() async {
    final preferences = await SharedPreferences.getInstance();
    var userId = preferences.getString(_localUserIdKey);
    if (userId == null || userId.isEmpty) {
      userId = _createLocalUserId();
      final saved = await preferences.setString(_localUserIdKey, userId);
      if (!saved) {
        throw StateError('Could not save the local check-in user ID.');
      }
    }
    return userId;
  }

  Uri _uri(String path) => Uri.parse(baseUrl).resolve(path);

  Future<http.Response> _request(
    Future<http.Response> Function() send, {
    Duration timeout = _apiRequestTimeout,
  }) async {
    try {
      return await send().timeout(timeout);
    } on http.ClientException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError(
          'Could not reach the Java backend at $baseUrl. Start App.java first '
          'and confirm API_BASE_URL points to an address this device can reach. '
          'Android phones need the computer Wi-Fi address; 10.0.2.2 is for '
          'emulators. Details: $error',
        ),
        stackTrace,
      );
    } on TimeoutException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        TimeoutException(
          'The request to $baseUrl timed out after ${timeout.inSeconds} seconds.',
          timeout,
        ),
        stackTrace,
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected response from Java server.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] ?? 'Java server request failed.';
      throw Exception(error);
    }

    return decoded;
  }
}
