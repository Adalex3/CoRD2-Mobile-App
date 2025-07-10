import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cord2_mobile_app/classes/analytics.dart';
import 'package:cord2_mobile_app/pages/messages.dart';
import 'package:cord2_mobile_app/pages/search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // for Polyline & PolylineLayer
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_model.dart';
import '../models/point_data.dart';
import 'package:location/location.dart' hide PermissionStatus;
import 'package:permission_handler/permission_handler.dart';

class DisplayMap extends StatefulWidget {
  final bool admin;
  final String userId;

  const DisplayMap({super.key, this.admin = false, required this.userId});

  @override
  State<DisplayMap> createState() => DisplayMapPageState();
}

class DisplayMapPageState extends State<DisplayMap> {
  final AnalyticsService analytics = AnalyticsService();
  final double latitude = 28.5384;
  final double longitude = -81.3789;
  late List<Marker> _markers = [];
  late List<PointData> _data = [];
  // related to lotis data
  late List<Marker> school_markers = [];
  late List<Marker> sunrail_markers = [];
  late List<Marker> transit_markers = [];
  late List<Polygon> counties_polygons = [];
  late MapController mapController;
  CollectionReference events = FirebaseFirestore.instance.collection('events');
  CollectionReference users = FirebaseFirestore.instance.collection('users');
  String permType = '';

  static const String _hurdatUrl = 'https://www.nhc.noaa.gov/data/hurdat/hurdat2-1851-2024-040425.txt';

  bool showReports = true;
  bool showSchools = true;
  bool showSunrail = false;
  bool showTransit = false;
  bool showCountyLine = false;
  bool showHurricanes = false;
  List<String> selectedHurricanes = [];
  List<Polyline> hurricanePolylines = [];

  final Location _locationController = Location();
  StreamSubscription<LocationData>? locationSubscription;

  LatLng? _currentP;
  Timer? locationUpdates;

  @override
  void initState() {
    geoJsonParser.setDefaultMarkerTapCallback(onTapMarkerFunction);
    geoJsonParser2.setDefaultMarkerTapCallback(onTapMarkerFunction);
    geoJsonParser3.setDefaultMarkerTapCallback(onTapMarkerFunction);
    geoJsonParser4.setDefaultMarkerTapCallback(onTapMarkerFunction);

    mapController = MapController();
    processData();
    createMarkers();
    analytics.logScreenBrowsing("Map");

    print("here");

    getLocationUpdates();
    // locationUpdates = Timer.periodic(
    //     const Duration(minutes: 5), (Timer t) => sendLocationToFirebase());

    super.initState();
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    locationUpdates?.cancel();
    super.dispose();
  }

  // Sends Location to Firebase
  void sendLocationToFirebase() {
    if (_currentP != null) {
      analytics.logLocationChecked(_currentP!.latitude, _currentP!.longitude);

      users.doc(widget.userId).update({
        "location": {
          "latitude": _currentP!.latitude,
          "longitude": _currentP!.longitude,
          "lastUpdate": DateTime.now().millisecondsSinceEpoch
        }
      });
    }
  }

  // will update realtime location in app if given permission
  Future<void> getLocationUpdates() async {
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _permissionGranted = await Permission.location.request();
    if (_permissionGranted != PermissionStatus.granted) {
      var status = await Permission.location.request();

      if (status != PermissionStatus.granted) {
        await openAppSettings();
      }
    }

    if (_permissionGranted.isGranted) {
      print("here!");
      _serviceEnabled = await _locationController.serviceEnabled();
      if (_serviceEnabled) {
        _serviceEnabled = await _locationController.requestService();
      } else {
        return;
      }

      print("here!!!");

      locationSubscription = _locationController.onLocationChanged
          .listen((LocationData currentLocation) {
        if (currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          if (mounted) {
            setState(() {
              _currentP =
                  LatLng(currentLocation.latitude!, currentLocation.longitude!);
            });
          }
        }
      });
    }
  }

  // zooms closer to users current position
  void pinpointUser() async {
    if (_currentP != null) {
      mapController.move(_currentP!, 15.0);
      analytics.logLocationChecked(_currentP!.latitude, _currentP!.longitude);
    }

    createMarkers();
  }

  // zooms closer to selected search result
  void zoomTo(double lat, double lon) {
    mapController.move(LatLng(lat, lon), 15.0);
  }

