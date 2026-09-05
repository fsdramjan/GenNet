import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../model/vpn/app_usage.dart';
import '../../../service/vpn/export_service.dart';
import '../../../service/vpn/monitor_service.dart';

class VpnPage extends StatefulWidget {
  VpnPage({super.key});

  @override
  State<VpnPage> createState() => _VpnPageState();
}

class _VpnPageState extends State<VpnPage> with TickerProviderStateMixin {
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

  // ---------------------------------------------------------------------
  // DARK THEME PALETTE
  // ---------------------------------------------------------------------
  // Self-contained on purpose: defined directly here rather than pulled
  // from AppColors, so this page's dark redesign can't accidentally
  // affect any other screen that also reads AppColors.

  static const _bg = Color(0xFF0D1117); // page background
  static const _surface = Color(0xFF161B22); // card / surface background
  static const _surfaceAlt = Color(0xFF1E242C); // inputs, chips, inner panels
  static const _ink = Color(0xFFF1F3F6); // primary text (light, on dark)
  static const _inkMuted = Color(0xFFA3ADBA); // secondary/muted text
  static const _inkFaint = Color(0xFF6E7885); // tertiary text, disabled icons
  static const _border = Color(0xFF262D38); // dividers / hairline borders

  static const _brandA = Color(0xFF3B82F6);
  static const _brandB = Color(0xFF60A5FA);

  static const _accentTeal = Color(0xFF2DD4BF);
  static const _accentOrange = Color(0xFFFBBF24);
  static const _accentPurple = Color(0xFFA78BFA);

  @override
  void initState() {
    super.initState();

    _httpClient = HttpClient()
      ..connectionTimeout = Duration(seconds: 8)
      ..idleTimeout = Duration(seconds: 10);

    _tabController = TabController(
      length: 2,
      vsync: this,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1400),
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
        await Future.delayed(Duration(milliseconds: 100));

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
        throw FormatException(
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
        Duration(seconds: 1),
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

  /// Relevance-ranked app search -- not just "contains()". Name matches
  /// rank above package-name matches, and within each, an exact or
  /// prefix match ranks above a plain substring match, so typing
  /// "chrome" surfaces Chrome itself before something merely mentioning
  /// it in its package id.
  List<AppInfo> _searchApps(List<AppInfo> apps, String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      return apps;
    }

    final scored = <MapEntry<AppInfo, int>>[];

    for (final app in apps) {
      final name = app.appName.toLowerCase();
      final pkg = app.packageName.toLowerCase();

      int? score;

      if (name == q) {
        score = 100;
      } else if (name.startsWith(q)) {
        score = 90;
      } else if (name.contains(' $q') || name.contains('_$q')) {
        // Matches the start of a later word, e.g. "lite" in "Facebook Lite".
        score = 80;
      } else if (name.contains(q)) {
        score = 70;
      } else if (pkg.startsWith(q) || pkg.contains('.$q')) {
        score = 50;
      } else if (pkg.contains(q)) {
        score = 40;
      }

      if (score != null) {
        scored.add(MapEntry(app, score));
      }
    }

    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return a.key.appName.toLowerCase().compareTo(b.key.appName.toLowerCase());
    });

