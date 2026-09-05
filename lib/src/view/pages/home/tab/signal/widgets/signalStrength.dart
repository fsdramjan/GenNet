// ignore_for_file: deprecated_member_use, duplicate_ignore

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:dart_ping/dart_ping.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/sizedBox.dart';
import 'dart:async';
import 'dart:math';

import 'package:apptrack/src/view/widgets/text/kText.dart';

enum GraphDataType {
  signal,
  throughput,
  latency,
}

class SignalStrengthTab extends StatefulWidget {
  @override
  _SignalStrengthTabState createState() => _SignalStrengthTabState();
}

class _SignalStrengthTabState extends State<SignalStrengthTab>
    with SingleTickerProviderStateMixin {
  //first tab signal strength and Floor Plan
  // int _firstSelectedTabIndex = 0; // 0: Signal Strength, 1: Floor Plan

  // Second tab for WiFi/Cellular

  int _secondSelectedTabIndex = 0; // 0: WiFi, 1: Cellular

  //third tab for Graphs [Signal, Throughput, Latency]
  // int _thirdSelectedTabIndex = 0; // 0: Signal, 1: Throughput, 2: Latency

  late TabController _tabController; // For WiFi/Cellular tabs
  int _selectedGraphButtonIndex = 0; // 0: Signal, 1: Throughput, 2: Latency
  GraphDataType _currentGraphType =
      GraphDataType.signal; // Current active graph data type

  // Data lists for each graph type
  List<FlSpot> _signalData = [];
  List<FlSpot> _throughputData = [];
  List<FlSpot> _latencyGraphData = [];

  // Current values to display above the graph
  String _currentSignalDbm = '... dBm';
  String _currentPhySpeedUp = '...';
  String _currentPhySpeedDown = '...';

  // Timer for continuous data fetching
  Timer? _graphDataTimer;

  // For dummy throughput data generation
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startGraphDataMonitoring(); // Start monitoring the initial graph type
  }

  @override
  void dispose() {
    _tabController.dispose();
    _graphDataTimer?.cancel();
    super.dispose();
  }

  // --- Data Fetching Logic ---
  void _startGraphDataMonitoring() {
    // Clear existing timer if any
    _graphDataTimer?.cancel();

    // Set initial data based on current graph type
    _fetchCurrentGraphData();

    // Start periodic timer for continuous updates
    _graphDataTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _fetchCurrentGraphData();
    });
  }

  void _fetchCurrentGraphData() {
    switch (_currentGraphType) {
      case GraphDataType.signal:
        _fetchSignalStrength();
        break;
      case GraphDataType.throughput:
        _fetchThroughput();
        break;
      case GraphDataType.latency:
        _fetchLatencyGraphData();
        break;
    }
  }

  static const platform = MethodChannel('wifi.info.channel');
  Future<void> _fetchSignalStrength() async {
    try {
      final Map<dynamic, dynamic> result =
          await platform.invokeMethod('getWifiSignalInfo');

      final int signalStrength = result['signalStrength'];
      final int linkSpeed = result['linkSpeed'];

      if (!mounted) return;
      setState(() {
        // Update current values
        _currentSignalDbm = '$signalStrength dBm';
        _currentPhySpeedUp = '${(linkSpeed * 0.6).toInt()} Mbps';
        _currentPhySpeedDown = '${(linkSpeed * 0.4).toInt()} Mbps';

        // Update graph data list
        _signalData.add(
            FlSpot(_signalData.length.toDouble(), signalStrength.toDouble()));

        // Keep max 60 points in graph
        if (_signalData.length > 20) {
          _signalData.removeAt(0);
          for (int i = 0; i < _signalData.length; i++) {
            _signalData[i] = FlSpot(i.toDouble(), _signalData[i].y);
          }
        }

        // Dummy throughput and latency data updates
        _throughputData.add(FlSpot(
            _throughputData.length.toDouble(), _random.nextDouble() * 100));
        if (_throughputData.length > 60) {
          _throughputData.removeAt(0);
          for (int i = 0; i < _throughputData.length; i++) {
            _throughputData[i] = FlSpot(i.toDouble(), _throughputData[i].y);
          }
        }

        _latencyGraphData.add(FlSpot(
            _latencyGraphData.length.toDouble(), _random.nextDouble() * 50));
        if (_latencyGraphData.length > 60) {
          _latencyGraphData.removeAt(0);
          for (int i = 0; i < _latencyGraphData.length; i++) {
            _latencyGraphData[i] = FlSpot(i.toDouble(), _latencyGraphData[i].y);
          }
        }
      });
    } catch (e) {
      print("Failed to get WiFi signal info: $e");
      if (!mounted) return;
      setState(() {
        _currentSignalDbm = 'Error';
        _currentPhySpeedUp = 'Error';
        _currentPhySpeedDown = 'Error';
      });
    }
  }

  // Dummy Throughput fetching for demonstration
  Future<void> _fetchThroughput() async {
    if (mounted) {
      setState(() {
        // Simulate fluctuating throughput values (e.g., 0 to 100 Mbps)
        double simulatedThroughput = _random.nextDouble() * 100; // Mbps
        _throughputData.add(
            FlSpot(_throughputData.length.toDouble(), simulatedThroughput));

        if (_throughputData.length > 60) {
          _throughputData.removeAt(0);
          for (int i = 0; i < _throughputData.length; i++) {
            _throughputData[i] = FlSpot(i.toDouble(), _throughputData[i].y);
          }
        }
        // Update current display (you might want to average or show last)
        _currentPhySpeedUp = simulatedThroughput.toInt().toString();
        _currentPhySpeedDown = (_random.nextDouble() * 50)
            .toInt()
            .toString(); // Dummy download for throughput
      });
    }
  }

  Future<void> _fetchLatencyGraphData() async {
    try {
      final ping = Ping('google.com', count: 1, timeout: 2);
      await for (var pingData in ping.stream) {
        if (pingData.response != null && pingData.response!.time != null) {
          if (mounted) {
            setState(() {
              double latencyMs =
                  pingData.response!.time!.inMilliseconds.toDouble();
              _latencyGraphData
                  .add(FlSpot(_latencyGraphData.length.toDouble(), latencyMs));

              if (_latencyGraphData.length > 60) {
                _latencyGraphData.removeAt(0);
                for (int i = 0; i < _latencyGraphData.length; i++) {
                  _latencyGraphData[i] =
                      FlSpot(i.toDouble(), _latencyGraphData[i].y);
                }
              }
              // Update current signal display with latest latency
              _currentSignalDbm =
                  '${latencyMs.toInt()} ms'; // Re-purpose for latency display
              _currentPhySpeedUp = '...'; // Reset for latency context
              _currentPhySpeedDown = '...';
            });
          }
          return; // Get one ping result and then wait for next timer tick
        } else if (pingData.error != null) {
          print('Ping error for latency graph: ${pingData.error?.error}');
          if (mounted) {
            setState(() {
              _currentSignalDbm = 'Error';
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _currentSignalDbm = 'Timed out';
        });
      }
    } catch (e) {
      print('Exception pinging for latency graph: $e');
      if (mounted) {
        setState(() {
          _currentSignalDbm = 'Error';
        });
      }
    }
  }

  // --- UI Building Methods (Mostly unchanged, but use dynamic data) ---
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNetworkTypeTabs(),
        SizedBox(height: 16),
        _buildNetworkDetailsRow(),
        SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardGrey,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              _buildSignalStrengthGraph(),
              SizedBox(height: 20),
              _buildGraphDetailButtons(),
              SizedBox(height: 20),
              _buildAccessPointDetails(),
              SizedBox(height: 20),
            ],
          ),
        ),
        SizedBox(height: 20),
        _buildAccessPointRoaming(),
      ],
    );
  }

  Widget _buildNetworkDetailsRow() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KText(
                text: 'Band',
                color: AppColors.white70,
                fontSize: 12,
              ),
              SizedBox(height: 4),
              KText(
                text: '2.4 GHz (40 MHz)',
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Label changes based on active graph type
              KText(
                text: _currentGraphType == GraphDataType.latency
                    ? 'Latency'
                    : 'Signal',
                color: AppColors.white70,
                fontSize: 12,
              ),
              SizedBox(height: 4),
              KText(
                text: _currentSignalDbm,
                color: AppColors.green,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KText(
                text: _currentGraphType == GraphDataType.throughput
                    ? 'Throughput (Mbps)'
                    : 'PHY Speed (Mbps)',
                color: AppColors.white70,
                fontSize: 12,
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  if (_currentGraphType !=
                      GraphDataType.latency) // Don't show for latency
                    Icon(
                      Icons.arrow_upward,
                      color: Colors.greenAccent,
                      size: 14,
                    ),
                  KText(
                    text: _currentPhySpeedUp,
                    color: Colors.greenAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  if (_currentGraphType !=
                      GraphDataType.latency) // Don't show for latency
                    Icon(
                      Icons.arrow_downward,
                      color: Colors.orange,
                      size: 14,
                    ),
                  KText(
                    text: _currentPhySpeedDown,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalStrengthGraph() {
    // Determine which data to show
    List<FlSpot> dataToShow;
    double minY, maxY;
    String Function(double)? getTitlesWidget; // Y-axis label formatter

    switch (_currentGraphType) {
      case GraphDataType.signal:
        dataToShow = _signalData;
        minY = -100; // Typical range for dBm
        maxY = -20;
        getTitlesWidget = (value) => '${value.toInt()}';
        break;
      case GraphDataType.throughput:
        dataToShow = _throughputData;
        minY = 0; // Mbps
        maxY = 120;
        getTitlesWidget = (value) => '${value.toInt()}';
        break;
      case GraphDataType.latency:
        dataToShow = _latencyGraphData;
        minY = 0; // ms
        maxY = 500; // Max latency to show on graph
        getTitlesWidget = (value) => '${value.toInt()}';
        break;
    }

    // fl_chart lazily computes mostLeftSpot/mostRightSpot from the first
    // entry in `spots` the moment it paints. If the list is empty (e.g. on
    // first build, before any data has come in, or right after switching
    // graph type and clearing the lists), that lazy getter throws a
    // LateInitializationError. Always give it at least one point.
    final List<FlSpot> chartSpots =
        dataToShow.isNotEmpty ? dataToShow : const [FlSpot(0, 0)];

    return Container(
      height: 200,
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // decoration: BoxDecoration(
      //   // color: Colors.grey[900],
      //   borderRadius: BorderRadius.circular(10),
      // ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.white10, strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
                FlLine(color: Colors.white10, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                // ignore: unnecessary_null_comparison
                getTitlesWidget: getTitlesWidget != null
                    ? (value, meta) =>
                        KText(text: getTitlesWidget!(value).toString())
                    : (value, meta) => Text(''),
                interval: (maxY - minY) / 5, // 5 intervals for Y-axis
                reservedSize: 30,
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.white24, width: 1),
          ),
          minX: 0,
          maxX: (dataToShow.isNotEmpty
              ? dataToShow.length.toDouble() - 1
              : 0), // X-axis dynamically adapts to data points
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: chartSpots,
              isCurved: true,
              color: Colors.blueAccent,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Colors.white,
                    strokeWidth: 1,
                    strokeColor: Colors.blueAccent,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    // ignore: deprecated_member_use
                    Colors.blueAccent.withOpacity(0.3),
                    Colors.blueAccent.withOpacity(0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            // Direct use of LineTouchData
            touchCallback:
                (FlTouchEvent event, LineTouchResponse? touchResponse) {
              // Handle touch events on the graph if needed
            },
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              // tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  return LineTooltipItem(
                    '${barSpot.y.toInt()} ${_currentGraphType == GraphDataType.signal ? 'dBm' : _currentGraphType == GraphDataType.latency ? 'ms' : 'Mbps'}',
                    const TextStyle(color: Colors.white),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  // Widget _buildGraphDetailButtons() {
  //   return Container(
  //     decoration: BoxDecoration(
  //       color: AppColors.cardGrey,
  //       borderRadius: BorderRadius.circular(8),
  //     ),
  //     child: Padding(
  //       padding: EdgeInsets.all(5),
  //       child: Row(
  //         children: [
  //           Expanded(
  //             child: Container(
  //               height: 70,
  //               width: Get.width,
  //               padding: EdgeInsets.symmetric(vertical: 12),
  //               decoration: _firstSelectedTabIndex == 0
  //                   ? BoxDecoration(
  //                       color: AppColors.backgroundColor,
  //                       borderRadius: BorderRadius.circular(8),
  //                     )
  //                   : null,
  //               child: InkWell(
  //                 onTap: () {
  //                   setState(() {
  //                     _firstSelectedTabIndex = 0; // Signal Strength
  //                   });
  //                 },
  //                 child: Column(
  //                   mainAxisAlignment: MainAxisAlignment.center,
  //                   children: [
  //                     // Icon(
  //                     //   Icons.stacked_bar_chart_sharp,
  //                     //   color: _firstSelectedTabIndex == 0
  //                     //       ? AppColors.lightBlue
  //                     //       : AppColors.white54,
  //                     //   size: 20,
  //                     // ),
  //                     Image.asset(
  //                       'assets/icons/signal_strength.png',
  //                       color: _firstSelectedTabIndex == 0
  //                           ? AppColors.lightBlue
  //                           : AppColors.white54,
  //                       height: 25,
  //                     ),
  //                     SizedBox(width: 8),
  //                     KText(
  //                       text: 'Signal Strength',
  //                       color: _firstSelectedTabIndex == 0
  //                           ? AppColors.lightBlue
  //                           : AppColors.white54,
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           ),
  //           Expanded(
  //             child: Container(
  //               height: 70,
  //               width: Get.width,
  //               padding: EdgeInsets.symmetric(vertical: 12),
  //               decoration: _firstSelectedTabIndex == 1
  //                   ? BoxDecoration(
  //                       color: AppColors.backgroundColor,
  //                       borderRadius: BorderRadius.circular(8),
  //                     )
  //                   : null,
  //               child: InkWell(
  //                 onTap: () {
  //                   setState(() {
  //                     _firstSelectedTabIndex = 1; // Floor Plan
  //                   });
  //                 },
  //                 child: Column(
  //                   mainAxisAlignment: MainAxisAlignment.center,
  //                   children: [
  //                     Image.asset(
  //                       'assets/icons/stacks_icon.png',
  //                       color: _firstSelectedTabIndex == 1
  //                           ? AppColors.lightBlue
  //                           : AppColors.white54,
  //                       height: 25,
  //                     ),
  //                     // Icon(
  //                     //   Icons.stacked_bar_chart_sharp,
  //                     // color: _firstSelectedTabIndex == 1
  //                     //     ? AppColors.lightBlue
  //                     //     : AppColors.white54,
  //                     // size: 20,
  //                     // ),
  //                     SizedBox(width: 8),
  //                     KText(
  //                       text: 'Floor Plan',
  //                       color: _firstSelectedTabIndex == 1
  //                           ? AppColors.lightBlue
  //                           : AppColors.white54,
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildGraphDetailButtons() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        // height: 50,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: EdgeInsets.all(5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: _buildDetailButton(
                'Signal',
                0,
                GraphDataType.signal,
              ),
            ),
            Expanded(
              child: _buildDetailButton(
                'Throughput',
                1,
                GraphDataType.throughput,
              ),
            ),
            Expanded(
              child: _buildDetailButton(
                'Latency',
                2,
                GraphDataType.latency,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailButton(String text, int index, GraphDataType type) {
    bool isSelected = _selectedGraphButtonIndex == index;
    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() {
            _selectedGraphButtonIndex = index;
            _currentGraphType = type;
            // When graph type changes, reset data and restart monitoring for new data
            _signalData.clear();
            _throughputData.clear();
            _latencyGraphData.clear();
            _startGraphDataMonitoring(); // Re-start the timer for the new graph type
          });
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.backgroundColor : Colors.transparent,
          borderRadius: BorderRadius.circular(
            10,
          ),
        ),
        alignment: Alignment.center,
        child: KText(
          text: text,
          color: isSelected ? AppColors.lightBlue : Colors.white54,
        ),
      ),
    );
  }

  Widget _buildNetworkTypeTabs() {
    return Padding(
      padding: EdgeInsets.all(5),
      child: Row(
        children: [
          Container(
            // height: 35,
            width: 90,

            padding: EdgeInsets.symmetric(vertical: 3, horizontal: 20),
            decoration: _secondSelectedTabIndex == 0
                ? BoxDecoration(
                    color: AppColors.lightBlue,
                    borderRadius: BorderRadius.circular(15),
                  )
                : null,
            alignment: Alignment.center,

            child: InkWell(
              onTap: () {
                setState(() {
                  _secondSelectedTabIndex = 0; // Signal Strength
                });
              },
              child: KText(text: 'WiFi', fontSize: 12, color: AppColors.white),
            ),
          ),
          wSizedBox(10),
          Container(
            // height: 35,
            width: 90,
            padding: EdgeInsets.symmetric(vertical: 3, horizontal: 20),
            decoration: _secondSelectedTabIndex == 1
                ? BoxDecoration(
                    color: AppColors.lightBlue,
                    borderRadius: BorderRadius.circular(15),
                  )
                : null,
            alignment: Alignment.center,
            child: InkWell(
              onTap: () {
                setState(() {
                  _secondSelectedTabIndex = 1; // Signal Strength
                });
              },
              child: KText(
                text: 'Cellular',
                fontSize: 12,
                color: AppColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessPointDetails() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.router_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  KText(
                    text: 'Access Point',
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ],
              ),
              KText(
                text: '14:EB:B6:51:98:F8', // MAC Address - placeholder
                color: AppColors.white70, fontSize: 12,
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.lightBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
                  KText(
                    text: '2.4 GHz',
                    color: AppColors.white,
                    fontSize: 12,
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.green,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: KText(
                      text: 'CONNECTED',
                      color: AppColors.greenAccent,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
              KText(
                text: _currentSignalDbm,
                color: AppColors.greenAccent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccessPointRoaming() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KText(
          text: 'Access Point Roaming',
          color: AppColors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        hSizedBox(5),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: KText(
                  text: 'No access point changes recorded yet',
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
