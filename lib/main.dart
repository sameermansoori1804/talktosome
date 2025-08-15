import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'call_screen.dart';
import 'webrtc_provider.dart';


void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => WebRTCProvider(),
      child: MaterialApp(
        home: CallScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CallScreen(),
    );
  }
}