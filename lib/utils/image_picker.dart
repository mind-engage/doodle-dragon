// image_picker.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImagePicker extends StatefulWidget {
  final Function(File) onSelect; // Callback to pass the selected file back
  ImagePicker({Key? key, required this.onSelect}) : super(key: key);

  @override
  _ImagePickerState createState() => _ImagePickerState();
}

class _ImagePickerState extends State<ImagePicker> {
  List<File> images = [];

  @override
  void initState() {
    super.initState();
    _listImages(); // List images when the screen initializes
  }

  Future<void> _listImages() async {
    final directory = await getApplicationDocumentsDirectory();
    final List<File> imageList = Directory(directory.path)
        .listSync() // Sync list of files
        .whereType<File>() // Filter to include only files
        .where((item) => _isImageFile(item.path)) // Check if file is an image
        .toList();
    setState(() {
      images = imageList; // Update the state with the list of images
    });
  }

  bool _isImageFile(String path) {
    // Helper function to determine if a file is an image based on its extension
    final String ext = path.toLowerCase();
    return ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.bmp');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select an Image'),
      ),
      body: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, // Number of columns
          crossAxisSpacing: 4.0, // Horizontal space between items
          mainAxisSpacing: 4.0, // Vertical space between items
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              widget.onSelect(images[index]); // Use the onSelect callback
              Navigator.of(context).pop(); // Close the screen after selection
            },
            child: Image.file(
              images[index],
              fit: BoxFit.cover, // Cover the area without distorting the aspect ratio
            ),
          );
        },
      ),
    );
  }
}