  // reloads submitted reports from database
  void refreshMap() async {
    createMarkers();
    mapController.move(LatLng(latitude, longitude), 9.0);
  }

  // instantiate parser, use the defaults
  GeoJsonParser geoJsonParser = GeoJsonParser(
    defaultMarkerColor: Colors.yellow[800],
    defaultPolygonBorderColor: Colors.red,
    defaultPolygonFillColor: Colors.red.withOpacity(0.1),
    defaultCircleMarkerColor: Colors.red.withOpacity(0.25),
  );

  // instantiate parser, use the defaults
  GeoJsonParser geoJsonParser2 = GeoJsonParser(
    defaultMarkerColor: Colors.yellow[800],
    defaultPolygonBorderColor: Colors.red,
    defaultPolygonFillColor: Colors.red.withOpacity(0.1),
    defaultCircleMarkerColor: Colors.red.withOpacity(0.25),
  );

  // instantiate parser, use the defaults
  GeoJsonParser geoJsonParser3 = GeoJsonParser(
    defaultMarkerColor: Colors.yellow[800],
    defaultPolygonBorderColor: Colors.red,
    defaultPolygonFillColor: Colors.red.withOpacity(0.1),
    defaultCircleMarkerColor: Colors.red.withOpacity(0.25),
  );

  GeoJsonParser geoJsonParser4 = GeoJsonParser(
    defaultMarkerColor: Colors.yellow[800],
    defaultPolygonBorderColor: Colors.red,
    defaultPolygonFillColor: Colors.red.withOpacity(0.1),
    defaultCircleMarkerColor: Colors.red.withOpacity(0.25),
  );

  // can filter based on criteria
  bool myFilterFunction(Map<String, dynamic> properties) {
    if (properties['FID'].toString().contains('0')) {
      return false;
    } else {
      return true;
    }
  }

