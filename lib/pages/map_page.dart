import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:tencent_map_flutter/tencent_map_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/marker_dto.dart';
import '../models/marker_share_dto.dart';
import '../models/station.dart';
import '../services/api_client.dart';

class FamilyTencentMapPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onLogout;

  const FamilyTencentMapPage({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<FamilyTencentMapPage> createState() => _FamilyTencentMapPageState();
}

enum _StationScope { all, mine, shared }

class _FamilyTencentMapPageState extends State<FamilyTencentMapPage> {
  TencentMapController? _controller;
  bool _uiReady = false;
  late final Widget _mapWidget;
  _StationScope _stationScope = _StationScope.all;

  final Map<String, Station> _stations = {};
  LatLng? _lastRaw;
  LatLng? _filtered;
  DateTime? _lastTime;
  final Distance _distance = const Distance();

  @override
  void initState() {
    super.initState();
    _mapWidget = TencentMap(
      myLocationEnabled: true,
      userLocationType: UserLocationType.trackingLocationRotate,
      onMapCreated: _onMapCreated,
      onPress: _onMapPress,
      onTapMarker: _onTapMarker,
      onLocation: _onLocation,
      onMarkerDragEnd: _onMarkerDragEnd,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _uiReady = true);
      _loadRemoteMarkers();
    });
  }

  Future<void> _loadRemoteMarkers() async {
    try {
      final items = await widget.api.listMarkers();
      for (final marker in items) {
        _upsertStation(_stationFromMarker(marker));
      }
      if (_controller != null && items.isNotEmpty) {
        final first = items.first;
        _controller!.moveCamera(
          CameraPosition(position: LatLng(first.lat, first.lng), zoom: 16),
        );
      }
      if (mounted) setState(() {});
    } on UnauthorizedApiException catch (e) {
      _showToast(e.message);
      widget.onLogout();
    } on ApiException catch (e) {
      _showToast(e.message);
    } catch (_) {
      _showToast('加载云端标记失败');
    }
  }

  Station _stationFromMarker(MarkerDto marker) {
    return Station(
      id: 'remote_${marker.id}',
      title: marker.title,
      note: marker.note,
      position: LatLng(marker.lat, marker.lng),
      isCustom: true,
      remoteId: marker.id,
      visible: marker.visible,
      canEdit: marker.canEdit,
      canDelete: marker.canDelete,
      ownerUsername: marker.ownerUsername,
    );
  }

  bool _matchesScope(Station station) {
    switch (_stationScope) {
      case _StationScope.all:
        return true;
      case _StationScope.mine:
        return station.canDelete;
      case _StationScope.shared:
        return !station.canDelete;
    }
  }

  bool _shouldDisplayOnMap(Station station) {
    return station.visible && _matchesScope(station);
  }

  void _syncMapMarkers() {
    if (_controller == null) return;
    for (final station in _stations.values) {
      _controller!.removeMarker(station.id);
    }
    for (final station in _stations.values) {
      if (!_shouldDisplayOnMap(station)) continue;
      _controller!.addMarker(
        Marker(
          id: station.id,
          position: station.position,
          icon: station.icon,
          anchor: Anchor(x: 0.5, y: 1.0),
          draggable: station.isCustom && station.canEdit,
        ),
      );
    }
  }

  void _upsertStation(Station station) {
    _stations[station.id] = station;
    if (_controller != null) {
      _controller!.removeMarker(station.id);
      if (!_shouldDisplayOnMap(station)) {
        return;
      }
      _controller!.addMarker(
        Marker(
          id: station.id,
          position: station.position,
          icon: station.icon,
          anchor: Anchor(x: 0.5, y: 1.0),
          draggable: station.isCustom && station.canEdit,
        ),
      );
    }
  }

  void _onMapCreated(TencentMapController controller) {
    _controller = controller;
    _syncMapMarkers();
  }

  Future<void> _onMarkerDragEnd(String markerId, LatLng position) async {
    final station = _stations[markerId];
    if (station == null || !station.canEdit) return;
    final moved = station.copyWith(position: position);
    setState(() => _upsertStation(moved));
    if (moved.remoteId == null) return;
    try {
      final updated = await widget.api.updateMarker(
        id: moved.remoteId!,
        lat: position.latitude,
        lng: position.longitude,
      );
      setState(
        () =>
            _upsertStation(_stationFromMarker(updated).copyWith(id: moved.id)),
      );
    } on UnauthorizedApiException catch (e) {
      _showToast(e.message);
      widget.onLogout();
    } on ApiException catch (e) {
      _showToast(e.message);
    } catch (_) {
      _showToast('拖拽位置保存失败');
    }
  }

  void _onLocation(Location loc) {
    final now = DateTime.now();
    final raw = loc.position;
    if (loc.accuracy != null && loc.accuracy! > 50) {
      return;
    }
    if (_lastRaw != null && _lastTime != null) {
      final dt = now.difference(_lastTime!).inSeconds.clamp(1, 999);
      final dist = _distance.as(LengthUnit.Meter, _lastRaw!, raw);
      if (dt < 3 && dist > 80) {
        return;
      }
    }
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
    if (mounted) setState(() {});
  }

  void _onTapMarker(String markerId) {
    final station = _stations[markerId];
    if (station != null) {
      _showStationInfo(station);
    }
  }

  void _onMapPress(LatLng pos) async {
    final nearest = _findNearestStation(pos, 25);
    if (nearest != null) {
      _showStationInfo(nearest);
      return;
    }

    final form = await _promptMarkerForm(
      title: '',
      note: '',
      position: pos,
      dialogTitle: '新增站点',
    );
    if (form == null) return;
    await _createMarkerAtPos(
      form.position,
      form.title,
      form.note,
      form.visible,
    );
  }

  Future<void> _createMarkerAtPos(
    LatLng pos,
    String title,
    String note,
    bool visible,
  ) async {
    try {
      final created = await widget.api.createMarker(
        title: title,
        note: note,
        lat: pos.latitude,
        lng: pos.longitude,
        visible: visible,
      );
      final station = _stationFromMarker(created);
      setState(() => _upsertStation(station));
      _showStationInfo(station);
    } on UnauthorizedApiException catch (e) {
      _showToast(e.message);
      widget.onLogout();
    } on ApiException catch (e) {
      _showToast(e.message);
    } catch (_) {
      _showToast('保存标记失败');
    }
  }

  Future<void> _editMarker(Station station) async {
    if (station.remoteId == null) {
      _showToast('当前标记不支持编辑');
      return;
    }
    final form = await _promptMarkerForm(
      title: station.title,
      note: station.note,
      position: station.position,
      visible: station.visible,
      dialogTitle: '编辑站点',
    );
    if (form == null) return;
    try {
      final updated = await widget.api.updateMarker(
        id: station.remoteId!,
        title: form.title,
        note: form.note,
        lat: form.position.latitude,
        lng: form.position.longitude,
        visible: form.visible,
      );
      final updatedStation = _stationFromMarker(
        updated,
      ).copyWith(id: station.id);
      setState(() => _upsertStation(updatedStation));
      if (!mounted) return;
      Navigator.pop(context);
      _showStationInfo(updatedStation);
    } on UnauthorizedApiException catch (e) {
      _showToast(e.message);
      widget.onLogout();
    } on ApiException catch (e) {
      _showToast(e.message);
    } catch (_) {
      _showToast('编辑失败');
    }
  }

  Future<void> _addAtCurrentLocation() async {
    if (_filtered == null) {
      _showToast('暂无定位，请稍等定位完成');
      return;
    }
    final form = await _promptMarkerForm(
      title: '',
      note: '',
      position: _filtered!,
      dialogTitle: '定位点新增站点',
    );
    if (form == null) return;
    await _createMarkerAtPos(
      form.position,
      form.title,
      form.note,
      form.visible,
    );
  }

  Station? _findNearestStation(LatLng pos, double meters) {
    Station? nearest;
    double minDistance = meters;
    for (final station in _stations.values) {
      if (!_shouldDisplayOnMap(station)) continue;
      final d = _distance.as(LengthUnit.Meter, pos, station.position);
      if (d <= minDistance) {
        minDistance = d;
        nearest = station;
      }
    }
    return nearest;
  }

  Future<_MarkerFormData?> _promptMarkerForm({
    required String title,
    required String note,
    required LatLng position,
    bool visible = true,
    required String dialogTitle,
  }) async {
    final titleCtrl = TextEditingController(text: title);
    final noteCtrl = TextEditingController(text: note);
    final latCtrl = TextEditingController(
      text: position.latitude.toStringAsFixed(6),
    );
    final lngCtrl = TextEditingController(
      text: position.longitude.toStringAsFixed(6),
    );
    var visibleValue = visible;
    return showDialog<_MarkerFormData>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '站点名称',
                  hintText: '如：姨妈家',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '如：门口有红灯笼',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: latCtrl,
                decoration: const InputDecoration(labelText: '纬度'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lngCtrl,
                decoration: const InputDecoration(labelText: '经度'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
              const SizedBox(height: 10),
              StatefulBuilder(
                builder: (context, setInnerState) {
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('显示标记'),
                    subtitle: const Text('关闭后地图隐藏，但数据保留'),
                    value: visibleValue,
                    onChanged: (value) =>
                        setInnerState(() => visibleValue = value),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final markerTitle = titleCtrl.text.trim();
                if (markerTitle.isEmpty) {
                  _showToast('站点名称不能为空');
                  return;
                }
                final lat = double.tryParse(latCtrl.text.trim());
                final lng = double.tryParse(lngCtrl.text.trim());
                if (lat == null || lng == null) {
                  _showToast('经纬度格式不正确');
                  return;
                }
                if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
                  _showToast('经纬度超出范围');
                  return;
                }
                Navigator.of(ctx).pop(
                  _MarkerFormData(
                    title: markerTitle,
                    note: noteCtrl.text.trim(),
                    position: LatLng(lat, lng),
                    visible: visibleValue,
                  ),
                );
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteStation(Station station) async {
    if (!station.canDelete) {
      _showToast('你没有删除权限');
      return;
    }
    if (station.remoteId != null) {
      try {
        await widget.api.deleteMarker(station.remoteId!);
      } on UnauthorizedApiException catch (e) {
        _showToast(e.message);
        widget.onLogout();
        return;
      } on ApiException catch (e) {
        _showToast(e.message);
        return;
      } catch (_) {
        _showToast('删除失败');
        return;
      }
    }
    _controller?.removeMarker(station.id);
    _stations.remove(station.id);
    if (mounted) {
      setState(() {});
      Navigator.pop(context);
    }
  }

  void _showStationInfo(Station station) {
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
              station.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              station.note.isEmpty ? '未填写备注' : station.note,
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Text(
              station.visible ? '状态：显示中' : '状态：已隐藏',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              station.ownerUsername.isEmpty
                  ? '所有者：未知'
                  : '所有者：${station.ownerUsername}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              '坐标：${station.position.latitude.toStringAsFixed(6)}, ${station.position.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _startWalkNavi(station),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('步行导航'),
                ),
                const SizedBox(width: 8),
                if (station.isCustom && station.canEdit)
                  OutlinedButton(
                    onPressed: () => _editMarker(station),
                    child: const Text('编辑'),
                  ),
                const SizedBox(width: 8),
                if (station.isCustom && station.canDelete)
                  OutlinedButton(
                    onPressed: () => _openShareManager(station),
                    child: const Text('共享'),
                  ),
                const SizedBox(width: 8),
                if (station.isCustom && station.canDelete)
                  TextButton(
                    onPressed: () => _deleteStation(station),
                    child: const Text('删除'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openShareManager(Station station) async {
    if (station.remoteId == null) {
      _showToast('当前标记不支持共享');
      return;
    }

    List<MarkerShareDto> initialShares;
    try {
      initialShares = await widget.api.listMarkerShares(station.remoteId!);
      initialShares.sort((a, b) => a.username.compareTo(b.username));
    } on UnauthorizedApiException catch (e) {
      _showToast(e.message);
      widget.onLogout();
      return;
    } on ApiException catch (e) {
      _showToast(e.message);
      return;
    } catch (_) {
      _showToast('加载共享列表失败');
      return;
    }

    final usernameCtrl = TextEditingController();
    var canEdit = false;
    var loading = false;
    List<MarkerShareDto> shares = initialShares;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        Future<void> refreshShares(StateSetter setModalState) async {
          setModalState(() => loading = true);
          try {
            shares = await widget.api.listMarkerShares(station.remoteId!);
            shares.sort((a, b) => a.username.compareTo(b.username));
          } on UnauthorizedApiException catch (e) {
            _showToast(e.message);
            widget.onLogout();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
            }
            return;
          } on ApiException catch (e) {
            _showToast(e.message);
          } catch (_) {
            _showToast('加载共享列表失败');
          } finally {
            if (mounted) setModalState(() => loading = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> submitShare() async {
              final username = usernameCtrl.text.trim();
              if (username.isEmpty) {
                _showToast('请输入用户名');
                return;
              }
              try {
                await widget.api.shareMarker(
                  markerId: station.remoteId!,
                  username: username,
                  canEdit: canEdit,
                );
                usernameCtrl.clear();
                setModalState(() => canEdit = false);
                await refreshShares(setModalState);
                _showToast('共享成功');
              } on UnauthorizedApiException catch (e) {
                _showToast(e.message);
                widget.onLogout();
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              } on ApiException catch (e) {
                _showToast(e.message);
              } catch (_) {
                _showToast('共享失败');
              }
            }

            Future<void> removeShare(MarkerShareDto share) async {
              try {
                await widget.api.removeMarkerShare(
                  markerId: station.remoteId!,
                  userId: share.userId,
                );
                await refreshShares(setModalState);
                _showToast('已取消共享');
              } on UnauthorizedApiException catch (e) {
                _showToast(e.message);
                widget.onLogout();
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              } on ApiException catch (e) {
                _showToast(e.message);
              } catch (_) {
                _showToast('取消共享失败');
              }
            }

            Future<void> toggleSharePermission(
              MarkerShareDto share,
              bool value,
            ) async {
              final previous = share.canEdit;
              setModalState(() {
                shares = shares
                    .map(
                      (item) => item.userId == share.userId
                          ? MarkerShareDto(
                              shareId: item.shareId,
                              userId: item.userId,
                              username: item.username,
                              canEdit: value,
                            )
                          : item,
                    )
                    .toList();
              });
              try {
                await widget.api.shareMarker(
                  markerId: station.remoteId!,
                  username: share.username,
                  canEdit: value,
                );
                _showToast('权限已更新');
              } on UnauthorizedApiException catch (e) {
                _showToast(e.message);
                widget.onLogout();
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              } on ApiException catch (e) {
                setModalState(() {
                  shares = shares
                      .map(
                        (item) => item.userId == share.userId
                            ? MarkerShareDto(
                                shareId: item.shareId,
                                userId: item.userId,
                                username: item.username,
                                canEdit: previous,
                              )
                            : item,
                      )
                      .toList();
                });
                _showToast(e.message);
              } catch (_) {
                setModalState(() {
                  shares = shares
                      .map(
                        (item) => item.userId == share.userId
                            ? MarkerShareDto(
                                shareId: item.shareId,
                                userId: item.userId,
                                username: item.username,
                                canEdit: previous,
                              )
                            : item,
                      )
                      .toList();
                });
                _showToast('更新权限失败');
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 6,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '共享：${station.title}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: '被共享用户名',
                        hintText: '输入家人账号用户名',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许编辑'),
                      subtitle: const Text('开启后对方可改名称/备注/坐标'),
                      value: canEdit,
                      onChanged: (value) =>
                          setModalState(() => canEdit = value),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: submitShare,
                        child: const Text('添加/更新共享'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          '已共享列表',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => refreshShares(setModalState),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : shares.isEmpty
                          ? const Center(child: Text('暂未共享给任何人'))
                          : ListView.separated(
                              itemCount: shares.length,
                              separatorBuilder: (_, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final share = shares[index];
                                return ListTile(
                                  title: Text(share.username),
                                  subtitle: Text(
                                    share.canEdit ? '权限：可编辑' : '权限：只读',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: share.canEdit,
                                        onChanged: (value) =>
                                            toggleSharePermission(share, value),
                                      ),
                                      TextButton(
                                        onPressed: () => removeShare(share),
                                        child: const Text('移除'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startWalkNavi(Station station) async {
    final uri = Uri.parse(
      'qqmap://map/routeplan'
      '?type=walk'
      '&fromcoord=CurrentLocation'
      '&to=${Uri.encodeComponent(station.title)}'
      '&tocoord=${station.position.latitude},${station.position.longitude}'
      '&referer=PW7BZ-MGAYW-HBYRD-YJSLR-ABPKQ-C4BEJ',
    );

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception('launch failed');
      }
    } catch (_) {
      _showToast('未检测到腾讯地图App，请先安装');
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setStationScope(_StationScope scope) {
    if (_stationScope == scope) return;
    setState(() {
      _stationScope = scope;
      _syncMapMarkers();
    });
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
                            Colors.white.withValues(alpha: 0.75),
                            Colors.white.withValues(alpha: 0.55),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
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
                                child: const Icon(
                                  Icons.map,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '拜年路线面板',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () {
                                  if (_filtered != null &&
                                      _controller != null) {
                                    _controller!.moveCamera(
                                      CameraPosition(
                                        position: _filtered,
                                        zoom: 17,
                                      ),
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
                            children: [
                              _StationChip(
                                title: '全部',
                                selected: _stationScope == _StationScope.all,
                                onTap: () =>
                                    _setStationScope(_StationScope.all),
                              ),
                              _StationChip(
                                title: '我的',
                                selected: _stationScope == _StationScope.mine,
                                onTap: () =>
                                    _setStationScope(_StationScope.mine),
                              ),
                              _StationChip(
                                title: '共享给我',
                                selected: _stationScope == _StationScope.shared,
                                onTap: () =>
                                    _setStationScope(_StationScope.shared),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: widget.onLogout,
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('退出登录'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 160,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: _uiReady ? 1 : 0,
              child: Card(
                color: Colors.amber.shade100,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('提示：出发前请在腾讯地图App里下载“乡村/县城”离线包。'),
                ),
              ),
            ),
          ),
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
                              ? '定位中...'
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
          Positioned(
            right: 12,
            bottom: 142,
            child: FloatingActionButton.small(
              onPressed: _openStationList,
              child: const Icon(Icons.list),
            ),
          ),
        ],
      ),
    );
  }

  void _openStationList() {
    final searchCtrl = TextEditingController();
    List<Station> all = _stations.values.where(_matchesScope).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    List<Station> filtered = List<Station>.from(all);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void applyFilter(String keyword) {
              final key = keyword.trim().toLowerCase();
              setModalState(() {
                filtered = key.isEmpty
                    ? List<Station>.from(all)
                    : all
                          .where((s) => s.title.toLowerCase().contains(key))
                          .toList();
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 6,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: Column(
                  children: [
                    TextField(
                      controller: searchCtrl,
                      onChanged: applyFilter,
                      decoration: const InputDecoration(
                        hintText: '搜索标点名称',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('没有匹配的标点'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final station = filtered[index];
                                return ListTile(
                                  title: Text(station.title),
                                  subtitle: Text(
                                    '${station.position.latitude.toStringAsFixed(5)}, '
                                    '${station.position.longitude.toStringAsFixed(5)}'
                                    '\n${station.ownerUsername.isEmpty ? 'owner: unknown' : 'owner: ${station.ownerUsername}'}'
                                    '${station.canEdit ? ' · 可编辑' : ' · 只读'}'
                                    '${station.visible ? '' : ' · 已隐藏'}',
                                  ),
                                  isThreeLine: true,
                                  onTap: () {
                                    _controller?.moveCamera(
                                      CameraPosition(
                                        position: station.position,
                                        zoom: 17,
                                      ),
                                    );
                                    Navigator.pop(ctx);
                                    _showStationInfo(station);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StationChip extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback? onTap;

  const _StationChip({required this.title, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2E7D32)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF2E7D32)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _MarkerFormData {
  final String title;
  final String note;
  final LatLng position;
  final bool visible;

  const _MarkerFormData({
    required this.title,
    required this.note,
    required this.position,
    required this.visible,
  });
}
