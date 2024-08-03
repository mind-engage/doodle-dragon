import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON processing
import "log.dart";

class TraceImagePicker extends StatefulWidget {
  final Function(String) onSelect; // Callback to pass the selected image URL back
  String folder;
  TraceImagePicker({Key? key, required this.onSelect, required this.folder}) : super(key: key);

  @override
  _TraceImagePickerState createState() => _TraceImagePickerState();
}

class _TraceImagePickerState extends State<TraceImagePicker> {
  List<String> imageUrls = []; // List to hold image URLs from selected folder
  bool selectingImages = false; // State to toggle between folder and image selection

  @override
  void initState() {
    super.initState();
    _listImages(widget.folder);
  }

  Future<void> _listImages(String selectedFolder) async {
    String apiUrl = selectedFolder;
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        var items = data['items'] as List<dynamic>;
        var urls = items.where((item) => item['contentType'] == 'image/png')
            .map((item) => item['mediaLink'] as String)
            .toList(); // Filter and map only PNG images
        setState(() {
          imageUrls = urls;
          selectingImages = true; // Switch to image selection mode
        });
      } else {
        throw Exception('Failed to load images');
      }
    } catch (e) {
      Log.d('Error fetching images: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select an Image'),
      ),
      body: buildImageGrid(),
    );
  }

  Widget buildImageGrid() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // Number of columns
        crossAxisSpacing: 4.0, // Horizontal space between items
        mainAxisSpacing: 4.0, // Vertical space between items
      ),
      itemCount: imageUrls.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            widget.onSelect(imageUrls[index]); // Use the onSelect callback with the URL
            Navigator.of(context). pop(); // Close the screen after selection
          },
          child: Image.network(
            imageUrls[index],
            fit: BoxFit.cover, // Cover the area without distorting the aspect ratio
          ),
        );
      },
    );
  }
}
