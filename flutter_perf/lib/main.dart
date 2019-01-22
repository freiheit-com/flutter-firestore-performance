import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'dart:isolate';
import 'dart:io';
import 'dart:async';
import 'dart:math';


void main() => runApp(MyApp());

final String _performanceTestCollection = 'perf-test-700TS';
final String _batchCollection = 'perf-test-batches-700TS';
final int maxConcurrencyLoad = 3;

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

void logUpdates(QuerySnapshot snap) {
  print("####logUpdate received " + snap.toString());

  int added = 0;

  for (DocumentChange change in snap.documentChanges) {
    if (change.type == DocumentChangeType.added) {
      added++;
    }
  }

  print("Added: " + added.toString());
}

void listenToFirestoreUpdate(SendPort sendPort) {
  print("starting listening on the firestore");

  var result =
      Firestore().collection(_performanceTestCollection).snapshots().listen(
    logUpdates,
    onError: (e) {
      print("Listen err " + e.toString());
    },
    onDone: () {
      print("Listen done");
    },
  );

  print("started firestore listener " + result.toString());

  print("waiting infinite");
  while (true) {
    //Test!!!!!
    sleep(Duration(seconds: 1));
  }
}

class BatchLoad {
  int batchID;
  DateTime startedTime;

  BatchLoad(this.batchID, this.startedTime);
}



/// SQLite Database handling

Database db;

final String dbName = 'Data';

Future<Database> openArticleDatabase() async {

    var databasePath = await getDatabasesPath();
    String path = join(databasePath, 'data.db');

    return openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
          // When creating the db, create the table
          await db.execute(
              'CREATE TABLE Data (id INT PRIMARY KEY, data TEXT)');
        });
}

/// END SQLite Database
class _StreamMeasureWidgetState extends State<StreamMeasureWidget> {
  int _counter = 0;
  int _stopCount = -1;
  DateTime _stopTime;

  bool initialUpdate = true;
  DateTime startTime;

  String queryResult = "";

  _StreamMeasureWidgetState() {

    openArticleDatabase().then((Database dbInit) {

      print("database initialised");
      db = dbInit;

      Firestore firestore = Firestore();
      firestore.settings(persistenceEnabled: false).then((void v) {
        CollectionReference batchRef = Firestore.instance.collection(_batchCollection);
        CollectionReference docRef = Firestore.instance.collection(_performanceTestCollection);
        startBatchedUpdate(batchRef);
        startBacklogTimer(docRef, batchRef);
      });
    });
  }

  /** async batch load state variables **/
  List<int> backlog = List(); //TODO that should be a queue
  List<BatchLoad> pendingBatchLoads = new List();

  int workedOffBatches = 0;


  void startBatchedUpdate(CollectionReference batchRef) {

    //TODO query batches with stored last timestamp on app-start
    //if batch successfully processed, timestamp is saved (if lower??)

    batchRef.snapshots().listen(loadBatch);
  }


  void loadBatch(QuerySnapshot snap) {
    for (DocumentChange change in snap.documentChanges) {
      if (change.type == DocumentChangeType.added) {
        backlog.add(change.document.data['BatchID']);
      } else {
        //what TODO if backlog entry is deleted (query again to see if data are also deleted)
        //as for now: ignore entry and do nothing
        print("backlog entry " + change.document.data['BatchID'] + "deleted");
      }
    }
  }

  void startBacklogTimer(CollectionReference docRef, CollectionReference batchRef) {
    Timer.periodic(Duration(seconds: 3), (timer){checkBacklog(timer, docRef, batchRef);});
  }

  void checkBacklog(Timer timer, CollectionReference docRef, CollectionReference batchRef) {
    print("checking backlog, length=" + backlog.length.toString() + ", workedOffBatches=" + workedOffBatches.toString());
    if(backlog.length != 0) {
      timer.cancel();

      workOffBacklog(docRef, batchRef);
    }
  }

  void workOffBacklog(CollectionReference docRef, CollectionReference batchRef) {

    print("#### backlog size is: " + backlog.length.toString());

    int loadsToStart = min(backlog.length, maxConcurrencyLoad);
    loadsToStart -= pendingBatchLoads.length;

    print("#### starting " + loadsToStart.toString() + " queries, " + pendingBatchLoads.length.toString() + " already running");

    checkPendingBatchLoads();

    for(int i=0;i<loadsToStart;i++) {
      int batchId = backlog.removeAt(0);

      BatchLoad batchLoad = BatchLoad(batchId, DateTime.now());

      docRef.where('BatchID', isEqualTo: batchId).getDocuments().then((QuerySnapshot snap) {
        handleBatchResult(batchId, snap, docRef, batchRef);
      });
      pendingBatchLoads.add(batchLoad);
    }
  }

