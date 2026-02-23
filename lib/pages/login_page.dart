import 'package:flutter/material.dart';

import '../services/api_client.dart';

class LoginPage extends StatefulWidget {
  final ApiClient api;
  final void Function(String token) onLoggedIn;

  const LoginPage({
    super.key,
    required this.api,
    required this.onLoggedIn,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final token = await widget.api.login(
        _userCtrl.text.trim(),
        _passCtrl.text.trim(),
      );
      if (!mounted) return;
      widget.onLoggedIn(token);
    } on ApiException catch (e) {
      _showToast(e.message);
    } catch (_) {
      _showToast('登录失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      await widget.api.register(
        _userCtrl.text.trim(),
        _passCtrl.text.trim(),
      );
      if (!mounted) return;
      _showToast('注册成功，请登录');
    } on ApiException catch (e) {
      _showToast(e.message);
    } catch (_) {
      _showToast('注册失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '家人拜年导航',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(labelText: '密码'),
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
                TextButton(
                  onPressed: _loading ? null : _register,
                  child: const Text('注册新账号'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
