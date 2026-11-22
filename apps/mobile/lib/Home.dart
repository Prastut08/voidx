 import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter_config/flutter_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/cupertino.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:http/http.dart' as http;
import 'sos_chat_panel.dart';

String _safeBackendUrl() {
  try {
    final val = FlutterConfig.get('BACKEND_URL');
    if (val != null && val.toString().isNotEmpty) return val.toString();
  } catch (_) {}
  final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
  return 'http://$host:8080';
}

class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class SOSButton extends StatelessWidget {
  final bool isHelping;
  final double currentLat;
  final double currentLng;

  SOSButton({
    required this.isHelping,
    this.currentLat = 12.9806,
    this.currentLng = 80.2132,
  });

  @override
  Widget build(BuildContext context) {
    return (!isHelping)
        ? Positioned(
            bottom: 175.0,
            right: 16.0,
            child: FloatingActionButton(
              onPressed: () => _onSOSPressed(context),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'SOS',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              backgroundColor: const Color.fromARGB(255, 250, 121, 121),
            ),
          )
        : SizedBox();
  }

  void _onSOSPressed(BuildContext context) {
    try {
      js.context.callMethod('setFlutterInteractive', [true]);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return SOSChatPanel(
          currentLat: currentLat,
          currentLng: currentLng,
          backendUrl: _safeBackendUrl(),
          onClose: () => Navigator.of(bc).pop(),
        );
      },
    );
  }

  void _sendSOS(BuildContext context) async {
    final String message = 'SOS! I need help with the climate crisis!';
    final String uri = 'sms:?body=${Uri.encodeQueryComponent(message)}';

    if (await canLaunch(uri)) {
      await launch(uri);
    } else {
      print('Could not launch $uri');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: Could not launch messaging app')),
      );
    }
  }
}

class _HomeState extends State<Home> {
  double currentLat = 20.5937;
  double currentLng = 78.9629;
  bool locationLoaded = false;
  bool isHelping = false;
  bool isOffline = false;

  List<Map<String, dynamic>> _needItems = [];
  List<Map<String, dynamic>> _giveItems = [];

  Future<void> _checkConnectivity() async {
    final isConnected = await InternetConnectionChecker().hasConnection;
    setState(() {
      isOffline = !isConnected;
    });
  }

  List<Map<String, dynamic>> filtersNeedHelp = [
    {"type": "Pharmacy", "icon": Icons.local_pharmacy},
    {"type": "Grocery & Food", "icon": Icons.shopping_basket},
    {"type": "Supplies", "icon": Icons.inventory_2},
    {"type": "Hospital", "icon": Icons.local_hospital},
    {"type": "Relief Camp", "icon": Icons.holiday_village},
    {"type": "Shelter", "icon": Icons.home},
    {"type": "Volunteer", "icon": Icons.volunteer_activism},
  ];

  String _activeGroqHeading = '';
  bool _isLoadingGroqShops = false;
  List<Map<String, dynamic>> _groqShops = [];

  List<Map<String, dynamic>> filtersGiveHelp = [
    {"type": "Victim", "icon": Icons.medical_services},
    {"type": "Volunteer", "icon": Icons.volunteer_activism},
    {"type": "Donate", "icon": Icons.card_giftcard},
    {"type": "Shelter", "icon": Icons.home},
    {"type": "Food", "icon": Icons.restaurant},
  ];

  bool _isSpeedDialOpen = false;
  String selectedFilter = '';

  @override
  void initState() {
    super.initState();
    _registerJsCallbacks();
    _getCurrentLocation();
    _loadModePreference();
    _loadJsonData();
    Timer.periodic(Duration(seconds: 5), (timer) {
      _checkConnectivity();
    });
  }

  void _registerJsCallbacks() {
    try {
      js.context['flutterOpenDrawer'] = () {
        _showAssistanceDrawer();
      };
      js.context['flutterSOS'] = () {
        if (!isHelping) {
          SOSButton(isHelping: isHelping)._onSOSPressed(context);
        }
      };
      js.context['flutterRecenter'] = () {
        js.context.callMethod('updateWindyLocation', [currentLat, currentLng]);
      };
      js.context['flutterAction'] = () {
        actionButtonClickFn();
      };
      js.context.callMethod('setFlutterInteractive', [false]);
    } catch (e) {
      debugPrint('Error registering JS callbacks: $e');
    }
  }

