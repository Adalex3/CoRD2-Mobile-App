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
  String get currentUserId => widget.userId ?? "";
  String imageUrl = '';
  List<String> imageUrls = [];
  Reference referenceDirImages = FirebaseStorage.instance.ref().child('images');
  XFile? _imageFile;
  File? _selectedImage;
  final cameraPermission = Permission.camera;
  final locationPermission = Permission.location;
  String? permType;
  late MapController mapController;

  @override
  void initState() {
    mapController = MapController();
    super.initState();
    print(currentUserId);
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
    } else {
      showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Camera Access Denied'),
            content: const Text('Please enable camera access in order to\n'
                'to submit a taken picture. '
                'You may change this later in the app\'s settings.'),
            actions: <Widget> [
              TextButton(
                  onPressed: () {
                    file = null;
                    Navigator.pop(context, 'Cancel');
                  },
                  child: const Text('Cancel')
              ),
              TextButton(
                  onPressed: () {
                    openAppSettings();
                    Navigator.pop(context, 'Ok');
                  },
                  child: const Text('Ok')
              ),
            ],
          )
      );
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
          builder: (context) => chooseLocationModal(context, currentLat, currentLong)
      );
    } else {
      showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Location Access Denied'),
            content: const Text('Please enable location access so we can'
                'get your current location. Otherwise you will need to find'
                'the location on the map from a generic location. You can '
                'change this later in app settings.'),
            actions: <Widget> [
              TextButton(
                  onPressed: () {
                    //currentLat = 28.544331;
                    //currentLong = -81.191931;
                    showModalBottomSheet(
                        context: context,
                        builder: (context) => chooseLocationModal(
                            context, 28.544331, -81.191931
                        )
                    );
                    Navigator.pop(context, 'Cancel');
                  },
                  child: const Text('Cancel')
              ),
              TextButton(
                  onPressed: () {
                    openAppSettings();
                    if (currentLat == 0.0 && currentLong == 0.0) {
                      //currentLat = 28.544331;
                      //currentLong = -81.191931;
                      showModalBottomSheet(
                          context: context,
                          builder: (context) => chooseLocationModal(
                              context, 28.544331, -81.191931
                          )
                      );
                    }
                    Navigator.pop(context, 'Ok');
                  },
                  child: const Text('Ok')
              ),
            ],
          )
      );
    }
  }

  void setError(String msg) {
    setState(() {
      _error = msg;
    });
  }

  // Sets the user's report vals in firebase
  Future submitReport(String userId) async {
    setError("");
    if (descriptionCon.text.isEmpty) {
      setError("Please fill out the description field.");
      return;
    }
    if (titleCon.text.isEmpty) {
      setError("Please add a title.");
      return;
    }
    if(_imageFile == null){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please upload an image!")));
      return;
    }
    if(chooseLat == 0.0 && chooseLng == 0.0){
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Please choose a location for the hazard!")
          )
      );
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
      await _firestore.collection('events').add(submissionData)
          .then((DocumentReference data) async {
        await _firestore.collection('users').doc(userId).update({
          'events': FieldValue.arrayUnion([data.id]),
        });
      });

      print('Submission saved successfully!');
    } catch (e) {
      print('Error saving submission: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return
      Scaffold(
        resizeToAvoidBottomInset: true, // Set this to true
        body: CustomScrollView(
          slivers: [
        // SliverAppBar with fixed "Report" text
        SliverAppBar(
            expandedHeight: 130,
            flexibleSpace: FlexibleSpaceBar(
              title: Padding(
                  padding: EdgeInsets.only(right: 45.0),
  child:Text(
        'Report',
          style: GoogleFonts.jost(
            textStyle: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w400,
              color: Color(0xff060C3E),
            ),
          ),
        //  textAlign: TextAlign.center,
        )),centerTitle: true,),
       // centerTitle: true,
        floating: true,
        pinned: true,
        snap: false,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
    // SliverList for the scrolling content
    SliverList(
    delegate: SliverChildListDelegate(
    [
    // Padding for spacing
    const SizedBox(height: 20),

            Container(
          //    height:600,
              //   height: MediaQuery.of(context).size.height-200,
              padding: const EdgeInsets.only(top: 30, bottom:40),
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
                padding: const EdgeInsets.only(top: 10, left: 25, right: 25),
                   child:
                   Text(
                      'Title',
                     style: GoogleFonts.jost(
                       textStyle: const
                      TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.normal,
                        color: Colors.white,
                      )),
                    )),
                    Padding(
                      padding: const EdgeInsets.only(top: 10, left: 25, right: 25), // Adjust spacing as needed
                      child: Container(
                        height:55,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10), // Set rounded corners
                          color: Colors.white, // Set your desired background color
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10), // Adjust padding as needed
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
                              textStyle: const
                              TextStyle(
                              fontSize: 16, // Set your desired font size for input text
                              color: Colors.black, // Set your desired color for input text
                            )),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.only(top: 25, left: 25, right: 25, bottom:5),
                        child:
                        Text(
                          'Category',
                          style: GoogleFonts.jost(
                              textStyle: const
                              TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              )),
                        )),
                    const SizedBox(height: 10.0),
              Padding(
                padding: const EdgeInsets.only(left: 25, right: 25),
                child:
                    Container(
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10)),
                        height:60,
                        width:400,
                        padding: EdgeInsets.only(right: 10, left: 10),
                        child:
                        DropdownButton<String>(
                          style: const TextStyle(
                              color: Colors.black
                          ),
                          dropdownColor: Colors.white,
                          value: selectedCategory,
                          underline: Container(),
                          icon: Icon(Icons.arrow_drop_down), // Set the default arrow icon
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
                          ]
                              .map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Container( // Wrap the child in a Container
                            decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10), // Set rounded corners
                            color: Colors.white), // Set your desired background color
                            child:
                              Padding(
                                padding: const EdgeInsets.only(left: 5, top:10),
                              child:
                                Text(value,  style: GoogleFonts.jost(
                                textStyle: const
                                TextStyle(fontSize: 22,
                                  fontWeight: FontWeight.normal,
                                  color: Color(0xff060C3E),))),
                            )));
                          }).toList(),
                        ))),
                    const SizedBox(height: 30.0),
              Padding(
                padding: const EdgeInsets.only(left: 25, right: 25),
                     child:
                     Text(
                      'Description',
                        style: GoogleFonts.jost(
                            textStyle: const
                            TextStyle(fontSize: 25,
                              fontWeight: FontWeight.normal,
                              color: Colors.white)))),
              Padding(
                padding: const EdgeInsets.only(left: 20, top:10, right:20),
                child:
                Container(
                height:150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10), // Set rounded corners
                  color: Colors.white, // Set your desired background color
                ),child: Padding(
                padding: const EdgeInsets.only(left: 10), // Adjust padding as needed
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
                      textStyle: const
                      TextStyle(
                        fontSize: 16, // Set your desired font size for input text
                        color: Colors.black, // Set your desired color for input text
                      )),
                ),
              ))),
                    Padding(
                        padding: const EdgeInsets.only(left: 25, top:25, ),
                        child:
                        Text(
                            'Image',
                            style: GoogleFonts.jost(
                                textStyle: const
                                TextStyle(fontSize: 25,
                                    fontWeight: FontWeight.normal,
                                    color: Colors.white,)))),
                    if (_selectedImage != null)
                      GestureDetector(
                        onTap: () {
                          pickImage();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 40, top: 15, bottom: 10),
                          child: Container(
                            width: 330,
                            height: 300,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Image.file(
                              _selectedImage!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ),
                      )
                    else
                GestureDetector(
                  onTap: (){
                    pickImage();
                    },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 40, top:15, bottom:10),
                    child:
                  Container(
                    width: 330,
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:  Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.file_upload,
                          size: 80,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Upload File',
                            style: GoogleFonts.jost(
                                textStyle: const
                                TextStyle(fontSize: 25,
                                    fontWeight: FontWeight.normal,
                                    color: Color(0xff060C3E)))
                        ),
                      ],
                    ),
                  )),
                ),
                SizedBox(height:30),
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
                          minimumSize: MaterialStateProperty.all(Size(200, 50)), // Set the size here
                        ),
                        child:  Text('Choose Location',
                          style: GoogleFonts.jost(
                            textStyle: const
                            TextStyle(fontSize: 20,
                                fontWeight: FontWeight.normal,
                                color: Color(0xff060C3E)))),
                      ),
                    ),
                    SizedBox(height:30),
                    Center(
                      child: ElevatedButton(
                        onPressed: () {
                          descriptionCon.clear();
                          titleCon.clear();
                          selectedCategory == 'Hurricane';
                          submitReport(currentUserId);
                          showDialog(
                              context: context,
                              builder: (BuildContext context) =>
                              AlertDialog(
                            title: TextFormField(
                                decoration: InputDecoration(
                                    labelText: 'Submitted', // Your text
                                    labelStyle: GoogleFonts.jost( // Applying Google Font style
                                      textStyle: TextStyle(
                                        fontSize: 20,
                                        color: Colors.black,
                                      ),
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Color(0xff060C3E), width: 2.0), // Customize underline color
                                    ))),
                            elevation: 10,
                            content: SizedBox(
                              width: 50,
                              child: Text(
                                  "You have successfully submitted a report!",
                                  style: GoogleFonts.jost(
                                      textStyle:
                                      TextStyle(
                                        fontSize: 16, // Set your desired font size for input text
                                        color: Colors.black, // Set your desired color for input text
                                      )
                                  )),
                            ),
                            actions: [
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child:
                                  Text("Ok",
                                      style: GoogleFonts.jost(
                                          textStyle: TextStyle(
                                            fontSize: 15, // Set your desired font size for input text
                                            color: Colors.black, // Set your desired color for input text
                                          ))))
                            ],
                          ));
                        },
                        style: ButtonStyle(
                          minimumSize: MaterialStateProperty.all(Size(200, 50)), // Set the size here
                        ),
                        child:  Text('Submit Report',
                            style: GoogleFonts.jost(
                                textStyle: const
                                TextStyle(fontSize: 20,
                                    fontWeight: FontWeight.normal,
                                    color: Color(0xff060C3E)))),
                      ),
                    ),
            ],
            ),
          ),
        )
    ]
    ),
  )]));
  }

  Widget chooseLocationModal(BuildContext context, var lat, var lng) {
    return SingleChildScrollView(child:Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xff060C3E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
              padding: EdgeInsets.all(15),
              child:  FloatingActionButton(
                backgroundColor: Colors.white,
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Icon(Icons.close),
              )
          ),
          SizedBox(height: 5,),
           Text(
            'Pick a location from the map',
              style: GoogleFonts.jost(
                  textStyle: const
                  TextStyle(fontSize: 25,
                      fontWeight: FontWeight.normal,
                      color: Colors.white))
          ),
          SizedBox(height: 15),
          Container(
            height: MediaQuery.of(context).size.height * 0.4,
            width: MediaQuery.of(context).size.width * 0.8,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                  initialCenter: LatLng(lat, lng),
                  initialZoom: 17.0,
                  onTap: (tapPosition, point) => {
                    print(point.toString()),
                    // create a chooseLat/lng and have setstate set them here
                    // otherwise use user's current location?
                    setState(() {
                      chooseLat = point.latitude;
                      print('CHOSEN LAT: ${chooseLat}');
                      chooseLng = point.longitude;
                      print('CHOSEN LNG: ${chooseLng}');
                      Navigator.pop(context);
                    })
                  }
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

}
