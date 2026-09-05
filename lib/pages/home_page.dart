import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_usage.dart';
import '../services/export_service.dart';
import '../services/monitor_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final MonitorService _monitor = MonitorService();
  final ExportService _export = ExportService();

  late final TabController _tabController;
  late final AnimationController _pulseController;

  StreamSubscription<List<FlowEntry>>? _flowSub;
  Timer? _durationTimer;

  List<AppInfo> _installedApps = [];
  final Set<String> _selectedPackages = {};
  List<FlowEntry> _flows = [];

  bool _loadingApps = true;
  bool _running = false;
  bool _busy = false;

  Duration _elapsed = Duration.zero;

  String _searchQuery = '';
  String _protocolFilter = 'ALL';
  String _sortMode = 'recent';

  final Map<String, IpInfo> _ipInfoCache = {};
  final Set<String> _ipLookupLoading = {};
  final Set<String> _ipLookupFailed = {};

  HttpClient? _httpClient;

  static const _bg = Color(0xFFF4F7FC);
  static const _ink = Color(0xFF111827);

  static const _brandA = Color.fromARGB(255, 0, 78, 187);
  static const _brandB = Color(0xFF4D9BFF);

  static const _accentTeal = Color(0xFF00BFA6);
  static const _accentOrange = Color(0xFFFFA62B);
  static const _accentPurple = Color(0xFF7C5CFC);

  @override
  void initState() {
    super.initState();

    _httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10);

    _tabController = TabController(
      length: 2,
      vsync: this,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await _monitor.listInstalledApps();

      apps.sort(
        (a, b) => a.appName.toLowerCase().compareTo(
              b.appName.toLowerCase(),
            ),
      );

      if (!mounted) return;

      setState(() {
        _installedApps = apps;
        _loadingApps = false;
      });
    } catch (e) {
      dev.log(
        'App list failed: $e',
        name: 'GenNet',
      );

      if (!mounted) return;

      setState(() {
        _loadingApps = false;
      });

      _show('Could not load installed apps');
    }
  }

  Future<IpInfo?> _lookupIp(String ip) async {
    final normalizedIp = ip.trim();

    if (normalizedIp.isEmpty) return null;

    if (_isPrivateOrLocalIp(normalizedIp)) {
      final localInfo = IpInfo(
        ip: normalizedIp,
        success: true,
        country: 'Local network',
        countryCode: '',
        region: '',
        city: 'Local',
        latitude: null,
        longitude: null,
        isp: '',
        org: '',
        asn: '',
        timezone: '',
        type: '',
        hostname: '',
      );

      if (mounted) {
        setState(() {
          _ipInfoCache[normalizedIp] = localInfo;
        });
      }

      return localInfo;
    }

    final cached = _ipInfoCache[normalizedIp];

    if (cached != null) {
      return cached;
    }

    if (_ipLookupLoading.contains(normalizedIp)) {
      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 100));

        final result = _ipInfoCache[normalizedIp];

        if (result != null) {
          return result;
        }

        if (!_ipLookupLoading.contains(normalizedIp)) {
          break;
        }
      }

      return _ipInfoCache[normalizedIp];
    }

    _ipLookupLoading.add(normalizedIp);

    try {
      dev.log(
        'IP lookup: $normalizedIp',
        name: 'GenNet',
      );

      final client = _httpClient ?? HttpClient();

      final uri = Uri.https(
        'ipwho.is',
        '/$normalizedIp',
      );

      final request = await client.getUrl(uri);

      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json',
      );

      final response = await request.close();

      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'IP API HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid IP API response',
        );
      }

      final info = IpInfo.fromJson(decoded);

      if (mounted) {
        setState(() {
          _ipInfoCache[normalizedIp] = info;
          _ipLookupFailed.remove(normalizedIp);
        });
      }

      dev.log(
        'IP lookup success: $normalizedIp -> '
        '${info.country}, ${info.city}',
        name: 'GenNet',
      );

      return info;
    } catch (e) {
      dev.log(
        'IP lookup failed [$normalizedIp]: $e',
        name: 'GenNet',
      );

      if (mounted) {
        setState(() {
          _ipLookupFailed.add(normalizedIp);
        });
      }

      return null;
    } finally {
      _ipLookupLoading.remove(normalizedIp);

      if (_httpClient == null) {
        // no-op
      }

      if (mounted) {
        setState(() {});
      }
    }
  }

  bool _isPrivateOrLocalIp(String ip) {
    final parts = ip.split('.');

    if (parts.length == 4) {
      final numbers = <int>[];

      for (final part in parts) {
        final n = int.tryParse(part);

        if (n == null) {
          return false;
        }

        numbers.add(n);
      }

      final a = numbers[0];
      final b = numbers[1];

      if (a == 10) return true;

      if (a == 172 && b >= 16 && b <= 31) {
        return true;
      }

      if (a == 192 && b == 168) {
        return true;
      }

      if (a == 127) return true;

      if (a == 169 && b == 254) {
        return true;
      }

      if (a == 0) return true;

      return false;
    }

    final lower = ip.toLowerCase();

    if (lower == '::1') return true;
    if (lower == '::') return true;
    if (lower.startsWith('fe80:')) return true;
    if (lower.startsWith('fc')) return true;
    if (lower.startsWith('fd')) return true;

    return false;
  }

  void _startIpLookups(List<FlowEntry> flows) {
    final uniqueIps = <String>{};

    for (final flow in flows) {
      final ip = flow.destinationIp.trim();

      if (ip.isNotEmpty) {
        uniqueIps.add(ip);
      }
    }

    for (final ip in uniqueIps) {
      if (_ipInfoCache.containsKey(ip)) continue;
      if (_ipLookupLoading.contains(ip)) continue;

      _lookupIp(ip);
    }
  }

  Future<void> _toggleMonitoring() async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      if (_running) {
        await _monitor.stop();

        await _flowSub?.cancel();
        _flowSub = null;

        _durationTimer?.cancel();
        _durationTimer = null;

        if (!mounted) return;

        setState(() {
          _running = false;
        });

        _show('Monitoring stopped');

        return;
      }

      if (_selectedPackages.isEmpty) {
        _show('Select at least one app first.');
        return;
      }

      final status = await _monitor.start(
        _selectedPackages.toList(),
      );

      if (status == 'permission_required') {
        _show(
          'Approve the VPN permission dialog, then press START again.',
        );
        return;
      }

      if (status != 'started') {
        _show(
          'Could not start monitor: $status',
        );
        return;
      }

      await _flowSub?.cancel();

      _flowSub = _monitor.flowStream.listen(
        (flows) {
          if (!mounted) return;

          setState(() {
            _flows = List<FlowEntry>.from(flows);
          });

          _startIpLookups(flows);
        },
        onError: (error) {
          dev.log(
            'Flow stream error: $error',
            name: 'GenNet',
          );
        },
      );

      if (!mounted) return;

      setState(() {
        _running = true;
        _elapsed = Duration.zero;
        _flows = [];
      });

      _durationTimer?.cancel();

      _durationTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          final start = _monitor.sessionStart;

          if (!mounted || start == null) return;

          setState(() {
            _elapsed = DateTime.now().difference(start);
          });
        },
      );

      _show('Monitoring started');

      _tabController.animateTo(1);
    } catch (e) {
      dev.log(
        'Monitor toggle failed: $e',
        name: 'GenNet',
      );

      if (mounted) {
        _show('Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openAppSelector() async {
    if (_running) return;

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final temp = Set<String>.from(_selectedPackages);

        String search = '';

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _installedApps.where((app) {
              final q = search.trim().toLowerCase();

              if (q.isEmpty) return true;

              return app.appName.toLowerCase().contains(q) ||
                  app.packageName.toLowerCase().contains(q);
            }).toList();

            final allFilteredSelected = filtered.isNotEmpty &&
                filtered.every(
                  (app) => temp.contains(app.packageName),
                );

            return DraggableScrollableSheet(
              initialChildSize: .85,
              minChildSize: .45,
              maxChildSize: .96,
              expand: false,
              builder: (_, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      _sheetHandle(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          18,
                          20,
                          6,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Select apps',
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${temp.length} of ${_installedApps.length} selected',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _pillButton(
                              label: allFilteredSelected
                                  ? 'CLEAR ALL'
                                  : 'SELECT ALL',
                              filled: false,
                              onTap: () {
                                setSheetState(() {
                                  if (allFilteredSelected) {
                                    for (final app in filtered) {
                                      temp.remove(app.packageName);
                                    }
                                  } else {
                                    for (final app in filtered) {
                                      temp.add(app.packageName);
                                    }
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          0,
                        ),
                        child: TextField(
                          onChanged: (value) {
                            setSheetState(() {
                              search = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search installed apps',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.grey.shade500,
                            ),
                            suffixIcon: search.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      setSheetState(() {
                                        search = '';
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: _bg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _loadingApps
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: _brandA,
                                ),
                              )
                            : filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      'No apps found',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    controller: controller,
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      6,
                                      12,
                                      24,
                                    ),
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 4),
                                    itemBuilder: (_, index) {
                                      final app = filtered[index];

                                      final checked = temp.contains(
                                        app.packageName,
                                      );

                                      return _appSelectorRow(
                                        // Stable identity per app, keyed
                                        // by package name -- without
                                        // this, Flutter can reuse a
                                        // row's Element/State for a
                                        // DIFFERENT app after the list
                                        // is filtered by search, making
                                        // an app look like it got
                                        // "unselected" (or its check
                                        // animation replay) even though
                                        // nothing in `temp` actually
                                        // changed.
                                        key: ValueKey(app.packageName),
                                        app: app,
                                        checked: checked,
                                        onChanged: (value) {
                                          setSheetState(() {
                                            if (value == true) {
                                              temp.add(
                                                app.packageName,
                                              );
                                            } else {
                                              temp.remove(
                                                app.packageName,
                                              );
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            20,
                            8,
                            20,
                            14,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: _gradientButton(
                              label: 'DONE',
                              onTap: () => Navigator.pop(ctx, temp),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _selectedPackages
          ..clear()
          ..addAll(result);
      });
    }
  }

  Widget _appSelectorRow({
    Key? key,
    required AppInfo app,
    required bool checked,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(!checked),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: checked ? _brandA.withOpacity(.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _appIcon(app, size: 42),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            _checkDot(checked),
          ],
        ),
      ),
    );
  }

  Widget _checkDot(bool checked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: checked
            ? const LinearGradient(
                colors: [_brandA, _brandB],
              )
            : null,
        color: checked ? null : Colors.white,
        border: Border.all(
          color: checked ? Colors.transparent : Colors.grey.shade300,
          width: 1.6,
        ),
      ),
      child: checked
          ? const Icon(
              Icons.check_rounded,
              size: 16,
              color: Colors.white,
            )
          : null,
    );
  }

  Widget _sheetHandle() {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Future<void> _exportCsv() async {
    if (_flows.isEmpty) {
      _show('No traffic data to export.');
      return;
    }

    try {
      final file = await _export.exportCsv(_flows);

      _show(
        'CSV exported:\n${file.path}',
      );
    } catch (e) {
      _show('CSV export failed: $e');
    }
  }

  Future<void> _exportTxt() async {
    if (_flows.isEmpty) {
      _show('No traffic data to export.');
      return;
    }

    try {
      final file = await _export.exportTxt(_flows);

      _show(
        'TXT exported:\n${file.path}',
      );
    } catch (e) {
      _show('TXT export failed: $e');
    }
  }

  void _clearFlows() {
    if (_flows.isEmpty) {
      _show('Nothing to clear.');
      return;
    }

    setState(() {
      _flows = [];
    });

    _show('Live traffic list cleared');
  }

  void _pipOverlay() async {
    final hasPermission = await _monitor.hasOverlayPermission();

    if (!hasPermission) {
      if (!mounted) return;
      _show('Enable "Display over other apps" permission, then tap again.');
      await _monitor.openOverlayPermission();
      return;
    }

    try {
      await _monitor.startOverlay();
      if (!mounted) return;
      _show('Floating panel started — switch to your game/app to see it.');
    } catch (e) {
      if (!mounted) return;
      _show('Could not start overlay: $e');
    }
  }

  List<FlowEntry> get _visibleFlows {
    List<FlowEntry> result = List<FlowEntry>.from(_flows);

    final search = _searchQuery.trim().toLowerCase();

    if (search.isNotEmpty) {
      result = result.where((flow) {
        final ipInfo = _ipInfoCache[flow.destinationIp];

        return flow.destinationIp.toLowerCase().contains(search) ||
            flow.destinationPort.toString().contains(search) ||
            flow.protocol.toLowerCase().contains(search) ||
            (ipInfo?.country ?? '').toLowerCase().contains(search) ||
            (ipInfo?.city ?? '').toLowerCase().contains(search) ||
            (ipInfo?.isp ?? '').toLowerCase().contains(search) ||
            (ipInfo?.org ?? '').toLowerCase().contains(search);
      }).toList();
    }

    if (_protocolFilter != 'ALL') {
      result = result.where((flow) {
        return flow.protocol.toUpperCase() == _protocolFilter.toUpperCase();
      }).toList();
    }

    switch (_sortMode) {
      case 'bytes':
        result.sort(
          (a, b) => b.bytes.compareTo(a.bytes),
        );
        break;

      case 'port':
        result.sort(
          (a, b) => a.destinationPort.compareTo(
            b.destinationPort,
          ),
        );
        break;

      case 'recent':
      default:
        break;
    }

    return result;
  }

  int get _totalBytes {
    return _flows.fold<int>(
      0,
      (sum, flow) => sum + flow.bytes,
    );
  }

  int get _tcpCount {
    return _flows
        .where(
          (e) => e.protocol.toUpperCase() == 'TCP',
        )
        .length;
  }

  int get _udpCount {
    return _flows
        .where(
          (e) => e.protocol.toUpperCase() == 'UDP',
        )
        .length;
  }

  void _show(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(14),
        ),
      );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(d.inHours)}:'
        '${two(d.inMinutes.remainder(60))}:'
        '${two(d.inSeconds.remainder(60))}';
  }

  String _protocolLabel(String protocol) {
    final value = protocol.toUpperCase();

    if (value == 'TCP') return 'TCP';
    if (value == 'UDP') return 'UDP';
    if (value == 'ICMP') return 'ICMP';

    return value;
  }

  Color _protocolColor(String protocol) {
    final value = protocol.toUpperCase();

    if (value == 'TCP') {
      return _accentTeal;
    }

    if (value == 'UDP') {
      return _accentOrange;
    }

    if (value == 'ICMP') {
      return _accentPurple;
    }

    return Colors.grey;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pulseController.dispose();
    _flowSub?.cancel();
    _durationTimer?.cancel();
    _httpClient?.close(force: true);
    _monitor.dispose();

    super.dispose();
  }

  Widget _gradientButton({
    required String label,
    required VoidCallback? onTap,
    Widget? icon,
  }) {
    final disabled = onTap == null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: disabled
            ? LinearGradient(
                colors: [
                  Colors.grey.shade300,
                  Colors.grey.shade300,
                ],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_brandA, _brandB],
              ),
        boxShadow: disabled
            ? []
            : [
                BoxShadow(
                  color: _brandA.withOpacity(.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  icon,
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: disabled ? Colors.grey.shade600 : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required VoidCallback onTap,
    bool filled = true,
  }) {
    return Material(
      color: filled ? _brandA.withOpacity(.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _brandA,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: .3,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(150),
        child: _header(),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            _setupTab(),
            _trafficTab(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandA, _brandB],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x332563EB),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            6,
            16,
            8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 42,
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.podcasts_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'GenNet',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _headerStatusPill(),
                    const SizedBox(width: 2),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                      onSelected: (value) {
                        if (value == 'csv') {
                          _exportCsv();
                        } else if (value == 'txt') {
                          _exportTxt();
                        } else if (value == 'pip') {
                          _pipOverlay();
                        } else if (value == 'clear') {
                          _clearFlows();
                        }
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'csv',
                          child: Row(
                            children: [
                              Icon(
                                Icons.table_chart_outlined,
                                size: 19,
                              ),
                              SizedBox(width: 10),
                              Text('Export CSV'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'txt',
                          child: Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 19,
                              ),
                              SizedBox(width: 10),
                              Text('Export TXT'),
                            ],
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'pip',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 19,
                              ),
                              SizedBox(width: 10),
                              Text('Floating overlay (PIP)'),
                            ],
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'clear',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 19,
                              ),
                              SizedBox(width: 10),
                              Text('Clear traffic'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                height: 40,
                child: _segmentedTabs(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerStatusPill() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final pulse = _running ? _pulseController.value : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _running
                      ? Color.lerp(
                          const Color(0xFF00E5A0),
                          Colors.white,
                          pulse * .5,
                        )
                      : Colors.white54,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _running ? 'LIVE' : 'IDLE',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segmentedTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: _brandA,
        unselectedLabelColor: Colors.white,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        tabs: [
          const Tab(
            height: 40,
            child: _TabLabel(
              icon: Icons.tune_rounded,
              label: 'Setup',
            ),
          ),
          Tab(
            height: 40,
            child: _TabLabel(
              icon: Icons.podcasts_rounded,
              label: 'Live traffic',
              badgeCount: _flows.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _setupTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _controlCard(),
        const SizedBox(height: 12),
        _quickStatsRow(),
        if (!_running) ...[
          const SizedBox(height: 12),
          _tipCard(),
        ],
      ],
    );
  }

  Widget _controlCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_brandA, _brandB],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Network Monitor',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _running
                          ? 'Monitoring • ${_formatDuration(_elapsed)}'
                          : 'Select apps to monitor',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _ringIndicator(),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _running || _loadingApps ? null : _openAppSelector,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
              ),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.apps_rounded,
                    size: 19,
                    color: _running ? Colors.grey : _brandA,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedPackages.isEmpty
                          ? 'Select apps'
                          : '${_selectedPackages.length} app(s) selected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _running ? Colors.grey : _ink,
                      ),
                    ),
                  ),
                  if (!_running)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey.shade400,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: _gradientButton(
              label: _busy
                  ? 'PLEASE WAIT'
                  : _running
                      ? 'STOP MONITORING'
                      : 'START MONITORING',
              onTap: _busy ? null : _toggleMonitoring,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
            ),
          ),
          if (_selectedPackages.isNotEmpty) ...[
            const SizedBox(height: 24),
            _selectedAppNames(),
          ],
        ],
      ),
    );
  }

  Widget _ringIndicator() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final scale = _running ? 1 + (_pulseController.value * .12) : 1.0;

        return Transform.scale(
          scale: scale,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _running
                  ? const Color(0xFF00E5A0).withOpacity(.14)
                  : Colors.grey.withOpacity(.08),
              border: Border.all(
                color:
                    _running ? const Color(0xFF00E5A0) : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: Icon(
              _running ? Icons.bolt_rounded : Icons.bolt_outlined,
              color: _running ? const Color(0xFF00B589) : Colors.grey.shade400,
              size: 22,
            ),
          ),
        );
      },
    );
  }

  Widget _quickStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _miniStatCard(
            icon: Icons.swap_vert_rounded,
            value: '${_flows.length}',
            label: 'Flows',
            color: _brandA,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStatCard(
            icon: Icons.data_usage_rounded,
            value: AppUsage.humanBytes(_totalBytes),
            label: 'Data',
            color: _accentTeal,
          ),
        ),
      ],
    );
  }

  Widget _miniStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipCard() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _brandA.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _brandA.withOpacity(.10),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            color: _brandA,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _selectedPackages.isEmpty
                  ? 'Select an app and press START to monitor traffic.'
                  : 'Press START and open the selected app to see traffic.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey.shade700,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedAppNames() {
    final names = _selectedPackages.map((packageName) {
      final app = _installedApps.where(
        (a) => a.packageName == packageName,
      );

      if (app.isEmpty) return packageName;

      return app.first.appName;
    }).toList();

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: names.map((name) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _brandA.withOpacity(.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              color: _brandA,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _trafficTab() {
    final visibleFlows = _visibleFlows;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: _compactStats(),
        ),
        SliverToBoxAdapter(
          child: _compactToolbar(),
        ),
        if (visibleFlows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(),
          )
        else
          SliverList.builder(
            itemCount: visibleFlows.length,
            itemBuilder: (_, index) => _flowTile(visibleFlows[index]),
          ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
    );
  }

  Widget _compactStats() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        10,
        16,
        6,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _compactStat(
            Icons.swap_vert_rounded,
            _flows.length.toString(),
            _brandA,
          ),
          _compactDivider(),
          _compactStat(
            Icons.data_usage_rounded,
            AppUsage.humanBytes(_totalBytes),
            _ink,
          ),
          _compactDivider(),
          _compactStat(
            Icons.arrow_upward_rounded,
            _tcpCount.toString(),
            _accentTeal,
          ),
          _compactDivider(),
          _compactStat(
            Icons.arrow_downward_rounded,
            _udpCount.toString(),
            _accentOrange,
          ),
        ],
      ),
    );
  }

  Widget _compactStat(
    IconData icon,
    String value,
    Color color,
  ) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactDivider() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.grey.shade200,
    );
  }

  Widget _compactToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        5,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    style: const TextStyle(
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search IP, country, ISP or port',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: Colors.grey.shade500,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(
                                Icons.clear_rounded,
                                size: 17,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: 'Sort',
                  onSelected: (value) {
                    setState(() {
                      _sortMode = value;
                    });
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  icon: const Icon(
                    Icons.swap_vert_rounded,
                    size: 20,
                    color: _brandA,
                  ),
                  itemBuilder: (_) => [
                    _sortItem(
                      'recent',
                      'Recent',
                      Icons.access_time_rounded,
                    ),
                    _sortItem(
                      'bytes',
                      'Most bytes',
                      Icons.data_usage_rounded,
                    ),
                    _sortItem(
                      'port',
                      'Port',
                      Icons.numbers_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _compactFilter('ALL'),
                      _compactFilter('TCP'),
                      _compactFilter('UDP'),
                      _compactFilter('ICMP'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear',
                onPressed: _flows.isEmpty ? null : _clearFlows,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'Export',
                onSelected: (value) {
                  if (value == 'csv') {
                    _exportCsv();
                  } else {
                    _exportTxt();
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                icon: Icon(
                  Icons.file_download_outlined,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'csv',
                    child: Text('Export CSV'),
                  ),
                  PopupMenuItem(
                    value: 'txt',
                    child: Text('Export TXT'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Live traffic · ${_visibleFlows.length}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactFilter(String value) {
    final selected = _protocolFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _protocolFilter = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [_brandA, _brandB],
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Colors.transparent : Colors.grey.shade300,
            ),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _flowTile(FlowEntry flow) {
    final protocol = _protocolLabel(flow.protocol);

    final protocolColor = _protocolColor(protocol);

    final ipInfo = _ipInfoCache[flow.destinationIp];

    AppInfo? app;

    for (final item in _installedApps) {
      if (item.uid == flow.uid) {
        app = item;
        break;
      }
    }

    final isLoading = _ipLookupLoading.contains(
      flow.destinationIp,
    );

    return InkWell(
      onTap: () => _showFlowDetails(
        flow,
        app,
      ),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 3,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.025),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            app != null
                ? _appIcon(
                    app,
                    size: 38,
                  )
                : Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: protocolColor.withOpacity(.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.apps_rounded,
                      color: protocolColor,
                      size: 19,
                    ),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app?.appName ?? 'Unknown app',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: protocolColor.withOpacity(.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          protocol,
                          style: TextStyle(
                            color: protocolColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${flow.destinationIp}:${flow.destinationPort}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (isLoading)
                    Row(
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: _brandA,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Looking up IP...',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    )
                  else if (ipInfo != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.public_rounded,
                          size: 12,
                          color: _brandA,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _ipLocationText(
                              ipInfo,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.8,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      _ipLookupFailed.contains(
                        flow.destinationIp,
                      )
                          ? 'IP information unavailable'
                          : 'IP information loading...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppUsage.humanBytes(
                    flow.bytes,
                  ),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'IPv${flow.ipVersion}',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  String _ipLocationText(IpInfo info) {
    final parts = <String>[];

    if (info.city.isNotEmpty) {
      parts.add(info.city);
    }

    if (info.country.isNotEmpty) {
      parts.add(info.country);
    }

    if (parts.isEmpty && info.isp.isNotEmpty) {
      return info.isp;
    }

    return parts.join(', ');
  }

  void _showFlowDetails(
    FlowEntry flow,
    AppInfo? app,
  ) {
    final protocol = _protocolLabel(flow.protocol);

    final protocolColor = _protocolColor(protocol);

    final existingInfo = _ipInfoCache[flow.destinationIp];

    if (existingInfo == null &&
        !_isPrivateOrLocalIp(
          flow.destinationIp,
        )) {
      _lookupIp(flow.destinationIp);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: .78,
          minChildSize: .42,
          maxChildSize: .95,
          expand: false,
          builder: (_, scrollController) {
            return StatefulBuilder(
              builder: (context, sheetSetState) {
                final info = _ipInfoCache[flow.destinationIp];

                final loading = _ipLookupLoading.contains(
                  flow.destinationIp,
                );

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      28,
                    ),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          margin: const EdgeInsets.only(
                            bottom: 20,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(
                              20,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          app != null
                              ? _appIcon(
                                  app,
                                  size: 54,
                                )
                              : Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: protocolColor.withOpacity(
                                      .12,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      17,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.apps_rounded,
                                    color: protocolColor,
                                    size: 27,
                                  ),
                                ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app?.appName ?? 'Unknown app',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                if (app?.packageName != null) ...[
                                  const SizedBox(
                                    height: 3,
                                  ),
                                  Text(
                                    app!.packageName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: protocolColor.withOpacity(.12),
                              borderRadius: BorderRadius.circular(
                                20,
                              ),
                            ),
                            child: Text(
                              protocol,
                              style: TextStyle(
                                color: protocolColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 17,
                          horizontal: 17,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _brandA,
                              _brandB,
                            ],
                          ),
                          borderRadius: BorderRadius.all(
                            Radius.circular(18),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.data_usage_rounded,
                              color: Colors.white,
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            const Text(
                              'Data transferred',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              AppUsage.humanBytes(
                                flow.bytes,
                              ),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Connection',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _detailTile(
                        icon: Icons.dns_outlined,
                        title: 'Destination IP',
                        value: flow.destinationIp,
                        copyable: true,
                      ),
                      _detailTile(
                        icon: Icons.settings_ethernet_rounded,
                        title: 'Port',
                        value: flow.destinationPort.toString(),
                        copyable: true,
                      ),
                      _detailTile(
                        icon: Icons.swap_horiz_rounded,
                        title: 'Protocol',
                        value: flow.protocol,
                      ),
                      _detailTile(
                        icon: Icons.language_rounded,
                        title: 'IP version',
                        value: 'IPv${flow.ipVersion}',
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Icon(
                            Icons.public_rounded,
                            color: _brandA,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'IP information',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                          ),
                          if (loading)
                            const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _brandA,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (loading && info == null)
                        Container(
                          padding: const EdgeInsets.all(
                            18,
                          ),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _brandA,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Fetching IP information...',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (info != null)
                        _ipInfoCard(info)
                      else
                        Container(
                          padding: const EdgeInsets.all(
                            18,
                          ),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              const Expanded(
                                child: Text(
                                  'Could not load IP information.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await _lookupIp(
                                    flow.destinationIp,
                                  );

                                  sheetSetState(
                                    () {},
                                  );
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _ipInfoCard(IpInfo info) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _ipDetailRow(
            icon: Icons.public_rounded,
            title: 'Country',
            value: _display(
              info.country,
            ),
          ),
          _ipDetailRow(
            icon: Icons.flag_outlined,
            title: 'Country code',
            value: _display(
              info.countryCode,
            ),
          ),
          _ipDetailRow(
            icon: Icons.location_city_rounded,
            title: 'City',
            value: _display(
              info.city,
            ),
          ),
          _ipDetailRow(
            icon: Icons.map_outlined,
            title: 'Region',
            value: _display(
              info.region,
            ),
          ),
          _ipDetailRow(
            icon: Icons.business_outlined,
            title: 'ISP',
            value: _display(
              info.isp,
            ),
          ),
          _ipDetailRow(
            icon: Icons.corporate_fare_rounded,
            title: 'Organization',
            value: _display(
              info.org,
            ),
          ),
          _ipDetailRow(
            icon: Icons.tag_rounded,
            title: 'ASN',
            value: _display(
              info.asn,
            ),
          ),
          _ipDetailRow(
            icon: Icons.access_time_rounded,
            title: 'Timezone',
            value: _display(
              info.timezone,
            ),
          ),
          _ipDetailRow(
            icon: Icons.gps_fixed_rounded,
            title: 'Coordinates',
            value: info.hasCoordinates
                ? '${info.latitude!.toStringAsFixed(5)}, '
                    '${info.longitude!.toStringAsFixed(5)}'
                : 'Unavailable',
            isLast: true,
          ),
        ],
      ),
    );
  }

  String _display(String value) {
    return value.trim().isEmpty ? 'Unavailable' : value;
  }

  Widget _ipDetailRow({
    required IconData icon,
    required String title,
    required String value,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: _brandA,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 95,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile({
    required IconData icon,
    required String title,
    required String value,
    bool copyable = false,
    bool isLast = false,
  }) {
    return Container(
      margin: EdgeInsets.only(
        bottom: isLast ? 0 : 10,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 18,
              color: _brandA,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.copy_rounded,
                size: 18,
                color: Colors.grey.shade600,
              ),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: value),
                );
                _show('Copied "$value"');
              },
            ),
        ],
      ),
    );
  }

  Widget _appIcon(
    AppInfo app, {
    double size = 44,
  }) {
    if (app.icon != null && app.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: Image.memory(
          app.icon!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }

    final hue = (app.appName.isEmpty ? 0 : app.appName.codeUnitAt(0) * 37 % 360)
        .toDouble();

    final color = HSLColor.fromAHSL(
      1,
      hue,
      .55,
      .55,
    ).toColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(.14),
        borderRadius: BorderRadius.circular(
          size * .26,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        app.appName.isEmpty ? '?' : app.appName.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: size * .38,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(
    String value,
    String title,
    IconData icon,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: _brandA,
          ),
          const SizedBox(width: 10),
          Text(title),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) {
                final scale = _running ? 1 + _pulseController.value * .08 : 1.0;

                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _brandA.withOpacity(.14),
                          _brandB.withOpacity(.14),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _running ? Icons.radar_rounded : Icons.radar_outlined,
                      size: 44,
                      color: _brandA,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'No traffic yet',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedPackages.isEmpty
                  ? 'Go to the Setup tab, select a test app and press START.'
                  : _running
                      ? 'Open the selected app and generate some network traffic.'
                      : 'Go to the Setup tab and press START to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => _tabController.animateTo(0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brandA,
                  side: const BorderSide(
                    color: _brandA,
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                  ),
                ),
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 18,
                ),
                label: const Text(
                  'Go to Setup',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IpInfo {
  final String ip;
  final bool success;

  final String country;
  final String countryCode;
  final String region;
  final String city;

  final double? latitude;
  final double? longitude;

  final String isp;
  final String org;
  final String asn;

  final String timezone;
  final String type;
  final String hostname;

  const IpInfo({
    required this.ip,
    required this.success,
    required this.country,
    required this.countryCode,
    required this.region,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.isp,
    required this.org,
    required this.asn,
    required this.timezone,
    required this.type,
    required this.hostname,
  });

  factory IpInfo.fromJson(
    Map<String, dynamic> json,
  ) {
    final connection = json['connection'];

    final timezone = json['timezone'];

    return IpInfo(
      ip: json['ip']?.toString() ?? '',
      success: json['success'] == true,
      country: json['country']?.toString() ?? '',
      countryCode: json['country_code']?.toString() ?? '',
      region: json['region']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      latitude: _toDouble(
        json['latitude'],
      ),
      longitude: _toDouble(
        json['longitude'],
      ),
      isp: connection is Map ? connection['isp']?.toString() ?? '' : '',
      org: connection is Map ? connection['org']?.toString() ?? '' : '',
      asn: connection is Map ? connection['asn']?.toString() ?? '' : '',
      timezone: timezone is Map ? timezone['id']?.toString() ?? '' : '',
      type: json['type']?.toString() ?? '',
      hostname: json['hostname']?.toString() ?? '',
    );
  }

  bool get hasCoordinates => latitude != null && longitude != null;

  static double? _toDouble(
    dynamic value,
  ) {
    if (value == null) return null;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.icon,
    required this.label,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label),
        if (badgeCount != null && badgeCount! > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badgeCount! > 99 ? '99+' : '$badgeCount',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