  void _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      var position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        currentLat = position.latitude;
        currentLng = position.longitude;
        locationLoaded = true;
      });
      js.context.callMethod('updateWindyLocation', [currentLat, currentLng]);
      _loadJsonData();
    } catch (e) {
      debugPrint('Location error, attempting IP fallback: $e');
      try {
        final ipRes = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 4));
        if (ipRes.statusCode == 200) {
          final d = json.decode(ipRes.body);
          if (d['latitude'] != null && d['longitude'] != null) {
            setState(() {
              currentLat = (d['latitude'] as num).toDouble();
              currentLng = (d['longitude'] as num).toDouble();
              locationLoaded = true;
            });
            js.context.callMethod('updateWindyLocation', [currentLat, currentLng]);
          }
        }
      } catch (_) {}
      setState(() { locationLoaded = true; });
    }
  }

  Future<void> _fetchGroqShops(String heading, [StateSetter? setModalState]) async {
    setState(() {
      _activeGroqHeading = heading;
      _isLoadingGroqShops = true;
    });
    if (setModalState != null) setModalState(() {});

    try {
      final uri = Uri.parse('${_safeBackendUrl()}/api/v1/nearby-shops').replace(
        queryParameters: {
          'lat': currentLat.toString(),
          'lng': currentLng.toString(),
          'category': heading,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 18));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = List<Map<String, dynamic>>.from(data['shops'] ?? []);
        setState(() {
          _groqShops = list;
          _isLoadingGroqShops = false;
        });
      } else {
        setState(() {
          _isLoadingGroqShops = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching Groq shops: $e');
      setState(() {
        _isLoadingGroqShops = false;
      });
    }

    if (setModalState != null) setModalState(() {});
  }

  Future<void> _loadJsonData() async {
    final url = Uri.parse('${_safeBackendUrl()}/api/v1/?lat=$currentLat&lng=$currentLng');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonResponse = json
            .decode(response.body.replaceAll('\n', '').replaceAll('  ', ''));
        print(jsonResponse);
        _processJsonData(jsonResponse);
      } else {
        print(
            'Failed to load data from the internet. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print("Error fetching data: $e");
    }
  }

  void _processJsonData(Map<String, dynamic> data) {
    setState(() {
      _needItems = List<Map<String, dynamic>>.from(data['need'] ?? []);
      _giveItems = List<Map<String, dynamic>>.from(data['give'] ?? []);
    });
  }

  void _showLocationDetails(
      BuildContext context, Map<String, dynamic> locationDetails) async {
    try {
      js.context.callMethod('setFlutterInteractive', [true]);
    } catch (_) {}
    try {
      final double startLatitude = currentLat;
      final double startLongitude = currentLng;
      final location = locationDetails['location'] as Map<String, dynamic>?;
      final double endLatitude =
          (location?['lat'] as num?)?.toDouble() ?? currentLat;
      final double endLongitude =
          (location?['lng'] as num?)?.toDouble() ?? currentLng;

      double distanceInMeters = Geolocator.distanceBetween(
          startLatitude, startLongitude, endLatitude, endLongitude);
      String distanceDisplay = distanceInMeters < 1000
          ? '${distanceInMeters.toStringAsFixed(0)}m'
          : '${(distanceInMeters / 1000).toStringAsFixed(1)}km';

      final title = locationDetails['name'] ?? (locationDetails['type'] ?? 'ASSISTANCE').toString().toUpperCase();
      final address = locationDetails['address'] ?? '';
      final phone = locationDetails['phone'] ?? '';
      final hours = locationDetails['operating_hours'] ?? '';
      final List<dynamic> items = locationDetails['items_available'] ?? locationDetails['help'] ?? [];

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext bc) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.getFont(
                                "Lexend",
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.black,
                              ),
                            ),
                            if (locationDetails['type'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  locationDetails['type'].toString().toUpperCase(),
                                  style: GoogleFonts.getFont(
                                    "Lexend",
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 14, color: Colors.green[700]),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(color: Colors.green[800], fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (address.isNotEmpty) ...[
                    SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.grey[700]),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address,
                            style: GoogleFonts.getFont("Lexend", fontSize: 13, color: Colors.grey[800]),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (hours.isNotEmpty) ...[
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.teal),
                        SizedBox(width: 6),
                        Text(
                          hours,
                          style: GoogleFonts.getFont("Lexend", fontSize: 13, color: Colors.teal[800], fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 14),
                  Divider(),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.near_me, color: Colors.blue, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Distance: $distanceDisplay',
                        style: GoogleFonts.getFont("Lexend", fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                      ),
                      Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          _openMapRoute(startLatitude, startLongitude, endLatitude, endLongitude);
                        },
                        icon: Icon(Icons.directions, color: Colors.blue, size: 16),
                        label: Text('Route', style: GoogleFonts.getFont("Lexend", color: Colors.blue, fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.teal.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          js.context.callMethod('updateWindyLocation', [endLatitude, endLongitude]);
                        },
                        icon: Icon(Icons.map, color: Colors.teal, size: 16),
                        label: Text('Map', style: GoogleFonts.getFont("Lexend", color: Colors.teal, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (phone.isNotEmpty) ...[
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.phone, color: Colors.black54, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            phone,
                            style: GoogleFonts.getFont("Lexend", fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.green.withOpacity(0.1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () => launch('tel:$phone'),
                          icon: Icon(Icons.call, color: Colors.green[700], size: 16),
                          label: Text('Call', style: GoogleFonts.getFont("Lexend", color: Colors.green[700], fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                  if (items.isNotEmpty) ...[
                    SizedBox(height: 18),
                    Text(
                      'Available Supplies & Assistance:',
                      style: GoogleFonts.getFont("Lexend", fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: items.map<Widget>((it) {
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            it.toString(),
                            style: GoogleFonts.getFont("Lexend", fontSize: 12, color: Colors.black87),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      try {
        js.context.callMethod('setFlutterInteractive', [false]);
      } catch (_) {}
    }
  }

  void _openMapRoute(
      double startLat, double startLng, double endLat, double endLng) async {
    String googleMapsUrl =
        "https://www.google.com/maps/dir/?api=1&origin=$startLat,$startLng&destination=$endLat,$endLng&travelmode=driving";
    if (await canLaunch(googleMapsUrl)) {
      await launch(googleMapsUrl);
    } else {
      throw 'Could not open the map.';
    }
  }

  Future<void> _handleOfflineMode() async {
    if (isOffline) {
      while (isOffline) {
        await Future.delayed(Duration(hours: 2));
        final smsNumber = FlutterConfig.get('SMS_NUMBER');
        final lat = currentLat;
        final lng = currentLng;
        final message = 'offline $lat $lng';
        launch('sms:$smsNumber?body=$message');
        final response = await _waitForResponse(smsNumber);
        final jsonData = _combineJsonData(response);
        _processJsonData(jsonData);
      }
    }
  }

  void _loadModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isHelping = prefs.getBool('mode') ?? false;
    });
  }

  Future<List<String>> _waitForResponse(String smsNumber) async {
    // SMS/telephony not supported on web - return empty list
    final List<String> messages = [];
    await Future.delayed(const Duration(seconds: 1));
    return messages;
  }

  List<Map<String, dynamic>> _getFilteredItems() {
    List<Map<String, dynamic>> items = isHelping ? _giveItems : _needItems;
    if (selectedFilter.isEmpty) return items;
    return items.where((item) {
      String type = (item['type'] ?? '').toString().toLowerCase();
      return type == selectedFilter.toLowerCase();
    }).toList();
  }

  Map<String, dynamic> _combineJsonData(List<String> messages) {
    final Map<String, dynamic> combinedJson = {};
    final RegExp numberRegex = RegExp(r'^(\d+)-end$');
    final Map<int, String> orderedMessages = {};

    for (final message in messages) {
      final match = numberRegex.firstMatch(message);
      if (match != null) {
        final int number = int.parse(match.group(1)!);
        orderedMessages[number] = message;
      }
    }

    final List<String> orderedData = orderedMessages.values.toList();
    for (final data in orderedData) {
      final jsonData = jsonDecode(data);
      combinedJson.addAll(jsonData);
    }

    return combinedJson;
  }

  // <--------------------- UI --------------------->

  String _formatType(String raw) {
    if (raw.isEmpty) return 'Unknown';
    final spaced = raw.replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  IconData _getIconForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('pharmacy') || t.contains('drug')) return Icons.local_pharmacy;
    if (t.contains('groc') || t.contains('food') || t.contains('ration')) return Icons.shopping_basket;
    if (t.contains('hospital') || t.contains('clinic') || t.contains('medic')) return Icons.local_hospital;
    if (t.contains('relief') || t.contains('camp')) return Icons.holiday_village;
    if (t.contains('shelter') || t.contains('safe') || t.contains('space') || t.contains('home')) return Icons.home;
    if (t.contains('suppl') || t.contains('hardware') || t.contains('inventor')) return Icons.inventory_2;
    if (t.contains('rescue') || t.contains('boat') || t.contains('evac')) return Icons.emergency;
    if (t.contains('water')) return Icons.water_drop;
    if (t.contains('power') || t.contains('charg') || t.contains('bolt')) return Icons.bolt;
    return Icons.volunteer_activism;
  }

  void _showAssistanceDrawer({String? initialHeading}) async {
    try {
      js.context.callMethod('setFlutterInteractive', [true]);
    } catch (_) {}

    if (initialHeading != null && initialHeading.isNotEmpty) {
      _fetchGroqShops(initialHeading);
    }

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext bc) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              final defaultItems = isHelping ? _giveItems : _needItems;
              final bool isGroqActive = !isHelping && _activeGroqHeading.isNotEmpty;
              final displayList = isGroqActive ? _groqShops : defaultItems;

              return Container(
                height: MediaQuery.of(context).size.height * 0.82,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Drag handle
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // Need Help / Give Help toggle inside drawer
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: CupertinoSlidingSegmentedControl<int>(
                          children: {
                            0: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Text(
                                'Need Help',
                                style: GoogleFonts.getFont('Lexend',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: isHelping ? Colors.grey : Colors.redAccent),
                              ),
                            ),
                            1: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Text(
                                'Give Help',
                                style: GoogleFonts.getFont('Lexend',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: isHelping ? Colors.blue : Colors.grey),
                              ),
                            ),
                          },
                          groupValue: isHelping ? 1 : 0,
                          onValueChanged: (int? value) {
                            setState(() {
                              isHelping = value == 1;
                              if (isHelping) _activeGroqHeading = '';
                            });
                            setModalState(() {});
                          },
                          backgroundColor: Color(0xFFEEEEEE),
                          thumbColor: Colors.white,
                        ),
                      ),
                    ),
                    // Headings horizontal chips (when in Need Help mode)
                    if (!isHelping)
                      Container(
                        height: 48,
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3.0),
                              child: ChoiceChip(
                                label: Text('All', style: GoogleFonts.getFont('Lexend', fontSize: 13, fontWeight: FontWeight.bold)),
                                selected: _activeGroqHeading.isEmpty,
                                onSelected: (val) {
                                  setState(() {
                                    _activeGroqHeading = '';
                                    _groqShops.clear();
                                  });
                                  setModalState(() {});
                                },
                                selectedColor: Colors.black87,
                                labelStyle: TextStyle(color: _activeGroqHeading.isEmpty ? Colors.white : Colors.black87),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ),
                            ...filtersNeedHelp.map((f) {
                              final isSel = _activeGroqHeading == f['type'];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                                child: ChoiceChip(
                                  avatar: Icon(f['icon'], size: 16, color: isSel ? Colors.white : Colors.redAccent),
                                  label: Text(
                                    f['type'],
                                    style: GoogleFonts.getFont('Lexend', fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  selected: isSel,
                                  onSelected: (val) {
                                    _fetchGroqShops(f['type'], setModalState);
                                  },
                                  selectedColor: Colors.redAccent,
                                  labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87),
                                  backgroundColor: Color(0xFFF1F5F9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    // Heading Title + Count Row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                isHelping
                                    ? 'Available Requests'
                                    : (_activeGroqHeading.isNotEmpty
                                        ? 'Nearby ${_activeGroqHeading} Shops'
                                        : 'Nearby Assistance'),
                                style: GoogleFonts.getFont(
                                  'Lexend',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: Colors.black87,
                                ),
                              ),
                              if (isGroqActive) ...[
                                SizedBox(width: 6),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.bolt, size: 12, color: Colors.amber[900]),
                                      Text(
                                        'Groq AI',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber[900]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            _isLoadingGroqShops
                                ? 'Scanning...'
                                : '${displayList.length} locations',
                            style: GoogleFonts.getFont(
                              'Lexend',
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Groq AI Status Pill
                    if (isGroqActive)
                      Container(
                        margin: EdgeInsets.fromLTRB(16, 4, 16, 6),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.my_location, color: Color(0xFF16A34A), size: 14),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'GPS: (${currentLat.toStringAsFixed(3)}, ${currentLng.toStringAsFixed(3)}) • Showing nearby ${_activeGroqHeading}',
                                style: GoogleFonts.getFont('Lexend', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() { _activeGroqHeading = ''; });
                                setModalState(() {});
                              },
                              child: Icon(Icons.close, size: 16, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    // Body List
                    Expanded(
                      child: _isLoadingGroqShops
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: Colors.redAccent),
                                    SizedBox(height: 16),
                                    Text(
                                      'Locating nearby $_activeGroqHeading with Groq AI...',
                                      style: GoogleFonts.getFont('Lexend', fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Searching shops around your current device coordinates',
                                      style: GoogleFonts.getFont('Lexend', color: Colors.grey[600], fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : displayList.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.store_mall_directory_outlined, size: 48, color: Colors.grey[400]),
                                      SizedBox(height: 12),
                                      Text(
                                        isGroqActive
                                            ? 'No locations found for this heading'
                                            : 'No locations found',
                                        style: GoogleFonts.getFont('Lexend', color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  itemCount: displayList.length,
                                  separatorBuilder: (_, __) => SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final item = displayList[index];
                                    final double itemLat = (item['location']?['lat'] as num?)?.toDouble() ?? currentLat;
                                    final double itemLng = (item['location']?['lng'] as num?)?.toDouble() ?? currentLng;
                                    final dist = Geolocator.distanceBetween(currentLat, currentLng, itemLat, itemLng);
                                    final distStr = dist < 1000
                                        ? '${dist.toStringAsFixed(0)}m'
                                        : '${(dist / 1000).toStringAsFixed(1)}km';
                                    final String name = item['name'] ?? (item['type'] ?? 'ASSISTANCE').toString().toUpperCase();
                                    final String address = item['address'] ?? '';
                                    final String hours = item['operating_hours'] ?? '';
                                    final List<dynamic> itemsAvail = item['items_available'] ?? item['help'] ?? [];

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Color(0xFFE2E8F0)),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _showLocationDetails(context, item);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    padding: EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: (isHelping ? Colors.blue : Colors.redAccent).withOpacity(0.12),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      _getIconForType(item['type'] ?? _activeGroqHeading),
                                                      color: isHelping ? Colors.blue : Colors.redAccent,
                                                      size: 18,
                                                    ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                name,
                                                                style: GoogleFonts.getFont(
                                                                  'Lexend',
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 14,
                                                                  color: Colors.black87,
                                                                ),
                                                              ),
                                                            ),
                                                            Container(
                                                              padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: Colors.blue.withOpacity(0.1),
                                                                borderRadius: BorderRadius.circular(10),
                                                              ),
                                                              child: Text(
                                                                distStr,
                                                                style: GoogleFonts.getFont(
                                                                  'Lexend',
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: Colors.blue[800],
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        if (address.isNotEmpty) ...[
                                                          SizedBox(height: 3),
                                                          Row(
                                                            children: [
                                                              Icon(Icons.place, size: 12, color: Colors.grey[600]),
                                                              SizedBox(width: 3),
                                                              Expanded(
                                                                child: Text(
                                                                  address,
                                                                  style: GoogleFonts.getFont(
                                                                    'Lexend',
                                                                    fontSize: 11,
                                                                    color: Colors.grey[700],
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                        if (hours.isNotEmpty) ...[
                                                          SizedBox(height: 2),
                                                          Row(
                                                            children: [
                                                              Icon(Icons.access_time, size: 12, color: Colors.teal),
                                                              SizedBox(width: 3),
                                                              Text(
                                                                hours,
                                                                style: GoogleFonts.getFont(
                                                                  'Lexend',
                                                                  fontSize: 11,
                                                                  color: Colors.teal[700],
                                                                  fontWeight: FontWeight.w500,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (itemsAvail.isNotEmpty) ...[
                                                SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 5,
                                                  runSpacing: 4,
                                                  children: itemsAvail.take(4).map<Widget>((it) {
                                                    return Container(
                                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Color(0xFFCBD5E1)),
                                                      ),
                                                      child: Text(
                                                        it.toString(),
                                                        style: GoogleFonts.getFont('Lexend', fontSize: 10, color: Colors.black87),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ],
                                              SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  if (item['phone'] != null && item['phone'].toString().isNotEmpty)
                                                    TextButton.icon(
                                                      style: TextButton.styleFrom(
                                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        minimumSize: Size(0, 0),
                                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      ),
                                                      onPressed: () => launch('tel:${item['phone']}'),
                                                      icon: Icon(Icons.call, size: 14, color: Colors.green[700]),
                                                      label: Text('Call', style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.bold)),
                                                    ),
                                                  SizedBox(width: 6),
                                                  TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      minimumSize: Size(0, 0),
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    ),
                                                    onPressed: () {
                                                      _openMapRoute(currentLat, currentLng, itemLat, itemLng);
                                                    },
                                                    icon: Icon(Icons.directions, size: 14, color: Colors.blue),
                                                    label: Text('Route', style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
                                                  ),
                                                  SizedBox(width: 6),
                                                  TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      minimumSize: Size(0, 0),
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      js.context.callMethod('updateWindyLocation', [itemLat, itemLng]);
                                                    },
                                                    icon: Icon(Icons.map, size: 14, color: Colors.teal),
                                                    label: Text('Map', style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      try {
        js.context.callMethod('setFlutterInteractive', [false]);
      } catch (_) {}
    }
  }

  Widget _buildTopFloatingBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      height: 48,
      margin: EdgeInsets.only(top: topPadding > 0 ? topPadding + 6 : 14),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8, spreadRadius: 1)
            ],
          ),
          child: CupertinoSlidingSegmentedControl<int>(
            children: {
              0: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  'Need Help',
                  style: GoogleFonts.getFont('Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isHelping ? Colors.grey : Colors.redAccent),
                ),
              ),
              1: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  'Give Help',
                  style: GoogleFonts.getFont('Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isHelping ? Colors.blue : Colors.grey),
                ),
              ),
            },
            groupValue: isHelping ? 1 : 0,
            onValueChanged: (int? value) {
              setState(() {
                isHelping = value == 1;
                _isSpeedDialOpen = false;
                if (isHelping) _activeGroqHeading = '';
              });
            },
            backgroundColor: const Color(0xFFEEEEEE),
            thumbColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineWidget() {
    return Container(
      margin: EdgeInsets.all(20.0),
      padding: EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white),
          SizedBox(width: 10.0),
          Expanded(
            child: Text(
              'No network connection, switching to SMS mode',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    List<Map<String, dynamic>> currentFilters =
        isHelping ? filtersGiveHelp : filtersNeedHelp;
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: currentFilters.length,
        itemBuilder: (BuildContext context, int index) {
          Map<String, dynamic> filter = currentFilters[index];
          bool isSelected = filter['type'] == selectedFilter;

          return Container(
            margin: EdgeInsets.symmetric(horizontal: 3),
            child: FilterChip(
              avatar: Icon(filter['icon'],
                  color: isSelected ? Colors.white : Colors.grey),
              label: Text(filter['type'],
                  style: GoogleFonts.getFont('Lexend',
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: isSelected ? Colors.white : Colors.grey)),
              selected: isSelected,
              onSelected: (bool value) {
                setState(() {
                  selectedFilter = value ? filter['type'] : '';
                });
              },
              backgroundColor: Color.fromARGB(255, 227, 227, 227),
              selectedColor: isHelping
                  ? Color.fromARGB(255, 137, 202, 255)
                  : Color.fromARGB(255, 250, 121, 121),
              checkmarkColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : Colors.transparent,
                ),
              ),
              shadowColor: Colors.black,
              elevation: 3,
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget recenterBtn() {
    return Positioned(
      right: 16.0,
      bottom: 110.0,
      child: FloatingActionButton(
        mini: false,
        child: Icon(Icons.streetview, color: Colors.black),
        backgroundColor: Colors.white,
        onPressed: () {
          js.context
              .callMethod('updateWindyLocation', [currentLat, currentLng]);
          _loadJsonData();
        },
      ),
    );
  }

  Widget _buildAssistanceSpeedDial() {
    final activeChips = isHelping ? filtersGiveHelp : filtersNeedHelp;

    return Positioned(
      right: 16.0,
      bottom: 240.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isSpeedDialOpen) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 220),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Option to open full drawer
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isSpeedDialOpen = false;
                        });
                        _showAssistanceDrawer();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: (isHelping ? Colors.blue : Colors.redAccent).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dashboard_customize, size: 16, color: isHelping ? Colors.blue : Colors.redAccent),
                            const SizedBox(width: 8),
                            Text(
                              'View All Nearby',
                              style: GoogleFonts.getFont(
                                'Lexend',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isHelping ? Colors.blue : Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 8),
                    // Heading chips
                    ...activeChips.map((f) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isSpeedDialOpen = false;
                            });
                            _showAssistanceDrawer(initialHeading: f['type']);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(f['icon'], size: 16, color: isHelping ? Colors.blue : Colors.redAccent),
                                const SizedBox(width: 8),
                                Text(
                                  f['type'],
                                  style: GoogleFonts.getFont(
                                    'Lexend',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ],
          // Main trigger button for the assistance options
          FloatingActionButton(
            mini: false,
            backgroundColor: _isSpeedDialOpen
                ? Colors.black87
                : Colors.white,
            foregroundColor: _isSpeedDialOpen
                ? Colors.white
                : (isHelping ? Colors.blue : Colors.redAccent),
            tooltip: 'Nearby Assistance Options',
            onPressed: () {
              setState(() {
                _isSpeedDialOpen = !_isSpeedDialOpen;
              });
            },
            child: Icon(_isSpeedDialOpen ? Icons.close : Icons.store_mall_directory),
          ),
        ],
      ),
    );
  }

  Widget actionBtn(isHelping) {
    return Positioned(
      right: 16.0,
      bottom: 45.0,
      child: buildFloatingActionButton(
        isHelping: isHelping,
      ),
    );
  }

  Widget buildFloatingActionButton({
    required bool isHelping,
  }) {
    return FloatingActionButton(
      child: Icon(
        isHelping
            ? Icons.favorite
            : Icons.volunteer_activism,
        color: Colors.white,
      ),
      backgroundColor: isHelping
          ? Color.fromARGB(255, 137, 202, 255)
          : Color.fromARGB(255, 250, 121, 121),
      onPressed: actionButtonClickFn,
    );
  }

  Widget _buildItemsPanel() {
    final items = _getFilteredItems();
    if (items.isEmpty) return SizedBox.shrink();
    return Positioned(
      bottom: 90,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 10),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final loc2 = item['location'] as Map<String, dynamic>?;
            final double itemLat =
                (loc2?['lat'] as num?)?.toDouble() ?? currentLat;
            final double itemLng =
                (loc2?['lng'] as num?)?.toDouble() ?? currentLng;
            final dist = Geolocator.distanceBetween(
                currentLat, currentLng, itemLat, itemLng);
            final distStr = dist < 1000
                ? '${dist.toStringAsFixed(0)}m'
                : '${(dist / 1000).toStringAsFixed(1)}km';
            return GestureDetector(
              onTap: () => _showLocationDetails(context, item),
              child: Container(
                width: 140,
                margin: EdgeInsets.symmetric(horizontal: 5),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.93),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      (item['type'] ?? '').toString().toUpperCase(),
                      style: GoogleFonts.getFont('Lexend',
                          fontWeight: FontWeight.bold, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.place, size: 12, color: Colors.grey),
                      SizedBox(width: 2),
                      Text(distStr,
                          style: GoogleFonts.getFont('Lexend',
                              fontSize: 11, color: Colors.grey)),
                    ]),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void makePostRequest(List<String> selectedHelp, bool isHelping, dynamic lat,
      dynamic lng) async {
    final prefs = await SharedPreferences.getInstance();
    String phoneNumber =
        prefs.getString('phoneNumber') ?? 'No phone number set';

    String mode = isHelping ? "give" : "need";
    String type = isHelping ? "volunteer" : "victim";
    double latitude = lat;
    double longitude = lng;

    Map<String, dynamic> requestBody = {
      "mode": mode,
      "type": type,
      "location": {"lat": latitude, "lng": longitude},
      "phone": phoneNumber,
      "help": selectedHelp,
    };

    final response = await http.post(
      Uri.parse(_safeBackendUrl() + "/api/v1"),
      headers: <String, String>{
        'Content-Type': 'application/json;',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      print('POST request successful');
      print('Response: ${response.body}');
    } else {
      print('POST request failed with status: ${response.statusCode}');
      print('Response: ${response.body}');
    }
  }

  void reloadMapMarkers() async {
    await _loadJsonData();
  }

  void actionButtonClickFn() async {
    try {
      js.context.callMethod('setFlutterInteractive', [true]);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      String phoneNumber =
          prefs.getString('phoneNumber') ?? 'No phone number set';

      Map<String, IconData> needHelpIcons = {
        'Medical': Icons.medical_services,
        'Rescue & Evacuation': Icons.emergency,
        'Shelter': Icons.house,
        'Food & Rations': Icons.fastfood,
        'Clean Water': Icons.water_drop,
        'Clothing': Icons.checkroom,
        'Power & Charging': Icons.bolt,
        'Other': Icons.help_outline,
      };

      Map<String, IconData> giveHelpIcons = {
        'Volunteer': Icons.volunteer_activism,
        'Donate Supplies': Icons.monetization_on,
        'Provide Shelter': Icons.house,
        'Offer Food & Water': Icons.food_bank,
        'Medical Assistance': Icons.medical_services,
        'Rescue / Boat Unit': Icons.directions_boat,
      };

      Map<String, IconData> activeIcons =
          isHelping ? giveHelpIcons : needHelpIcons;

      Map<String, bool> helpOptions = {
        for (var item in activeIcons.keys) item: false,
      };

      bool isAnyOptionSelected() {
        return helpOptions.containsValue(true);
      }

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
        ),
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              return Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(height: 10),
                    Text(
                      isHelping ? ' I can provide' : ' I need',
                      style: GoogleFonts.getFont(
                        "Lexend",
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    Divider(),
                    ...helpOptions.keys.map((option) {
                      final isSelected = helpOptions[option]!;
                      return Container(
                        margin: EdgeInsets.only(top: 10),
                        child: InkWell(
                          onTap: () {
                            setModalState(() {
                              helpOptions[option] = !isSelected;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              border: isSelected
                                   ? Border.all(
                                       color: Theme.of(context).primaryColor,
                                       width: 2)
                                   : Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 15),
                                Icon(activeIcons[option],
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey),
                                SizedBox(width: 15),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: GoogleFonts.getFont(
                                      "Lexend",
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Theme.of(context).primaryColor
                                          : Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check,
                                      color: Theme.of(context).primaryColor),
                                SizedBox(width: 15),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: StadiumBorder(),
                        backgroundColor: isHelping ? Colors.blue : Colors.red,
                        padding:
                            EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                      child: Text(
                        'Submit',
                        style: GoogleFonts.getFont(
                          "Lexend",
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: isAnyOptionSelected()
                          ? () async {
                              List<String> selectedHelp = helpOptions.entries
                                  .where((entry) => entry.value)
                                  .map((entry) => entry.key)
                                  .toList();
                              print('Phone Number: $phoneNumber');
                              print('Selected Help Options: $selectedHelp');
                              makePostRequest(selectedHelp, isHelping,
                                  currentLat, currentLng);
                              Navigator.pop(context);
                              reloadMapMarkers();
                            }
                          : null,
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      try {
        js.context.callMethod('setFlutterInteractive', [false]);
      } catch (_) {}
    }
  }

  // <--------------------- Build --------------------->
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Map is in HTML background (index.html) — Flutter is fully transparent here
          const SizedBox.expand(),
          Column(
            children: [
              _buildTopFloatingBar(),
              isOffline ? _buildOfflineWidget() : Container(),
            ],
          ),
          recenterBtn(),
          _buildAssistanceSpeedDial(),
          actionBtn(isHelping),
          SOSButton(
            isHelping: isHelping == true,
            currentLat: currentLat,
            currentLng: currentLng,
          ),
        ],
      ),
    );
  }
}
