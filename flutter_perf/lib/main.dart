import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() => runApp(MyApp());

final String _performanceTestCollection = 'performance-test';

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Perf',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: StreamMeasureWidget(title: 'Flutter Sync Performance'),
    );
  }
}

class StreamMeasureWidget extends StatefulWidget {
  StreamMeasureWidget({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _StreamMeasureWidgetState createState() => _StreamMeasureWidgetState();
}

class _StreamMeasureWidgetState extends State<StreamMeasureWidget> {
  int _counter = 0;

  _StreamMeasureWidgetState() {
    Firestore.instance
        .collection(_performanceTestCollection)
        .snapshots()
        .listen(updateCounter);
  }

  void addToCount(int n) {
    setState(() {
      _counter += n;
    });
  }

  void updateCounter(QuerySnapshot snap) {
    int added = 0;

    for (DocumentChange change in snap.documentChanges) {
      if (change.type == DocumentChangeType.added) {
        added++;
      }
    }

    addToCount(added);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(

        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Received this many new documents:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.display1,
            ),
          ],
        ),
      ),
    );
  }
}