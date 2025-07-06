import 'package:cord2_mobile_app/classes/analytics.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
//import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
//import 'firebase_options.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class ReportForm extends StatefulWidget {
  String? userId; // Add a variable to hold the additional String?

  ReportForm({required this.userId});
  //const ReportForm({super.key});
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AnalyticsService analytics = AnalyticsService();
  String get currentUserId => widget.userId ?? "";
  String imageUrl = '';
  List<String> imageUrls = [];
  Reference referenceDirImages = FirebaseStorage.instance.ref().child('images');
  XFile? _imageFile;
  File? _selectedImage;
  final cameraPermission = Permission.camera;
  final locationPermission = Permission.location;
  String? permType;
  String error = "";
  late MapController mapController;

  @override
  void initState() {
    mapController = MapController();
    super.initState();
    print(currentUserId);
    analytics.logScreenBrowsing("Report Form");
  }

  TextEditingController descriptionCon = TextEditingController();
  TextEditingController titleCon = TextEditingController();
  String selectedCategory = 'Hurricane';
  String _error = "";
  var chooseLat = 0.0;
  var chooseLng = 0.0;

  // takes in type of permission need/want
  // returns true/false if have/need perm
  Future<bool> checkPerms(String permType) async {
    if (permType == null) {
      print('forgot to specify perm type wanted ie.) camera, location, etc');
      return false;
    }
    if (permType == 'camera') {
      // logic for camera permission here
      final status = await Permission.camera.request();

      if (status.isGranted) {
        return true;
      }
    }
    if (permType == 'location') {
      final status = await locationPermission.request();

      if (status.isGranted) {
        return true;
      }
    }

    return false;
  }

  Future<void> pickImage() async {
    ImagePicker picker = ImagePicker();
    bool permResult = await checkPerms('camera');
    XFile? file;

    if (permResult == true) {
      file = await picker.pickImage(
        source: ImageSource.camera,
        maxHeight: 640,
        maxWidth: 640,
        imageQuality: 50,
      );
      showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
                title: TextFormField(
                    decoration: InputDecoration(
                        labelText: 'Image Selected', // Your text
                        labelStyle: GoogleFonts.jost(
                          // Applying Google Font style
                          textStyle: TextStyle(
                            fontSize: 20,
                            color: Colors.black,
                          ),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Color(0xff060C3E),
                              width: 2.0), // Customize underline color
                        ))),
                elevation: 10,
                content: SizedBox(
                  width: 50,
                  child: Text("You have successfully selected an image.",
                      style: GoogleFonts.jost(
                          textStyle: TextStyle(
                        fontSize:
                            16, // Set your desired font size for input text
                        color: Colors
                            .black, // Set your desired color for input text
                      ))),
                ),
                actions: [
                  ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("Ok",
                          style: GoogleFonts.jost(
                              textStyle: TextStyle(
                            fontSize:
                                15, // Set your desired font size for input text
                            color: Colors
                                .black, // Set your desired color for input text
                          ))))
                ],
              ));
    } else {
      showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
                title: const Text('Camera Access Denied'),
                content: const Text('Please enable camera access in order to\n'
                    'to submit a taken picture. '
                    'You may change this later in the app\'s settings.'),
                actions: <Widget>[
                  TextButton(
                      onPressed: () {
                        file = null;
                        Navigator.pop(context, 'Cancel');
                      },
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () {
                        openAppSettings();
                        Navigator.pop(context, 'Ok');
                      },
                      child: const Text('Ok')),
                ],
              ));
      if (file != null) {
        setState(() {
          _selectedImage = File(file!.path); // Store the selected image
        });
      }
    }

    //XFile? file = await picker.pickImage(source: ImageSource.camera);

    if (file == null) {
      return;
    } else {
      setState(() {
        _imageFile = file;
      });
    }
  }

  Future<void> pickLocation() async {
    bool permResult = await checkPerms('location');
    var currentLat = 0.0;
    var currentLong = 0.0;
    if (permResult == true) {
      final position = await Geolocator.getCurrentPosition();
      currentLat = position.latitude;
      currentLong = position.longitude;
      showModalBottomSheet(
        context: context,
        builder: (context) =>
            chooseLocationModal(context, currentLat, currentLong, permResult),
      );
    } else {
      final rootContext = context;
      showDialog(
        context: rootContext,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Location Access Denied'),
          content: const Text('Please enable location access so we can '
              'get your current location. Otherwise you will need to find '
              'the location on the map from a generic location. You can '
              'change this later in app settings.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                showModalBottomSheet(
                  context: rootContext,
                  // default location is the center of UCF
                  builder: (_) => chooseLocationModal(rootContext, 28.602979238181945, -81.20011495430661, permResult),
                );
              },
              child: const Text('Ignore'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                openAppSettings();
                if (currentLat == 0.0 && currentLong == 0.0) {
                  showModalBottomSheet(
                    context: rootContext,
                    builder: (_) => chooseLocationModal(rootContext, 28.602979238181945, -81.20011495430661, permResult),
                  );
                }
              },
              child: const Text('Settings'),
            ),
          ],
        ),
      );
    }
  }

  void setError(String msg) {
    setState(() {
      error = msg;
    });
  }

  // Sets the user's report vals in firebase
  Future submitReport(String userId) async {
    setError("");
    if (titleCon.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Please add a title!")));
      return;
    }

    if (descriptionCon.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Please add a description!")));
      return;
    }

    if (_imageFile == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Please upload an image!")));
      return;
    }

    if (chooseLat == 0.0 && chooseLng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please choose a location for the hazard!")));
      return;
    }

    String uniqueFileName = DateTime.now().millisecondsSinceEpoch.toString();
    Reference referenceImageToUpload = referenceDirImages.child(uniqueFileName);

    try {
      File imageFile = File(_imageFile!.path);
      await referenceImageToUpload.putFile(imageFile);
      imageUrl = await referenceImageToUpload.getDownloadURL();
      print('Uploaded image URL: $imageUrl');
    } catch (error) {
      print('Error: $error');
    }

    imageUrls.add(imageUrl);

    Map<String, dynamic> submissionData = {
      'description': descriptionCon.text,
      'creator': userId,
      'images': imageUrls,
      'title': titleCon.text,
      'eventType': selectedCategory,
      'latitude': chooseLat,
      'longitude': chooseLng,
      'time': DateTime.now(),
      'active': true
    };

    try {
      // await _firestore.collection('users').doc(userId).update({
      //   'events': FieldValue.arrayUnion([submissionData]),
      // });
      await _firestore
          .collection('events')
          .add(submissionData)
          .then((DocumentReference data) async {
        await _firestore.collection('users').doc(userId).update({
          'events': FieldValue.arrayUnion([data.id]),
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Submission saved successfully!")));
      analytics.logReportSubmitted();
      descriptionCon.clear();
      titleCon.clear();
      setState(() {
        selectedCategory = 'Hurricane';
        _imageFile = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("There was an error saving the submission: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: true, // Set this to true
        body: CustomScrollView(slivers: [
          // SliverAppBar with fixed "Report" text
          SliverAppBar(
            expandedHeight: 130,
            flexibleSpace: FlexibleSpaceBar(
              title: Padding(
                  padding: EdgeInsets.only(right: 45.0),
                  child: Text(
                    'Report',
                    style: GoogleFonts.jost(
                      textStyle: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w400,
                        color: Color(0xff060C3E),
                      ),
                    ),
                    //  textAlign: TextAlign.center,
                  )),
              centerTitle: true,
            ),
            // centerTitle: true,
            floating: true,
            pinned: true,
            snap: false,
            backgroundColor: Colors.white,
            elevation: 0,
          ),
          // SliverList for the scrolling content
          SliverList(
            delegate: SliverChildListDelegate([
              // Padding for spacing
              const SizedBox(height: 20),

              Container(
                //    height:600,
                //   height: MediaQuery.of(context).size.height-200,
                padding: const EdgeInsets.only(top: 30, bottom: 40),
                decoration: const BoxDecoration(
                  color: Color(0xff060C3E),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30.0),
                    topRight: Radius.circular(30.0),
                  ),
                ),
                //  width: double.infinity,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                          padding: const EdgeInsets.only(
                              top: 10, left: 25, right: 25),
                          child: Text(
                            'Title',
                            style: GoogleFonts.jost(
                                textStyle: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.normal,
                              color: Colors.white,
                            )),
                          )),
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 10,
                            left: 25,
                            right: 25), // Adjust spacing as needed
                        child: Container(
                          height: 55,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                10), // Set rounded corners
                            color: Colors
                                .white, // Set your desired background color
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(
                                left: 10), // Adjust padding as needed
                            child: TextField(
                              controller: titleCon,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Add a title',
                                hintStyle: TextStyle(
                                  fontSize: 22,
                                  color: Colors.grey,
                                ),
                              ),
                              style: GoogleFonts.jost(
                                  textStyle: const TextStyle(
                                fontSize:
                                    16, // Set your desired font size for input text
                                color: Colors
                                    .black, // Set your desired color for input text
                              )),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                          padding: const EdgeInsets.only(
                              top: 25, left: 25, right: 25, bottom: 5),
                          child: Text(
                            'Category',
                            style: GoogleFonts.jost(
                                textStyle: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.normal,
                              color: Colors.white,
                            )),
                          )),
                      const SizedBox(height: 10.0),
                      Padding(
                          padding: const EdgeInsets.only(left: 25, right: 25),
                          child: Container(
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10)),
                              height: 60,
                              width: 400,
                              padding: EdgeInsets.only(right: 10, left: 10),
                              child: DropdownButton<String>(
                                style: const TextStyle(color: Colors.black),
                                dropdownColor: Colors.white,
                                value: selectedCategory,
                                underline: Container(),
                                icon: Icon(Icons
                                    .arrow_drop_down), // Set the default arrow icon
                                iconSize: 35, // Set the size of the icon
                                isExpanded: true,
                                onChanged: (String? newValue) {
                                  setState(() {
                                    selectedCategory = newValue!;
                                  });
                                },
                                items: <String>[
                                  'Hurricane',
                                  'Earthquake',
                                  'Tornado',
                                  'Wildfire',
                                  'Other'
                                ].map<DropdownMenuItem<String>>((String value) {
                                  return DropdownMenuItem<String>(
                                      value: value,
                                      child: Container(
                                          // Wrap the child in a Container
                                          decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      10), // Set rounded corners
                                              color: Colors
                                                  .white), // Set your desired background color
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                left: 5, top: 10),
                                            child: Text(value,
                                                style: GoogleFonts.jost(
                                                    textStyle: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.normal,
                                                  color: Color(0xff060C3E),
                                                ))),
                                          )));
                                }).toList(),
                              ))),
                      const SizedBox(height: 30.0),
                      Padding(
                          padding: const EdgeInsets.only(left: 25, right: 25),
                          child: Text('Description',
                              style: GoogleFonts.jost(
                                  textStyle: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.white)))),
                      Padding(
                          padding: const EdgeInsets.only(
                              left: 20, top: 10, right: 20),
                          child: Container(
                              height: 150,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                    10), // Set rounded corners
                                color: Colors
                                    .white, // Set your desired background color
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    left: 10), // Adjust padding as needed
                                child: TextField(
                                  controller: descriptionCon,
                                  maxLines: null,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Please write a description.',
                                    hintStyle: TextStyle(
                                      fontSize: 20,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  style: GoogleFonts.jost(
                                      textStyle: const TextStyle(
                                    fontSize:
                                        16, // Set your desired font size for input text
                                    color: Colors
                                        .black, // Set your desired color for input text
                                  )),
                                ),
                              ))),
                      Padding(
                          padding: const EdgeInsets.only(
                            left: 25,
                            top: 25,
                          ),
                          child: Text('Image',
                              style: GoogleFonts.jost(
                                  textStyle: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              )))),
                      GestureDetector(
                        onTap: () {
                          pickImage();
                        },
                        child: Padding(
                            padding: const EdgeInsets.only(
                                left: 40, right: 40, top: 15, bottom: 10),
                            child: Container(
                                width: 330,
                                height: 300,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: _imageFile != null
                                    ? Image.file(File(_imageFile!.path))
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.file_upload,
                                            size: 80,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(height: 10),
                                          Text('Upload File',
                                              style: GoogleFonts.jost(
                                                  textStyle: const TextStyle(
                                                      fontSize: 25,
                                                      fontWeight:
                                                          FontWeight.normal,
                                                      color:
                                                          Color(0xff060C3E)))),
                                        ],
                                      ))),
                      ),
                      SizedBox(height: 30),
                      Center(
                        child: ElevatedButton(
                          onPressed: () {
                            /*showModalBottomSheet(
          context: context,
          builder: (context) => buildMapModal(context)
      );*/
                            pickLocation();
                          },
                          style: ButtonStyle(
                            minimumSize: MaterialStateProperty.all(
                                Size(200, 50)), // Set the size here
                          ),
                          child: Text('Choose Location',
                              style: GoogleFonts.jost(
                                  textStyle: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.normal,
                                      color: Color(0xff060C3E)))),
                        ),
                      ),
                      SizedBox(height: 30),
                      Center(
                        child: ElevatedButton(
                          onPressed: () {
                            submitReport(currentUserId);
                            if (error.isNotEmpty) {
                              showDialog(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      AlertDialog(
                                        title:
                                            Text('Report Status', // Your text
                                                style: GoogleFonts.jost(
                                                  // Applying Google Font style
                                                  textStyle: TextStyle(
                                                    decoration: TextDecoration
                                                        .underline,
                                                    fontSize: 20,
                                                    color: Colors.black,
                                                  ),
                                                )),
                                        // Customize underline color

                                        elevation: 10,
                                        content: SizedBox(
                                          width: 50,
                                          child: Text(error,
                                              style: GoogleFonts.jost(
                                                  textStyle: TextStyle(
                                                fontSize:
                                                    16, // Set your desired font size for input text
                                                color: Colors
                                                    .black, // Set your desired color for input text
                                              ))),
                                        ),
                                        actions: [
                                          ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: Text("Ok",
                                                  style: GoogleFonts.jost(
                                                      textStyle: TextStyle(
                                                    fontSize:
                                                        15, // Set your desired font size for input text
                                                    color: Colors
                                                        .black, // Set your desired color for input text
                                                  ))))
                                        ],
                                      ));
                            }
                          },
                          style: ButtonStyle(
                            minimumSize: MaterialStateProperty.all(
                                Size(200, 50)), // Set the size here
                          ),
                          child: Text('Submit Report',
                              style: GoogleFonts.jost(
                                  textStyle: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.normal,
                                      color: Color(0xff060C3E)))),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            ]),
          )
        ]));
  }

  Widget chooseLocationModal(BuildContext context, double lat, double lng, bool hasLocationPermission) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xff060C3E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search location',
                prefixIcon: Icon(Icons.search, color: Colors.white),
                hintStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Color(0xff172A5E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: TextStyle(color: Colors.white),
              onSubmitted: (query) async {
                try {
                  List<Location> results = await locationFromAddress(query);
                  if (results.isNotEmpty) {
                    final loc = results.first;
                    mapController.move(LatLng(loc.latitude, loc.longitude), 15.0);
                  }
                } catch (e) {
                  // optionally show error
                }
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    center: LatLng(lat, lng),
                    zoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                  ],
                ),
                Center(
                  child: Icon(Icons.location_pin, size: 50, color: Colors.redAccent),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    icon: Icon(Icons.my_location),
                    color: hasLocationPermission ? Colors.black : Colors.grey,
                    onPressed: hasLocationPermission
                        ? () async {
                            final pos = await Geolocator.getCurrentPosition();
                            mapController.move(LatLng(pos.latitude, pos.longitude), 17.0);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton(
              onPressed: () {
                final center = mapController.center;
                setState(() {
                  chooseLat = center.latitude;
                  chooseLng = center.longitude;
                  print("chooseLat: ${chooseLat})");
                  print("chooseLong: ${chooseLng})");
                });
                Navigator.pop(context);
              },
              child: Text('Save Location'),
              style: ButtonStyle(
                minimumSize: MaterialStateProperty.all(Size(double.infinity, 48)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> getImageURL() async {
    // Retrieve the download URL of the image from Firebase Storage
    String uniqueFileName = DateTime.now().millisecondsSinceEpoch.toString();
    Reference referenceImageToUpload = referenceDirImages.child(uniqueFileName);
    try {
      File imageFile = File(_imageFile!.path);
      await referenceImageToUpload.putFile(imageFile);
      imageUrl = await referenceImageToUpload.getDownloadURL();
      print('Uploaded image URL: $imageUrl');
    } catch (error) {
      print('Error: $error');
    }

    imageUrls.add(imageUrl);
  }
}