  // shows lotis data points
  void onTapMarkerFunction(Map<String, dynamic> map) {
    analytics.logMapPointClick("GeoJson Point");

    // the specific geojsons all record diff data, so popup needs to be customized
    // for what you want to display in popup, a lot are just blank
    showModalBottomSheet(
        useRootNavigator: true,
        backgroundColor: const Color(0xff242C73),
        context: context,
        builder: (BuildContext bc) {
          return SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              width: MediaQuery.of(context).size.width * 1,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.deepOrange,
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                      ),
                      child: CloseButton(
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20.0)),
                            color: Colors.white,
                          ),
                          child: Center(
                            child: Text(map['FID'].toString(), // all have
                                style: GoogleFonts.jost(
                                    textStyle: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold))),
                          ),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                          ),
                          child: Center(
                            // transit/sunrail both have StrName, school has School_Nam
                            child: map['School_Nam'] != null
                                ? Text(map['School_Nam'],
                                    style: GoogleFonts.jost(
                                        textStyle:
                                            const TextStyle(fontSize: 18)))
                                : Text(map['StrName'],
                                    style: GoogleFonts.jost(
                                        textStyle:
                                            const TextStyle(fontSize: 18))),
                          ),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                          ),
                          child: Center(
                            // transit/sunrail both have City, school has School_Dst
                            child: map['City'] != null
                                ? Text(map['City'],
                                    style: GoogleFonts.jost(
                                        textStyle:
                                            const TextStyle(fontSize: 14)))
                                : Text(map['School_Dst'],
                                    style: GoogleFonts.jost(
                                        textStyle:
                                            const TextStyle(fontSize: 14))),
                          ),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(20.0)),
                            color: Colors.white,
                          ),
                          child: Center(
                            // transit/sunrail have Type, school has School_Typ
                            child: map['School_Typ'] != null
                                ? Text(map['School_Typ'],
                                    style: GoogleFonts.jost(
                                        textStyle:
                                            const TextStyle(fontSize: 14)))
                                : Text(map['Type'],
                                    style: GoogleFonts.jost(
                                        textStyle:
                                            const TextStyle(fontSize: 14))),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ));
        });
  }

  // shows user submitted reports
  void createMarkers() async {
    List<Marker> markers = [];
    List<PointData> points = [];
    // Get docs from collection reference
    QuerySnapshot querySnapshot = await events.get();
    // Get data from docs and convert map to List
    final allData = querySnapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    QuerySnapshot userSnapshot = await users.get();
    // Get data from docs and convert map to List
    final allUsers = userSnapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    // loop through allData and add markers there
    for (var point in allData) {
      String theUser;
      DocumentSnapshot doc = await users.doc(point['creator'].toString()).get();
      if (!mounted) return;
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String username = data['name'];
      DateTime time = point['time'].toDate();
      String imageURL = point['images'].toString();

      // if active show/add, otherwise dont show
      if (point['active'] == true) {
        var pointData = PointData(
            point['latitude'] as double,
            point['longitude'] as double,
            point['description'],
            point['title'],
            point['eventType'],
            imageURL.substring(1, imageURL.length - 1),
            DateFormat.yMEd().add_jms().format(time),
            username,
            point['creator']);

        markers.add(Marker(
            point: LatLng(
                point['latitude'] as double, point['longitude'] as double),
            width: 56,
            height: 56,
            child: customMarker(pointData)));
        points.add(pointData);
      }
    }

    setState(() {
      if (!mounted) return;
      _markers = markers;
      _data = points;
    });
  }

  MouseRegion customMarker(PointData pointData) {
    return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
            onTap: () => _showInfoScreen(context, pointData),
            child: const Icon(Icons.person_pin_circle_rounded)));
  }

  // shows user submitted points
  void _showInfoScreen(BuildContext context, PointData pointData) {
    analytics.logMapPointClick("Report");
    showModalBottomSheet(
        useRootNavigator: true,
        context: context,
        builder: (BuildContext bc) {
          return SingleChildScrollView(
              child: Stack(children: [
            Container(
              height: MediaQuery.of(context).size.height * 1.05,
              decoration: const BoxDecoration(
                color: Color(0xff242C73),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
              ),
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 20),
                    child: SingleChildScrollView(
                        child: Container(
                      margin: const EdgeInsets.all(20.0),
                      height: MediaQuery.of(context).size.height * 0.9,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                      ),
                      child: SingleChildScrollView(
                          child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 25, bottom: 5),
                            child: Center(
                                child: Text(
                                    style: GoogleFonts.jost(
                                        textStyle: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.normal,
                                      color: Color(0xff060C3E),
                                      decoration: TextDecoration.underline,
                                      decorationColor: Color(
                                          0xff242C73), // Color of the underline
                                      decorationThickness:
                                          2.0, // Thickness of the underline
                                      decorationStyle:
                                          TextDecorationStyle.solid,
                                    )),
                                    pointData.title)),
                          ),
                          const SizedBox(height: 5),
                          Text(
                              style: GoogleFonts.jost(
                                  textStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.normal,
                                color: Color(0xff060C3E),
                              )),
                              pointData.eventType),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Center(
                                child: Text(
                                    style: GoogleFonts.jost(
                                        textStyle: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.normal,
                                      color: Color(0xff060C3E),
                                    )),
                                    'Submitted by: ${pointData.creator}')),
                          ),
                          const SizedBox(height: 5),
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 10, left: 40, right: 40),
                            child: SingleChildScrollView(
                                child: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 10, left: 10, right: 10),
                                    child: SingleChildScrollView(
                                        child: Container(
                                            padding: const EdgeInsets.only(
                                                right: 10,
                                                left: 10,
                                                top: 10,
                                                bottom: 10),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(
                                                  10.0), // Adjust the radius as needed
                                              color: Colors.deepOrange,
                                            ),
                                            child: Center(
                                                child: Wrap(
                                                    alignment:
                                                        WrapAlignment.center,
                                                    children: [
                                                  Text(
                                                      style: GoogleFonts.jost(
                                                          textStyle:
                                                              const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.normal,
                                                        color: Colors.white,
                                                      )),
                                                      pointData.description)
                                                ])))))),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Center(
                                child: Image.network(
                              pointData.imageURL,
                              width: 250,
                              height: 250,
                            )),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Center(
                                child: Text(
                              pointData.formattedDate,
                              style: GoogleFonts.jost(
                                  textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.normal,
                                color: Color(0xff060C3E),
                              )),
                            )),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: ElevatedButton(
                                onPressed: () {
                                  handleUserChat(pointData.creatorId);
                                },
                                style: ButtonStyle(
                                  padding: MaterialStateProperty.all<
                                      EdgeInsetsGeometry>(
                                    const EdgeInsets.all(
                                        10.0), // Adjust the padding to change the size
                                  ),
                                  backgroundColor: MaterialStateProperty.all<
                                          Color>(
                                      const Color(0xff242C73)), // Default color
                                  overlayColor:
                                      MaterialStateProperty.resolveWith<Color>(
                                    (Set<MaterialState> states) {
                                      if (states
                                          .contains(MaterialState.hovered))
                                        return Colors.blueAccent
                                            .withOpacity(0.5); // Hover color
                                      return const Color(
                                          0xffbf0000); // No overlay color
                                    },
                                  ),
                                ),
                                child: Text(
                                  "Chat with this user",
                                  style: GoogleFonts.jost(
                                      textStyle: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.white,
                                  )),
                                )),
                          ),
                        ],
                      )),
                    )))
              ]),
            ),
            Positioned(
              top: 20, // Adjust this value as needed
              right: 15,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
                child: CloseButton(
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ]));
        });
  }

  void _showFilterScreen(BuildContext context) {
    showModalBottomSheet(
        useRootNavigator: true,
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setFilterState) {
            return SingleChildScrollView(
                child: Stack(children: [
              Container(
                height: MediaQuery.of(context).size.height * 1.05,
                decoration: const BoxDecoration(
                  color: Color(0xff242C73),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25),
                  ),
                ),
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 20),
                      child: SingleChildScrollView(
                          child: Container(
                        margin: const EdgeInsets.all(20.0),
                        height: MediaQuery.of(context).size.height * 0.9,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.all(Radius.circular(25)),
                        ),
                        child: SingleChildScrollView(
                            child: Column(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 25, bottom: 5),
                              child: Center(
                                  child: Text(
                                      style: GoogleFonts.jost(
                                          textStyle: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.normal,
                                        color: Color(0xff060C3E),
                                        decoration: TextDecoration.underline,
                                        decorationColor: Color(
                                            0xff242C73), // Color of the underline
                                        decorationThickness:
                                            2.0, // Thickness of the underline
                                        decorationStyle:
                                            TextDecorationStyle.solid,
                                      )),
                                      "Select Filters to Show")),
                            ),
                            const SizedBox(height: 20),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  showReports = !showReports;
                                });
                                setFilterState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        style: GoogleFonts.jost(
                                            textStyle: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.normal,
                                          color: Color(0xff060C3E),
                                          decorationColor: Color(
                                              0xff242C73), // Color of the underline
                                          decorationThickness:
                                              2.0, // Thickness of the underline
                                          decorationStyle:
                                              TextDecorationStyle.solid,
                                        )),
                                        "Reports"),
                                    showReports
                                        ? const Icon(Icons.check)
                                        : Container()
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  showSchools = !showSchools;
                                });

                                setFilterState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        style: GoogleFonts.jost(
                                            textStyle: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.normal,
                                          color: Color(0xff060C3E),
                                          decorationColor: Color(
                                              0xff242C73), // Color of the underline
                                          decorationThickness:
                                              2.0, // Thickness of the underline
                                          decorationStyle:
                                              TextDecorationStyle.solid,
                                        )),
                                        "Schools"),
                                    showSchools
                                        ? const Icon(Icons.check)
                                        : Container()
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  showSunrail = !showSunrail;
                                });

                                setFilterState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        style: GoogleFonts.jost(
                                            textStyle: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.normal,
                                          color: Color(0xff060C3E),
                                          decorationColor: Color(
                                              0xff242C73), // Color of the underline
                                          decorationThickness:
                                              2.0, // Thickness of the underline
                                          decorationStyle:
                                              TextDecorationStyle.solid,
                                        )),
                                        "Sunrail"),
                                    showSunrail
                                        ? const Icon(Icons.check)
                                        : Container()
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  showTransit = !showTransit;
                                });

                                setFilterState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        style: GoogleFonts.jost(
                                            textStyle: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.normal,
                                          color: Color(0xff060C3E),
                                          decorationColor: Color(
                                              0xff242C73), // Color of the underline
                                          decorationThickness:
                                              2.0, // Thickness of the underline
                                          decorationStyle:
                                              TextDecorationStyle.solid,
                                        )),
                                        "Transit"),
                                    showTransit
                                        ? const Icon(Icons.check)
                                        : Container(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            InkWell(
                              onTap: () async {
                                await _showHurricaneSelectionDialog();
                                setFilterState(() {
                                  showHurricanes = selectedHurricanes.isNotEmpty;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      style: GoogleFonts.jost(
                                        textStyle: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.normal,
                                          color: Color(0xff060C3E),
                                        ),
                                      ),
                                      "Hurricanes",
                                    ),
                                    showHurricanes ? const Icon(Icons.check) : Container(),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  showCountyLine = !showCountyLine;
                                });

                                setFilterState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        style: GoogleFonts.jost(
                                            textStyle: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.normal,
                                          color: Color(0xff060C3E),
                                          decorationColor: Color(
                                              0xff242C73), // Color of the underline
                                          decorationThickness:
                                              2.0, // Thickness of the underline
                                          decorationStyle:
                                              TextDecorationStyle.solid,
                                        )),
                                        "County Lines"),
                                    showCountyLine
                                        ? const Icon(Icons.check)
                                        : Container(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )),
                      )))
                ]),
              ),
              Positioned(
                top: 20, // Adjust this value as needed
                right: 15,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.deepOrange,
                    borderRadius: BorderRadius.all(Radius.circular(25)),
                  ),
                  child: CloseButton(
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ]));
          });
        });
  }

  void handleUserChat(String uid) async {
    DatabaseReference ref = FirebaseDatabase.instance
        .ref('chats/${FirebaseAuth.instance.currentUser?.uid}');
    DataSnapshot snapshot = await ref.get();
    for (DataSnapshot val in snapshot.children) {
      final map = val.value as Map?;
      List<String> participants =
          map?['participants'].map<String>((val) => val.toString()).toList();
      bool match = false;
      for (Object? part in map?['participants']) {
        Map<String, String> participant = {};
        if (part.toString() == uid) {
          match = true;
          DocumentSnapshot doc = await users.doc(part.toString()).get();
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          participant['name'] = data['name'];
          participant['uid'] = part.toString();
          DateTime lastUpdate = DateTime.parse(map!['lastUpdate'].toString());
          ChatModel chat =
              ChatModel(participant, participants, lastUpdate, val.key);
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => MessagePage(chat: chat)));
        }
      }
      if (match) return;
    }
    var chatId = const Uuid().v4();
    DatabaseReference newChat =
        FirebaseDatabase.instance.ref('chats/${uid}/$chatId');
    var res = await newChat.update({
      "lastUpdate": DateTime.now().toString(),
      "participants": ["${uid}", "${FirebaseAuth.instance.currentUser?.uid}"]
    });
    ref = FirebaseDatabase.instance
        .ref('chats/${FirebaseAuth.instance.currentUser?.uid}/$chatId');
    res = await ref.update({
      "lastUpdate": DateTime.now().toString(),
      "participants": ["${uid}", "${FirebaseAuth.instance.currentUser?.uid}"]
    });
    DatabaseReference newMsg = FirebaseDatabase.instance.ref('msgs');
    res = await newMsg.update({chatId: []});
    Map<String, String> participant = {};
    DocumentSnapshot doc = await users.doc(uid).get();
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    participant['name'] = data['name'];
    participant['uid'] = uid;
    List<String> participants = [uid, FirebaseAuth.instance.currentUser!.uid];
    DateTime lastUpdate = DateTime.now();

    ChatModel chat = ChatModel(participant, participants, lastUpdate, chatId);
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => MessagePage(chat: chat)));
  }

  Future<void> processData() async {
    // parses geoJson
    // normally one would use http to access geojson on web and this is
    // the reason why this function is async.
    List<String> paths = [
      'assets/LOTIS_SUNRAIL.geojson',
      'assets/LOTIS_SCHOOL.geojson',
      'assets/LOTIS_TRANSIT.geojson',
      'assets/geojson-fl-counties-fips.geojson'
    ];

    // gets geojson from assets
    String geoJsonData = await rootBundle.loadString(paths[0]);
    String geoJsonData2 = await rootBundle.loadString(paths[1]);
    String geoJsonData3 = await rootBundle.loadString(paths[2]);
    String geoJsonData4 = await rootBundle.loadString(paths[3]);

    setState(() {
      geoJsonParser.parseGeoJsonAsString(geoJsonData);
      sunrail_markers = geoJsonParser.markers;
      geoJsonParser2.parseGeoJsonAsString(geoJsonData2);
      school_markers = geoJsonParser2.markers;
      geoJsonParser3.parseGeoJsonAsString(geoJsonData3);
      transit_markers = geoJsonParser3.markers;
      geoJsonParser4.parseGeoJsonAsString(geoJsonData4);
      counties_polygons = geoJsonParser4.polygons;
    });
  }

  Widget buildMap() {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
          initialCenter: LatLng(latitude, longitude), initialZoom: 9.0),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: "com.app.demo",
        ),
        // replaced with MarkerCLusterLayerWidget
        /*MarkerLayer(
            markers: _markers,
          ),*/

        showReports ? _buildClusterLayer(_markers, Colors.blue) : Container(),
        showSchools
            ? _buildClusterLayer(school_markers, Colors.green)
            : Container(),
        showSunrail
            ? _buildClusterLayer(sunrail_markers, Colors.yellow)
            : Container(),
        showTransit
            ? _buildClusterLayer(transit_markers, Colors.red)
            : Container(),
        showCountyLine
            ? PolygonLayer(
                polygons: counties_polygons,
              )
            : Container(),
        showHurricanes
            ? PolylineLayer(
                polylines: hurricanePolylines,
              )
            : Container(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Search(
          map: buildMap(),
          data: _data,
          onSelect: _showInfoScreen,
          mapContext: context,
          zoomTo: zoomTo),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton(
            heroTag: null,
            onPressed: () {
              _showFilterScreen(context);
            },
            backgroundColor: const Color(0xff242C73),
            child: const Icon(Icons.filter_alt, color: Colors.white),
          ),
          const SizedBox(
            height: 10,
          ),
          FloatingActionButton(
            heroTag: null,
            onPressed: () {
              refreshMap();
            },
            backgroundColor: const Color(0xff242C73),
            child: const Icon(Icons.refresh, color: Colors.white),
          ),
          const SizedBox(
            height: 10,
          ),
          FloatingActionButton(
            heroTag: null,
            backgroundColor: const Color(0xff242C73),
            onPressed: () async {
              pinpointUser();
            },
            child: const Icon(Icons.location_searching_rounded,
                color: Colors.white),
          ),
        ],
      ),
    );
  }

  // handles clustering of points
  MarkerClusterLayerWidget _buildClusterLayer(
      List<Marker> markers, Color color) {
    return MarkerClusterLayerWidget(
        options: MarkerClusterLayerOptions(
            maxClusterRadius: 75,
            size: const Size(40, 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(50),
            markers: markers,
            builder: (context, markers) {
              return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: color,
                  ),
                  child: Text(markers.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        decoration: TextDecoration.none,
                      )));
            }));
  }
  // Hurricane selection dialog (fetchHurdatStormList and fetchHurdatStormPolylines must be implemented elsewhere)
  Future<void> _showHurricaneSelectionDialog() async {
    // TODO: implement fetchHurdatStormList() to get storm IDs/names
    final List<Map<String, dynamic>> storms = await fetchHurdatStormList(); // List<Map<String,dynamic>> with keys 'id','name', etc.
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Hurricanes'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: storms.length,
              itemBuilder: (context, index) {
                final storm = storms[index];
                final id = storm['id']!;
                final name = storm['name']!;
                final selected = selectedHurricanes.contains(id);
                return CheckboxListTile(
                  title: Text(name),
                  subtitle: Text('${storm['startDate']} – ${storm['endDate']}',
                      style: const TextStyle(fontSize: 12)),
                  value: selected,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        selectedHurricanes.add(id);
                      } else {
                        selectedHurricanes.remove(id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
    // After dialog, fetch polylines for selected storms:
    hurricanePolylines = await fetchHurdatStormPolylines(selectedHurricanes);
    setState(() {});
  }
  Future<List<Map<String, dynamic>>> fetchHurdatStormList() async {
    final url = _hurdatUrl;
    debugPrint('Fetching hurricane list from $url');
    final response = await http.get(Uri.parse(url));
    debugPrint('HURDAT2 list response status: ${response.statusCode}');
    final snippet = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
    debugPrint('HURDAT2 list response body snippet: $snippet');
    if (response.statusCode != 200) {
      throw Exception('Failed to load HURDAT2 list: HTTP ${response.statusCode}');
    }
    final lines = response.body.split('\n');
    final storms = <Map<String, dynamic>>[];
    for (var i = 0; i < lines.length; i++) {
      final header = lines[i];
      if (header.trim().isEmpty) continue;
      final headerParts = header.split(',');
      if (headerParts.length >= 3 && RegExp(r'^[A-Z]{2}\d{6}$').hasMatch(headerParts[0].trim())) {
        final id = headerParts[0].trim();
        final stormName = headerParts[1].trim();
        if (stormName.toUpperCase() == 'UNNAMED') continue;
        final obsCount = int.tryParse(headerParts[2].trim()) ?? 0;
        if (obsCount <= 0 || i + obsCount >= lines.length) {
          continue;
        }
        // Parse first observation
        final firstObs = lines[i + 1].split(',');
        final startDateRaw = firstObs[0].trim();
        final startTimeRaw = firstObs[1].trim();
        final startDT = DateTime.parse(
            '${startDateRaw.substring(0,4)}-${startDateRaw.substring(4,6)}-${startDateRaw.substring(6,8)}T${startTimeRaw.substring(0,2)}:${startTimeRaw.substring(2,4)}:00Z')
            .toLocal();
        // Parse last observation
        final lastIndex = i + obsCount;
        final lastObs = lines[lastIndex].split(',');
        final endDateRaw = lastObs[0].trim();
        final endTimeRaw = lastObs[1].trim();
        final endDT = DateTime.parse(
            '${endDateRaw.substring(0,4)}-${endDateRaw.substring(4,6)}-${endDateRaw.substring(6,8)}T${endTimeRaw.substring(0,2)}:${endTimeRaw.substring(2,4)}:00Z')
            .toLocal();
        // Format for display
        final startDisplay = DateFormat.yMMMd().format(startDT);
        final endDisplay = DateFormat.yMMMd().format(endDT);
        storms.add({
          'id': id,
          'name': stormName,
          'startDate': startDisplay,
          'endDate': endDisplay,
          'endDateDT': endDT,
        });
        // Skip observation lines
        i += obsCount;
      }
    }
    // Sort newest (most recent endDT) first
    storms.sort((a, b) => (b['endDateDT'] as DateTime).compareTo(a['endDateDT'] as DateTime));
    return storms;
  }

  Future<List<Polyline>> fetchHurdatStormPolylines(List<String> stormIds) async {
    final url = _hurdatUrl;
    debugPrint('Fetching hurricane tracks from $url for storms: $stormIds');
    final response = await http.get(Uri.parse(url));
    debugPrint('HURDAT2 tracks response status: ${response.statusCode}');
    final polySnippet = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
    debugPrint('HURDAT2 tracks response body snippet: $polySnippet');
    if (response.statusCode != 200) {
      throw Exception('Failed to load HURDAT2 tracks: HTTP ${response.statusCode}');
    }
    final lines = response.body.split('\n');
    final polylines = <Polyline>[];
    for (var i = 0; i < lines.length; i++) {
      final header = lines[i];
      if (header.trim().isEmpty) continue;
      final headerParts = header.split(',');
      final id = headerParts[0].trim();
      if (stormIds.contains(id) && headerParts.length >= 3) {
        final obsCount = int.tryParse(headerParts[2].trim()) ?? 0;
        final points = <LatLng>[];
        for (var j = i + 1; j <= i + obsCount && j < lines.length; j++) {
          final obsParts = lines[j].split(',');
          if (obsParts.length > 5) {
            final latStr = obsParts[4].trim();
            final lonStr = obsParts[5].trim();
            double lat = double.tryParse(latStr.substring(0, latStr.length - 1)) ?? 0;
            if (latStr.endsWith('S')) lat = -lat;
            double lon = double.tryParse(lonStr.substring(0, lonStr.length - 1)) ?? 0;
            if (lonStr.endsWith('W')) lon = -lon;
            points.add(LatLng(lat, lon));
          }
        }
        polylines.add(Polyline(points: points, strokeWidth: 3.0, color: Colors.blue));
        i += obsCount;
      }
    }
    return polylines;
  }
}