  void checkPendingBatchLoads() {

    DateTime maxOldest = DateTime.now().subtract(Duration(seconds: 30));

    Iterable<BatchLoad> tooLongOnes = pendingBatchLoads.where((BatchLoad batchLoad) {
      return batchLoad.startedTime.isBefore(maxOldest);
    });

    if(tooLongOnes.length > 0) {
      print("WARNING, batchLoad pending more than 30 seconds, ids:");
      for(BatchLoad batchLoad in tooLongOnes) {
        print("batchID=" + batchLoad.batchID.toString());
      }
    }
  }

  void remoteBatchLoaded(int batchID) {
    pendingBatchLoads.removeWhere((BatchLoad batchLoad) {return batchLoad.batchID == batchID;});
  }

  void storeBatchInDB(QuerySnapshot snap) {

    Batch batch = db.batch();

    for(DocumentChange change in snap.documentChanges) {
      if(change.type == DocumentChangeType.added) {
        //TODO Do an upsert here, to overwrite old data!!!
        batch.insert(dbName, {'id': change.document.data['DataID'], 'data': change.document.data['Data']});
      }
    }

    batch.commit(noResult: true);
  }

  void handleBatchResult(int batchID, QuerySnapshot snap, CollectionReference docRef, CollectionReference batchRef) {
    remoteBatchLoaded(batchID);
    workedOffBatches += 1;

    storeBatchInDB(snap);

    print("##handleBatchResult, len = " + snap.documents.length.toString() + " batchID=" + batchID.toString());

    updateCounter(snap);
    if(backlog.length > 0) {
      workOffBacklog(docRef, batchRef);
    } else {
      startBacklogTimer(docRef, batchRef);
    }
  }

  void addToCount(int n, bool doSetState) {
    if (_stopCount != -1 && _counter + n >= _stopCount) {
      setState(() {
        _stopTime = DateTime.now();
        _counter += 0;
      });
    }

    if (doSetState) {
      setState(() {
        _counter += n;
      });
    } else {
      _counter += n;
    }
  }

  void updateCounter(QuerySnapshot snap) {
    int added = 0;

    for (DocumentChange change in snap.documentChanges) {
      //TODO Set start time on first non-empty result received
      if (!initialUpdate && startTime == null) {
        startTime = DateTime.now();
      }

      if (change.type == DocumentChangeType.added) {
        added++;
      } else if (change.type == DocumentChangeType.removed) {
        added--;
      }
    }

    if (initialUpdate) {
      print("Initial update done!");
      initialUpdate = false;
      addToCount(added, true);
    } else {
      addToCount(added, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    String startedInfo = "";
    String diffStr = "";

    if (startTime != null && _stopTime != null) {
      startedInfo = "";
      diffStr = "Took: " + _stopTime.difference(startTime).toString();
    } else if (startTime != null) {
      startedInfo = "Measurement running";
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(top: 50.0),
      child: Text(
              'Received this many new documents:',
            )),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.display1,
            ),
            CircularProgressIndicator(),
            Padding(
              padding: EdgeInsets.only(top: 30.0),
              child: Text('Measure until:'),
            ),
            TextFormField(
              initialValue: "-1",
              keyboardType: TextInputType.numberWithOptions(
                  signed: false, decimal: false),
              onFieldSubmitted: (String newVal) {
                setState(() {
                  _stopCount = int.parse(newVal);
                  startTime = null;
                  _stopTime = null;
                });
              },
            ),
            Text(startedInfo),
            Text(diffStr),
            Padding(
              padding: EdgeInsets.only(top: 30.0),
              child: Text('Query ID:'),
            ),

            TextFormField(
              initialValue: "0",
              onFieldSubmitted: (String newVal) {
                int queryId = int.parse(newVal);
                queryDocumentAndShowResult(queryId);
              },
            ),
            Text(queryResult)
          ],
        ),
      );
  }

  void queryDocumentAndShowResult(int queryId) {
    setState(() {
      queryResult = "";
    });
    print("Starting query for id: " + queryId.toString());

    db.query(dbName, where: '"id"=?', whereArgs: [queryId]).then(addQueryResult);

    /*
    Firestore().collection(_performanceTestCollection)
        //.orderBy('DataID', descending: true).limit(1).snapshots().listen(addQueryResult);
        .where('DataID', isEqualTo: queryId).snapshots().listen(addQueryResult);
     */
  }

  void addQueryResult(List<Map<String, dynamic>> queryResultDB) {

    print("received query result " + queryResultDB.toString());

    String result = "";
    for (Map data in queryResultDB) {
      result = result + data.toString() + "\n";
    }
    setState(() {
      queryResult = result;
    });
  }
}

