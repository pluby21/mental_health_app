import 'package:collection/collection.dart' show IterableExtension;
import 'package:contacts_app/app-contact.class.dart';
import 'package:contacts_app/components/contacts-list.dart'; //what is this package
import 'package:contacts_service/contacts_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_sms/flutter_sms.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Contacts',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Contacts'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<AppContact> contacts = [];
  List<AppContact> contactsFiltered = []; //
  Map<String, Color> contactsColorMap = new Map(); //
  TextEditingController searchController = new TextEditingController(); //
  bool contactsLoaded = false;
  String _latitude = '';
  String _longitude = '';
  String _address = '';

  @override
  void initState() {
    super.initState();
    getPermissions();
  }

  getPermissions() async {
    if (await Permission.contacts.request().isGranted) {
      getAllContacts();
      searchController.addListener(() {
        filterContacts();
      });
    }
  }

  String flattenPhoneNumber(String phoneStr) {
    return phoneStr.replaceAllMapped(RegExp(r'^(\+)|\D'), (Match m) {
      return m[0] == "+" ? "+" : "";
    });
  }

  getAllContacts() async {
    List colors = [
      Colors.green,
      Colors.indigo,
      Colors.yellow,
      Colors.orange
    ];
    int colorIndex = 0;
    List<AppContact> _contacts = (await ContactsService.getContacts()).map((contact) {
      Color? baseColor = colors[colorIndex];
      colorIndex++;
      if (colorIndex == colors.length) {
        colorIndex = 0;
      }
      return new AppContact(info: contact, color: baseColor);
    }).toList();
    setState(() {
      contacts = _contacts;
      contactsLoaded = true;
    });
  }

  filterContacts() {
    List<AppContact> _contacts = [];
    _contacts.addAll(contacts);
    if (searchController.text.isNotEmpty) {
      _contacts.retainWhere((contact) {
        String searchTerm = searchController.text.toLowerCase();
        String searchTermFlatten = flattenPhoneNumber(searchTerm);
        String contactName = contact.info!.displayName!.toLowerCase();
        bool nameMatches = contactName.contains(searchTerm);
        if (nameMatches == true) {
          return true;
        }

        if (searchTermFlatten.isEmpty) {
          return false;
        }

        var phone = contact.info!.phones?.firstWhereOrNull((phn) {
          String phnFlattened = flattenPhoneNumber(phn.value!);
          return phnFlattened.contains(searchTermFlatten);
        });

        return phone != null;
      });
    }
    setState(() {
      contactsFiltered = _contacts;
    });
  }

  /// Determine the current position of the device.
  ///
  /// When the location services are not enabled or permissions
  /// are denied the `Future` will return an error.
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _updatePosition() async {
    Position position = await _determinePosition();
    List positions = await placemarkFromCoordinates(
        position.latitude, position.longitude);
    setState(() {
      _latitude = position.latitude.toString();
      _longitude = position.longitude.toString();
      _address = positions[0].toString();
    });
  }

  void _sendSMS(String message, List<String> recipents) async {
    String _result = await sendSMS(message: message, recipients: recipents)
        .catchError((onError) {
      print(onError);
    });
    print(_result);
  }

  @override
  Widget build(BuildContext context) {
    bool isSearching = searchController.text.isNotEmpty;
    bool listItemsExist = (
        (isSearching == true && contactsFiltered.isNotEmpty) ||
        (isSearching != true && contacts.isNotEmpty)
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title!),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        backgroundColor: Theme.of(context).primaryColorDark,
        onPressed: () async {
          try {
           await ContactsService.openContactForm();
           getAllContacts();
          } on FormOperationException catch (e) { //on keyword
            switch(e.errorCode) {
              case FormOperationErrorCode.FORM_OPERATION_CANCELED:
              case FormOperationErrorCode.FORM_COULD_NOT_BE_OPEN:
              case FormOperationErrorCode.FORM_OPERATION_UNKNOWN_ERROR:
                print(e.toString());
            }
          }
        },
      ),
      body: Container(
        padding: EdgeInsets.all(20),
        child: Column(

          children:

          <Widget>[

            Container(
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search',
                  border: new OutlineInputBorder(
                    borderSide: new BorderSide(
                      color: Theme.of(context).primaryColor
                    )
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).primaryColor
                  )
                ),
              ),
            ),
            contactsLoaded == true ?  // if the contacts have not been loaded yet
              listItemsExist == true ?  // if we have contacts to show
              ContactsList(
                reloadContacts: () {
                  getAllContacts();
                },
                contacts: isSearching == true ? contactsFiltered : contacts,
              ) : Container(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  isSearching ?'No search results to show' : 'No contacts exist',
                  style: TextStyle(color: Colors.grey, fontSize: 20),
                )
              ) :
            Container(  // still loading contacts
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),

            FloatingActionButton(
              tooltip: 'Share location.',
              child: const Icon(Icons.change_circle_outlined),
              onPressed: () async {
                _updatePosition;
                _sendSMS('Can you meet me at https://www.google.com/maps/search/?api=1&query=${_latitude},${_longitude}? It\'s an emergency.', ['8047730608']);
              }),
          ],
        ),
      ),
    );
  }
}