    return scored.map((e) => e.key).toList();
  }

  /// Renders [text] with the portion matching [query] highlighted in
  /// the brand color, so it's visually obvious *why* a result matched.
  Widget _highlightedText(
    String text,
    String query, {
    required TextStyle style,
    TextStyle? highlightStyle,
  }) {
    final q = query.trim();

    if (q.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = q.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);

    if (matchIndex < 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final matchEnd = matchIndex + q.length;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchEnd),
            style: highlightStyle ??
                style.copyWith(
                  color: _brandB,
                  fontWeight: FontWeight.w800,
                  backgroundColor: _brandA.withOpacity(.22),
                ),
          ),
          TextSpan(text: text.substring(matchEnd)),
        ],
      ),
    );
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
            final filtered = _searchApps(_installedApps, search);

            final allFilteredSelected = filtered.isNotEmpty &&
                filtered.every(
                  (app) => temp.contains(app.packageName),
                );

            return PopScope(
              canPop: false,
              onPopInvoked: (didPop) {
                if (didPop) return;
                // Back button (or any other way the sheet gets popped)
                // now behaves like DONE -- commits whatever was
                // selected in this session instead of silently
                // discarding it back to the previous selection.
                Navigator.pop(ctx, temp);
              },
              child: DraggableScrollableSheet(
                initialChildSize: .85,
                minChildSize: .45,
                maxChildSize: .96,
                expand: false,
                builder: (_, controller) {
                  return Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: 10),
                        _sheetHandle(),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
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
                                    Text(
                                      'Select apps',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: _ink,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      '${temp.length} of ${_installedApps.length} selected',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: _inkMuted,
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
                          padding: EdgeInsets.fromLTRB(
                            20,
                            12,
                            20,
                            0,
                          ),
                          child: TextField(
                            style: TextStyle(color: _ink),
                            onChanged: (value) {
                              setSheetState(() {
                                search = value;
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Search installed apps',
                              hintStyle: TextStyle(
                                color: _inkFaint,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: _inkFaint,
                              ),
                              suffixIcon: search.isNotEmpty
                                  ? IconButton(
                                      onPressed: () {
                                        setSheetState(() {
                                          search = '';
                                        });
                                      },
                                      icon: Icon(
                                        Icons.clear_rounded,
                                        color: _inkFaint,
                                      ),
                                    )
                                  : null,
                              filled: true,
                              fillColor: _surfaceAlt,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        if (search.trim().isNotEmpty)
                          Padding(
                            padding: EdgeInsets.fromLTRB(24, 6, 20, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                filtered.isEmpty
                                    ? 'No matches for "${search.trim()}"'
                                    : '${filtered.length} match${filtered.length == 1 ? '' : 'es'}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: _inkMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        SizedBox(height: 10),
                        Expanded(
                          child: _loadingApps
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: _brandA,
                                  ),
                                )
                              : filtered.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No apps found',
                                        style: TextStyle(
                                          color: _inkMuted,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      controller: controller,
                                      padding: EdgeInsets.fromLTRB(
                                        12,
                                        6,
                                        12,
                                        24,
                                      ),
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) =>
                                          SizedBox(height: 4),
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
                                          query: search,
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
                            padding: EdgeInsets.fromLTRB(
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
              ),
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
    String query = '',
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(!checked),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: checked ? _brandA.withOpacity(.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _appIcon(app, size: 42),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightedText(
                    app.appName,
                    query,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _inkFaint,
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
      duration: Duration(milliseconds: 180),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: checked
            ? LinearGradient(
                colors: [_brandA, _brandB],
              )
            : null,
        color: checked ? null : _surfaceAlt,
        border: Border.all(
          color: checked ? Colors.transparent : _border,
          width: 1.6,
        ),
      ),
      child: checked
          ? Icon(
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
        color: _border,
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
          content: Text(
            message,
            style: TextStyle(color: _ink),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.all(14),
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

    return _inkMuted;
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
                  _surfaceAlt,
                  _surfaceAlt,
                ],
              )
            : LinearGradient(
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
                  offset: Offset(0, 8),
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
                  SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: disabled ? _inkFaint : Colors.white,
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
      color: filled ? _brandA.withOpacity(.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: _brandB,
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
        preferredSize: Size.fromHeight(150),
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
      decoration: BoxDecoration(
        // gradient: LinearGradient(
        //   begin: Alignment.topLeft,
        //   end: Alignment.bottomRight,
        //   colors: [_brandA, _brandB],
        // ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.28),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
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
                      child: Icon(
                        Icons.podcasts_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    SizedBox(width: 9),
                    Expanded(
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
                    SizedBox(width: 2),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      padding: EdgeInsets.zero,
                      color: _surfaceAlt,
                      icon: Icon(
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
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'csv',
                          child: Row(
                            children: [
                              Icon(
                                Icons.table_chart_outlined,
                                size: 19,
                                color: _ink,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Export CSV',
                                style: TextStyle(color: _ink),
                              ),
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
                                color: _ink,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Export TXT',
                                style: TextStyle(color: _ink),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'pip',
                          child: Row(
                            children: [
                              Icon(
                                Icons.picture_in_picture_alt_outlined,
                                size: 19,
                                color: _ink,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Floating overlay (PIP)',
                                style: TextStyle(color: _ink),
                              ),
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
                                color: _ink,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Clear traffic',
                                style: TextStyle(color: _ink),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 7),
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
          padding: EdgeInsets.symmetric(
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
                          Color(0xFF00E5A0),
                          Colors.white,
                          pulse * .5,
                        )
                      : Colors.white54,
                ),
              ),
              SizedBox(width: 6),
              Text(
                _running ? 'LIVE' : 'IDLE',
                style: TextStyle(
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
      padding: EdgeInsets.all(4),
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
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        tabs: [
          Tab(
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
      padding: EdgeInsets.all(16),
      children: [
        _controlCard(),
        SizedBox(height: 12),
        _quickStatsRow(),
        if (!_running) ...[
          SizedBox(height: 12),
          _tipCard(),
        ],
      ],
    );
  }

  Widget _controlCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_brandA, _brandB],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.radar_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Network Monitor',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      _running
                          ? 'Monitoring • ${_formatDuration(_elapsed)}'
                          : 'Select apps to monitor',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _ringIndicator(),
            ],
          ),
          SizedBox(height: 14),
          InkWell(
            onTap: _running || _loadingApps ? null : _openAppSelector,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 48,
              padding: EdgeInsets.symmetric(
                horizontal: 14,
              ),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.apps_rounded,
                    size: 19,
                    color: _running ? _inkFaint : _brandB,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedPackages.isEmpty
                          ? 'Select apps'
                          : '${_selectedPackages.length} app(s) selected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _running ? _inkFaint : _ink,
                      ),
                    ),
                  ),
                  if (!_running)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _inkFaint,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 14),
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
                  ? SizedBox(
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
            SizedBox(height: 24),
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
              color:
                  _running ? Color(0xFF00E5A0).withOpacity(.16) : _surfaceAlt,
              border: Border.all(
                color: _running ? Color(0xFF00E5A0) : _border,
                width: 2,
              ),
            ),
            child: Icon(
              _running ? Icons.bolt_rounded : Icons.bolt_outlined,
              color: _running ? Color(0xFF00E5A0) : _inkFaint,
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
            color: _brandB,
          ),
        ),
        SizedBox(width: 10),
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
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: color,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: _inkMuted,
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
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _brandA.withOpacity(.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _brandA.withOpacity(.24),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            color: _brandB,
            size: 19,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              _selectedPackages.isEmpty
                  ? 'Select an app and press START to monitor traffic.'
                  : 'Press START and open the selected app to see traffic.',
              style: TextStyle(
                fontSize: 11.5,
                color: _inkMuted,
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
          padding: EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _brandA.withOpacity(.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 12,
              color: _brandB,
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
        SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
    );
  }

  Widget _compactStats() {
    return Container(
      margin: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        6,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          _compactStat(
            Icons.swap_vert_rounded,
            _flows.length.toString(),
            _brandB,
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
          SizedBox(width: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
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
      color: _border,
    );
  }

  Widget _compactToolbar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
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
                    color: _surface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _border),
                  ),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    style: TextStyle(
                      fontSize: 13,
                      color: _ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search IP, country, ISP or port',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: _inkFaint,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: _inkFaint,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: Icon(
                                Icons.clear_rounded,
                                size: 17,
                                color: _inkFaint,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 7),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _border),
                ),
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: 'Sort',
                  color: _surfaceAlt,
                  onSelected: (value) {
                    setState(() {
                      _sortMode = value;
                    });
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  icon: Icon(
                    Icons.swap_vert_rounded,
                    size: 20,
                    color: _brandB,
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
          SizedBox(height: 7),
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
              SizedBox(width: 5),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear',
                onPressed: _flows.isEmpty ? null : _clearFlows,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: _inkMuted,
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'Export',
                color: _surfaceAlt,
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
                  color: _inkMuted,
                ),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'csv',
                    child: Text(
                      'Export CSV',
                      style: TextStyle(color: _ink),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'txt',
                    child: Text(
                      'Export TXT',
                      style: TextStyle(color: _ink),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Live traffic · ${_visibleFlows.length}',
              style: TextStyle(
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
      padding: EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _protocolFilter = value;
          });
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [_brandA, _brandB],
                  )
                : null,
            color: selected ? null : _surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Colors.transparent : _border,
            ),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? Colors.white : _inkMuted,
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
        margin: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 3,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _border),
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
                      color: protocolColor.withOpacity(.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.apps_rounded,
                      color: protocolColor,
                      size: 19,
                    ),
                  ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app?.appName ?? 'Unknown app',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: protocolColor.withOpacity(.14),
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
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${flow.destinationIp}:${flow.destinationPort}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  if (isLoading)
                    Row(
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: _brandB,
                          ),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Looking up IP...',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: _inkFaint,
                          ),
                        ),
                      ],
                    )
                  else if (ipInfo != null)
                    Row(
                      children: [
                        Icon(
                          Icons.public_rounded,
                          size: 12,
                          color: _brandB,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _ipLocationText(
                              ipInfo,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.8,
                              color: _inkMuted,
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
                        color: _inkFaint,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppUsage.humanBytes(
                    flow.bytes,
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'IPv${flow.ipVersion}',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: _inkFaint,
                  ),
                ),
              ],
            ),
            SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: _inkFaint,
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
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
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
                          margin: EdgeInsets.only(
                            bottom: 20,
                          ),
                          decoration: BoxDecoration(
                            color: _border,
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
                                      .16,
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
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app?.appName ?? 'Unknown app',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                if (app?.packageName != null) ...[
                                  SizedBox(
                                    height: 3,
                                  ),
                                  Text(
                                    app!.packageName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _inkMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: protocolColor.withOpacity(.16),
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
                      SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          vertical: 17,
                          horizontal: 17,
                        ),
                        decoration: BoxDecoration(
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
                            Icon(
                              Icons.data_usage_rounded,
                              color: Colors.white,
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Text(
                              'Data transferred',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Spacer(),
                            Text(
                              AppUsage.humanBytes(
                                flow.bytes,
                              ),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 22),
                      Text(
                        'Connection',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 10),
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
                      SizedBox(height: 22),
                      Row(
                        children: [
                          Icon(
                            Icons.public_rounded,
                            color: _brandB,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
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
                            SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _brandB,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 10),
                      if (loading && info == null)
                        Container(
                          padding: EdgeInsets.all(
                            18,
                          ),
                          decoration: BoxDecoration(
                            color: _surfaceAlt,
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _brandB,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Fetching IP information...',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (info != null)
                        _ipInfoCard(info)
                      else
                        Container(
                          padding: EdgeInsets.all(
                            18,
                          ),
                          decoration: BoxDecoration(
                            color: _surfaceAlt,
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: _inkMuted,
                              ),
                              SizedBox(
                                width: 10,
                              ),
                              Expanded(
                                child: Text(
                                  'Could not load IP information.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _ink,
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
                                child: Text(
                                  'Retry',
                                  style: TextStyle(color: _brandB),
                                ),
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
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceAlt,
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
      padding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: _border,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: _brandB,
            ),
          ),
          SizedBox(width: 10),
          SizedBox(
            width: 95,
            child: Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  color: _inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
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
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 18,
              color: _brandB,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
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
                color: _inkMuted,
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
      .62,
    ).toColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(.20),
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
            color: _brandB,
          ),
          SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(color: _ink),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(30),
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
                          _brandA.withOpacity(.22),
                          _brandB.withOpacity(.22),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _running ? Icons.radar_rounded : Icons.radar_outlined,
                      size: 44,
                      color: _brandB,
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 20),
            Text(
              'No traffic yet',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _selectedPackages.isEmpty
                  ? 'Go to the Setup tab, select a test app and press START.'
                  : _running
                      ? 'Open the selected app and generate some network traffic.'
                      : 'Go to the Setup tab and press START to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _inkMuted,
                height: 1.4,
              ),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: 180,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => _tabController.animateTo(0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brandB,
                  side: BorderSide(
                    color: _brandB,
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      14,
                    ),
                  ),
                ),
                icon: Icon(
                  Icons.tune_rounded,
                  size: 18,
                ),
                label: Text(
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

  IpInfo({
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
  _TabLabel({
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
        SizedBox(width: 6),
        Text(label),
        if (badgeCount != null && badgeCount! > 0) ...[
          SizedBox(width: 6),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badgeCount! > 99 ? '99+' : '$badgeCount',
              style: TextStyle(
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
