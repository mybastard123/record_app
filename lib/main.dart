import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:screenshot/screenshot.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MainScreen(),
    );
  }
}

class RecordingState {
  static final RecordingState _instance = RecordingState._internal();
  factory RecordingState() => _instance;
  RecordingState._internal();

  bool isRecording = false;
  String recordingStatus = '';
}

class MainScreen extends StatefulWidget {
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final GlobalKey<_ScreenRecordHomeState> _homeKey =
      GlobalKey<_ScreenRecordHomeState>();
  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _pages.add(ScreenRecordHome(key: _homeKey));
    _pages.add(SettingsScreen(
        onShowNotificationBar: _showNotificationBarFromSettings));
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showNotificationBarFromSettings(BuildContext context) {
    _homeKey.currentState?._showNotificationBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification bar shown (Android only)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class ScreenRecordHome extends StatefulWidget {
  const ScreenRecordHome({Key? key}) : super(key: key);
  @override
  State<ScreenRecordHome> createState() => _ScreenRecordHomeState();
}

class _ScreenRecordHomeState extends State<ScreenRecordHome> {
  @override
  void initState() {
    super.initState();
    _requestPermissions();
    platform.setMethodCallHandler(_handleNativeCall);
    // Restore recording state
    _isRecording = RecordingState().isRecording;
    _recordingStatus = RecordingState().recordingStatus;
  }

  Future<void> _showNotificationBar() async {
    if (Platform.isAndroid) {
      try {
        await platform.invokeMethod('showNotificationBar');
      } catch (e) {
        setState(() {
          _recordingStatus = 'Failed to show notification bar: $e';
        });
      }
    }
  }

  Future<void> _hideNotificationBar() async {
    if (Platform.isAndroid) {
      try {
        await platform.invokeMethod('hideNotificationBar');
      } catch (e) {
        setState(() {
          _recordingStatus = 'Failed to hide notification bar: $e';
        });
      }
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onFloatingButtonPressed') {
      // Legacy: Toggle recording
      if (_isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
    } else if (call.method == 'onFloatingButtonStart') {
      if (!_isRecording) {
        await _startRecording();
      }
    } else if (call.method == 'onFloatingButtonStop') {
      if (_isRecording) {
        await _stopRecording();
      }
    } else if (call.method == 'onFloatingButtonScreenshot') {
      await _takeScreenshot();
    }
    // Handle notification bar actions from Android
    if (call.method == 'onNotificationStart') {
      if (!_isRecording) await _startRecording();
    } else if (call.method == 'onNotificationStop') {
      if (_isRecording) await _stopRecording();
    } else if (call.method == 'onNotificationScreenshot') {
      await _takeScreenshot();
    }
    setState(() {
      RecordingState().isRecording = _isRecording;
      RecordingState().recordingStatus = _recordingStatus;
    });
  }

  final MethodChannel platform = const MethodChannel('floating_button_channel');
  bool _isRecording = false;
  String _recordingStatus = '';
  ScreenshotController screenshotController = ScreenshotController();
  bool _isFloatingBarShown = false;

  Future<void> _showFloatingButton() async {
    if (Platform.isAndroid) {
      bool granted = await _checkOverlayPermission();
      if (!granted) {
        await _requestOverlayPermission();
        setState(() {
          _recordingStatus = 'Please grant overlay permission and try again.';
        });
        return;
      }
    }
    try {
      await platform.invokeMethod('showFloatingButton');
    } catch (e) {
      setState(() {
        _recordingStatus = 'Failed to show floating button: $e';
      });
    }
  }

  Future<bool> _checkOverlayPermission() async {
    try {
      final bool granted =
          await platform.invokeMethod('checkOverlayPermission');
      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestOverlayPermission() async {
    try {
      await platform.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<void> _hideFloatingButton() async {
    try {
      await platform.invokeMethod('hideFloatingButton');
    } catch (e) {
      setState(() {
        _recordingStatus = 'Failed to hide floating button: $e';
      });
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.microphone.request();
    await Permission.manageExternalStorage.request();
  }

  Future<void> _startRecording() async {
    String fileName =
        'screen_recording_{DateTime.now().millisecondsSinceEpoch}';
    bool started = await FlutterScreenRecording.startRecordScreen(fileName);
    setState(() {
      _isRecording = started;
      _recordingStatus =
          started ? 'Recording started' : 'Failed to start recording';
      RecordingState().isRecording = _isRecording;
      RecordingState().recordingStatus = _recordingStatus;
    });
  }

  Future<void> _stopRecording() async {
    String path = await FlutterScreenRecording.stopRecordScreen;
    String newPath = path;
    if (Platform.isAndroid) {
      // Move the file to Movies/flutter_screen_record directory for gallery visibility
      final moviesDir =
          Directory('/storage/emulated/0/Movies/flutter_screen_record');
      if (!moviesDir.existsSync()) {
        moviesDir.createSync(recursive: true);
      }
      final fileName =
          'screen_recording_${DateTime.now().millisecondsSinceEpoch}.mp4';
      newPath = p.join(moviesDir.path, fileName);
      try {
        final oldFile = File(path);
        await oldFile.copy(newPath);
        await oldFile.delete();
        // Trigger media scan
        await platform.invokeMethod(
            'scanFile', {'path': newPath, 'mimeType': 'video/mp4'});
      } catch (e) {
        // If move fails, keep original path
        newPath = path;
      }
    }
    setState(() {
      _isRecording = false;
      _recordingStatus = 'Recording saved: $newPath';
      RecordingState().isRecording = _isRecording;
      RecordingState().recordingStatus = _recordingStatus;
    });
  }

  Future<void> _takeScreenshot() async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = Directory('/storage/emulated/0/Pictures');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    final fileName = 'screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
    final path = p.join(directory.path, fileName);
    final image = await screenshotController.capture();
    if (image != null) {
      final file = File(path);
      await file.writeAsBytes(image);
      if (Platform.isAndroid) {
        // Trigger media scan so it appears in gallery
        final result = await platform
            .invokeMethod('scanFile', {'path': path, 'mimeType': 'image/png'});
      }
      setState(() {
        _recordingStatus = 'Screenshot saved: $path';
      });
    } else {
      setState(() {
        _recordingStatus = 'Failed to take screenshot';
      });
    }
  }

  Future<void> _toggleFloatingButton() async {
    if (_isFloatingBarShown) {
      await _hideFloatingButton();
      setState(() {
        _isFloatingBarShown = false;
      });
    } else {
      await _showFloatingButton();
      setState(() {
        _isFloatingBarShown = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Screenshot(
      controller: screenshotController,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Screen Record & Screenshot'),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  elevation: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    child: Column(
                      children: [
                        Icon(
                          _isRecording
                              ? Icons.fiber_manual_record
                              : Icons.fiber_smart_record,
                          color: _isRecording ? Colors.red : Colors.black87,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isRecording ? 'Recording...' : 'Ready to Record',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                              onPressed: _isRecording ? null : _startRecording,
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: const Text('Start'),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                              onPressed: _isRecording ? _stopRecording : null,
                              icon: const Icon(Icons.stop, size: 20),
                              label: const Text('Stop'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onPressed: _takeScreenshot,
                          icon: const Icon(Icons.camera_alt, size: 20),
                          label: const Text('Take Screenshot'),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.deepPurple),
                            foregroundColor: Colors.deepPurple,
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onPressed: _toggleFloatingButton,
                          icon: Icon(
                              _isFloatingBarShown
                                  ? Icons.close
                                  : Icons.open_in_new,
                              size: 20),
                          label: Text(_isFloatingBarShown
                              ? 'Hide Floating Bar'
                              : 'Show Floating Bar'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red[50] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isRecording
                            ? Icons.fiber_manual_record
                            : Icons.info_outline,
                        color: _isRecording ? Colors.red : Colors.deepPurple,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _recordingStatus,
                          style: TextStyle(
                            color: _isRecording ? Colors.red : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _takeScreenshot,
          backgroundColor: Colors.blueAccent,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Screenshot'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final void Function(BuildContext context)? onShowNotificationBar;
  const SettingsScreen({Key? key, this.onShowNotificationBar})
      : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _outputDir;

  @override
  void initState() {
    super.initState();
    _loadOutputDir();
  }

  Future<void> _loadOutputDir() async {
    // Load from persistent storage if needed
    setState(() {
      _outputDir = null;
    });
  }

  Future<void> _pickOutputDir() async {
    String? selectedDir = await FilePicker.platform.getDirectoryPath();
    if (selectedDir != null) {
      setState(() {
        _outputDir = selectedDir;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                elevation: 8,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.folder,
                              color: Colors.deepPurple, size: 32),
                          SizedBox(width: 12),
                          Text(
                            'Output Directory',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _outputDir ??
                              'Default (Movies/flutter_screen_record)',
                          style: const TextStyle(
                              fontSize: 15, color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                        onPressed: _pickOutputDir,
                        icon: const Icon(Icons.edit_location_alt, size: 20),
                        label: const Text('Change Output Directory'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                elevation: 6,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.grey[50],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.notifications_active,
                              color: Colors.blueAccent, size: 28),
                          const SizedBox(width: 10),
                          const Text(
                            'Notification Bar Controls',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.blueAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                        onPressed: () {
                          if (widget.onShowNotificationBar != null) {
                            widget.onShowNotificationBar!(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Notification bar not available.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.notifications, size: 20),
                        label: const Text('Show Notification Controls'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
