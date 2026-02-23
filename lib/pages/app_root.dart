import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import 'login_page.dart';
import 'map_page.dart';

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _authStorage = const AuthStorage();
  String? _token;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await _authStorage.loadToken();
    if (!mounted) return;
    setState(() {
      _token = token;
      _loading = false;
    });
  }

  Future<void> _setToken(String? token) async {
    if (token == null) {
      await _authStorage.clearToken();
    } else {
      await _authStorage.saveToken(token);
    }
    if (!mounted) return;
    setState(() => _token = token);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_token == null) {
      return LoginPage(
        api: const ApiClient(baseUrl: AppConfig.apiBaseUrl),
        onLoggedIn: (token) => _setToken(token),
      );
    }
    return FamilyTencentMapPage(
      api: ApiClient(baseUrl: AppConfig.apiBaseUrl, token: _token),
      onLogout: () => _setToken(null),
    );
  }
}
