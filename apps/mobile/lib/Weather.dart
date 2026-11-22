import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'config/app_config.dart';

String _safeBackendUrl() => AppConfig.baseUrl;

class WeatherScreen extends StatefulWidget {
  @override
  _WeatherScreenState createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  late Map<String, dynamic> weatherData = {};

  @override
  void initState() {
    super.initState();
    _loadWeatherData();
  }

  // Future<void> _loadWeatherData() async {
  //   final jsonString = await rootBundle.loadString('assets/weatherData.json');
  //   final jsonData = json.decode(jsonString);
  //   setState(() {
  //     weatherData = jsonData;
  //   });

  Future<void> _loadWeatherData() async {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    final response = await http.get(Uri.parse(_safeBackendUrl() +
        '/api/gemini?city=' +
        position.latitude.toString() +
        ',' +
        position.longitude.toString()));

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);

      setState(() {
        weatherData = jsonData;
      });
    } else {
      _loadWeatherData();
    }
  }

  IconData _getWeatherIcon(String weather) {
    switch (weather.toLowerCase()) {
      case 'partly cloudy':
        return Icons.wb_cloudy;
      case 'sunny':
        return Icons.wb_sunny;
      case 'rainy':
        return Icons.grain;
      case 'thunderstorm':
        return Icons.bolt;
      case 'snowy':
        return Icons.ac_unit;
      case 'windy':
        return Icons.air;
      case 'foggy':
        return Icons.foggy;
      case 'hail':
        return Icons.cloudy_snowing;
      default:
        return Icons.help_outline;
    }
  }

  Color _getColor(String color) {
    switch (color.toLowerCase()) {
      case 'white':
        return Colors.white;
      case 'red':
        return Colors.red;
      case 'orange':
        return Colors.orange;
      case 'yellow':
        return Colors.yellow;
      case 'green':
        return Colors.green;
      default:
        return Colors.transparent;
    }
  }

  List<Widget> _buildPrecautionItems(List<dynamic> precautions) {
    return precautions
        .map(
          (precaution) => Padding(
            padding: const EdgeInsets.only(left: 40.0, right: 40.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                  dense: true,
                  leading: Icon(Icons.circle, size: 10),
                  title: Text(
                    precaution,
                    style: TextStyle(
                      fontFamily: GoogleFonts.kanit().fontFamily,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: weatherData.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _getColor(weatherData['Color']),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Icon(
                    _getWeatherIcon(weatherData['weather']),
                    size: 150,
                  ),
                  const SizedBox(height: 40),
                  Text(
                    weatherData['weather'],
                    style: TextStyle(
                      fontFamily: GoogleFonts.kanit().fontFamily,
                      fontSize: 35,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    width: 250,
                    height: 35,
                    decoration: ShapeDecoration(
                      color: Color(0xFFD9D9D9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'In ${weatherData["Time"]} hrs',
                        style: GoogleFonts.kanit(
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildPrecautionItems(
                                weatherData['Precautions']),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
