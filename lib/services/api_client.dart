import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/marker_dto.dart';
import '../models/marker_share_dto.dart';

class ApiClient {
  final String baseUrl;
  final String? token;

  const ApiClient({required this.baseUrl, this.token});

  Duration get _timeout => const Duration(seconds: AppConfig.apiTimeoutSeconds);

  Map<String, String> _jsonHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<String> login(String username, String password) async {
    try {
      final body =
          'username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';
      final resp = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
          )
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '登录失败');
      final data = _extractData(resp.body) as Map<String, dynamic>;
      return data['access_token'] as String;
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<void> register(String username, String password) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: _jsonHeaders(),
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '注册失败');
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<List<MarkerDto>> listMarkers() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/markers'), headers: _jsonHeaders())
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '加载标记失败');
      final list = _extractData(resp.body) as List<dynamic>;
      return list
          .map((item) => MarkerDto.fromJson(item as Map<String, dynamic>))
          .toList();
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<MarkerDto> createMarker({
    required String title,
    required String note,
    required double lat,
    required double lng,
    bool visible = true,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/markers'),
            headers: _jsonHeaders(),
            body: jsonEncode({
              'title': title,
              'note': note,
              'lat': lat,
              'lng': lng,
              'visible': visible,
            }),
          )
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '创建标记失败');
      return MarkerDto.fromJson(
        _extractData(resp.body) as Map<String, dynamic>,
      );
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<MarkerDto> updateMarker({
    required int id,
    String? title,
    String? note,
    double? lat,
    double? lng,
    bool? visible,
  }) async {
    try {
      Map<String, dynamic>? entry(String key, Object? value) =>
          value == null ? null : {key: value};
      final payload = <String, dynamic>{
        ...?entry('title', title),
        ...?entry('note', note),
        ...?entry('lat', lat),
        ...?entry('lng', lng),
        ...?entry('visible', visible),
      };
      final resp = await http
          .put(
            Uri.parse('$baseUrl/markers/$id'),
            headers: _jsonHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '更新标记失败');
      return MarkerDto.fromJson(
        _extractData(resp.body) as Map<String, dynamic>,
      );
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<void> deleteMarker(int id) async {
    try {
      final resp = await http
          .delete(Uri.parse('$baseUrl/markers/$id'), headers: _jsonHeaders())
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '删除标记失败');
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<void> shareMarker({
    required int markerId,
    required String username,
    bool canEdit = false,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/markers/$markerId/share'),
            headers: _jsonHeaders(),
            body: jsonEncode({'username': username, 'can_edit': canEdit}),
          )
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '共享标记失败');
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<List<MarkerShareDto>> listMarkerShares(int markerId) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$baseUrl/markers/$markerId/shares'),
            headers: _jsonHeaders(),
          )
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '加载共享列表失败');
      final list = _extractData(resp.body) as List<dynamic>;
      return list
          .map((item) => MarkerShareDto.fromJson(item as Map<String, dynamic>))
          .toList();
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  Future<void> removeMarkerShare({
    required int markerId,
    required int userId,
  }) async {
    try {
      final resp = await http
          .delete(
            Uri.parse('$baseUrl/markers/$markerId/share/$userId'),
            headers: _jsonHeaders(),
          )
          .timeout(_timeout);
      _ensureSuccess(resp, fallback: '取消共享失败');
    } on SocketException {
      throw const ApiException('网络不可用，请检查连接');
    } on TimeoutException {
      throw const ApiException('请求超时，请稍后重试');
    } on http.ClientException {
      throw const ApiException('网络请求失败，请稍后重试');
    }
  }

  void _ensureSuccess(http.Response resp, {required String fallback}) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return;
    }
    if (resp.statusCode == 401) {
      throw const UnauthorizedApiException('登录已失效，请重新登录');
    }
    final message =
        _extractMessage(resp.body) ?? '$fallback(${resp.statusCode})';
    throw ApiException(message);
  }

  String? _extractMessage(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final message = parsed['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
        final detail = parsed['detail'];
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
        if (detail is Map<String, dynamic>) {
          final nestedMessage = detail['message'];
          if (nestedMessage is String && nestedMessage.isNotEmpty) {
            return nestedMessage;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  dynamic _extractData(String body) {
    final parsed = jsonDecode(body);
    if (parsed is Map<String, dynamic> && parsed.containsKey('data')) {
      return parsed['data'];
    }
    return parsed;
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class UnauthorizedApiException extends ApiException {
  const UnauthorizedApiException(super.message);
}
