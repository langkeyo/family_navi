import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:tencent_map_flutter/tencent_map_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 必须先同意隐私协议，否则地图无法正常加载
  await TencentMap.init(agreePrivacy: true);
  runApp(const FamilyNaviApp());
}

class FamilyNaviApp extends StatelessWidget {
  const FamilyNaviApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.notoSansScTextTheme(
      ThemeData.light().textTheme,
    );
    return MaterialApp(
      title: '家人拜年导航',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        textTheme: textTheme,
      ),
      home: const FamilyTencentMapPage(),
    );
  }
}

class FamilyTencentMapPage extends StatefulWidget {
  const FamilyTencentMapPage({super.key});

  @override
  State<FamilyTencentMapPage> createState() => _FamilyTencentMapPageState();
}

class _FamilyTencentMapPageState extends State<FamilyTencentMapPage> {
  TencentMapController? _controller;
  bool _uiReady = false;
  late final Widget _mapWidget;

  // 站点数据
  final Map<String, _Station> _stations = {};
  int _idSeed = 1;

  // 定位纠偏相关
  LatLng? _lastRaw;
  LatLng? _filtered;
  DateTime? _lastTime;

  final Distance _distance = const Distance();

  @override
  void initState() {
    super.initState();
    _initDefaultStations();
    _mapWidget = TencentMap(
      myLocationEnabled: true,
      userLocationType: UserLocationType.trackingLocationRotate,
      onMapCreated: _onMapCreated,
      onPress: _onMapPress,
      onTapMarker: _onTapMarker,
      onLocation: _onLocation, // Android 有效
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _uiReady = true);
      }
    });
  }

  void _initDefaultStations() {
    _addStation(
      _Station(
        id: 'uncle2',
        title: '二舅家',
        tip: '这是二舅家，导航到这后步行20米即到',
        position: const LatLng(36.6000, 114.5000),
        // 自定义图标
        icon: Bitmap(asset: 'images/uncle2.png'),
      ),
    );
    _addStation(
      _Station(
        id: 'aunt3',
        title: '三姑家',
        tip: '这是三姑家，到了门口按门铃',
        position: const LatLng(36.6010, 114.5010),
      ),
    );
    _addStation(
      _Station(
        id: 'village_gate',
        title: '村口（导航终点）',
        tip: '村口集合点，车到这后步行进村',
        position: const LatLng(36.5990, 114.4990),
      ),
    );
  }

  void _addStation(_Station s) {
    _stations[s.id] = s;
    if (_controller != null) {
      _controller!.addMarker(
        Marker(
          id: s.id,
          position: s.position,
          icon: s.icon,
          anchor: Anchor(x: 0.5, y: 1.0),
        ),
      );
    }
  }

  void _onMapCreated(TencentMapController controller) {
    _controller = controller;

    // 地图初始化完成后，把站点渲染出来
    for (final s in _stations.values) {
      _controller!.addMarker(
        Marker(
          id: s.id,
          position: s.position,
          icon: s.icon,
          anchor: Anchor(x: 0.5, y: 1.0),
        ),
      );
    }

    // 初始镜头对准“村口”
    _controller!.moveCamera(
      CameraPosition(position: _stations['village_gate']!.position, zoom: 16),
    );
  }

  // Android 端定位回调（高精度定位数据）
  void _onLocation(Location loc) {
    _applyDriftFilter(loc);
  }

  // 漂移过滤 + 简单平滑
  void _applyDriftFilter(Location loc) {
    final now = DateTime.now();
    final raw = loc.position;

    // 1) 精度过差，直接丢弃
    if (loc.accuracy != null && loc.accuracy! > 50) {
      return;
    }

    // 2) 短时间内跳点太远，疑似漂移
    if (_lastRaw != null && _lastTime != null) {
      final dt = now.difference(_lastTime!).inSeconds.clamp(1, 999);
      final dist = _distance.as(LengthUnit.Meter, _lastRaw!, raw);
      if (dt < 3 && dist > 80) {
        return;
      }
    }

    // 3) 平滑
    if (_filtered == null) {
      _filtered = raw;
    } else {
      _filtered = LatLng(
        _filtered!.latitude * 0.7 + raw.latitude * 0.3,
        _filtered!.longitude * 0.7 + raw.longitude * 0.3,
      );
    }

    _lastRaw = raw;
    _lastTime = now;
    setState(() {});
  }

  // 点击 marker
  void _onTapMarker(String markerId) {
    final s = _stations[markerId];
    if (s != null) {
      _showStationInfo(s);
    }
  }

  // 点击地图：点到站点附近则显示，否则新增站点
  void _onMapPress(LatLng pos) async {
    final nearest = _findNearestStation(pos, 25);
    if (nearest != null) {
      _showStationInfo(nearest);
      return;
    }

    final name = await _promptForName();
    if (name == null || name.trim().isEmpty) return;

    final id = 'custom_${_idSeed++}';
    final s = _Station(
      id: id,
      title: name.trim(),
      tip: '这是手动添加的站点',
      position: pos,
      isCustom: true,
    );
    setState(() {
      _addStation(s);
    });
    _showStationInfo(s);
  }

  // 使用当前定位点快速新增站点
  Future<void> _addAtCurrentLocation() async {
    if (_filtered == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无定位，请稍等定位完成')));
      return;
    }
    final name = await _promptForName();
    if (name == null || name.trim().isEmpty) return;
    final id = 'custom_${_idSeed++}';
    final s = _Station(
      id: id,
      title: name.trim(),
      tip: '这是手动添加的站点',
      position: _filtered!,
      isCustom: true,
    );
    setState(() {
      _addStation(s);
    });
    _showStationInfo(s);
  }

  _Station? _findNearestStation(LatLng pos, double meters) {
    _Station? nearest;
    double min = meters;
    for (final s in _stations.values) {
      final d = _distance.as(LengthUnit.Meter, pos, s.position);
      if (d <= min) {
        min = d;
        nearest = s;
      }
    }
    return nearest;
  }

  Future<String?> _promptForName() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('新增站点'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入站点名称，如“姨妈家”'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showStationInfo(_Station s) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(s.tip, style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _startWalkNavi(s),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('步行导航'),
                ),
                const SizedBox(width: 12),
                if (s.isCustom)
                  TextButton(
                    onPressed: () {
                      _controller?.removeMarker(s.id);
                      _stations.remove(s.id);
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: const Text('删除此站点'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 调起腾讯地图 App 步行导航
  Future<void> _startWalkNavi(_Station s) async {
    final uri = Uri.parse(
      'qqmap://map/routeplan'
      '?type=walk'
      '&fromcoord=CurrentLocation'
      '&to=${Uri.encodeComponent(s.title)}'
      '&tocoord=${s.position.latitude},${s.position.longitude}'
      '&referer=PW7BZ-MGAYW-HBYRD-YJSLR-ABPKQ-C4BEJ',
    );

    try {
      // 直接尝试外部打开，部分机型 canLaunchUrl 会误判
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception('launch failed');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未检测到腾讯地图App，请先安装')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('家人拜年导航'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _mapWidget,
          // 顶部玻璃面板
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 8,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              offset: _uiReady ? Offset.zero : const Offset(0, -0.1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _uiReady ? 1 : 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.75),
                            Colors.white.withOpacity(0.55),
                          ],
                        ),
                        border: Border.all(color: Colors.white.withOpacity(0.6)),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E7D32),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.map, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '拜年路线面板',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () async {
                                  if (_filtered != null && _controller != null) {
                                    _controller!.moveCamera(
                                      CameraPosition(position: _filtered, zoom: 17),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.my_location, size: 18),
                                label: const Text('回到定位'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const [
                              _StationChip(title: '二舅家'),
                              _StationChip(title: '三姑家'),
                              _StationChip(title: '村口'),
                              _StationChip(title: '点地图可新增站点'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 离线地图提示
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 140,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: _uiReady ? 1 : 0,
              child: Card(
                color: Colors.amber.shade100,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('提示：出发前请在腾讯地图App里下载“乡村/县城”离线包，山里信号弱也能用。'),
                ),
              ),
            ),
          ),
          // 定位状态提示
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 320),
              offset: _uiReady ? Offset.zero : const Offset(0, 0.1),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.gps_fixed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _filtered == null
                              ? '定位中…'
                              : '定位(纠偏后)：${_filtered!.latitude.toStringAsFixed(5)}, '
                                  '${_filtered!.longitude.toStringAsFixed(5)}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 78,
            child: FloatingActionButton.extended(
              onPressed: _addAtCurrentLocation,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('定位点标记'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Station {
  final String id;
  final String title;
  final String tip;
  final LatLng position;
  final Bitmap? icon;
  final bool isCustom;

  _Station({
    required this.id,
    required this.title,
    required this.tip,
    required this.position,
    this.icon,
    this.isCustom = false,
  });
}

class _StationChip extends StatelessWidget {
  final String title;

  const _StationChip({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
