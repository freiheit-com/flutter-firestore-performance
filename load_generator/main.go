package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"cloud.google.com/go/firestore"

	"google.golang.org/api/option"
)

const testCollection = "perf-test4"
const batchCollection = "perf-test-batches4"

func main() {

	n := flag.Uint("n", 1, "number of documents to write into the firestore")
	c := flag.Uint("c", 1, "concurrency, number of parallel go routines used to write into the firestore")
	d := flag.Uint("numBytes", 50, "number of bytes stored in firebase")
	flag.Parse()

	numPerRoutineFrac := float64(*n) / float64(*c)
	numPerRoutine := uint(numPerRoutineFrac)

	client := connectToFirestore()
	defer client.Close()
	col := client.Collection(testCollection)
	batchCol := client.Collection(batchCollection)

	var wg sync.WaitGroup
	wg.Add(int(*c))

	var counter int64 = 0

	startTime := time.Now()
	numTotal := uint(0)
	for r := uint(0); r < *c; r++ {

		num := numPerRoutine
		if r == (*c)-1 {
			//the last go routine takes the rest
			num = *n - numTotal
		}

		numTotal += num
		//go addToFirestore(testData, &wg, col, num)
		go addBatchedToFirestore(int(*d), &counter, client, &wg, col, batchCol, num)
	}

	fmt.Printf("Waiting for write routines to finish...\n")
	wg.Wait()
	endTime := time.Now()

	tookTime := endTime.Sub(startTime)

	fmt.Printf("Data load generation done\n")
	fmt.Printf("Took: %s \n", tookTime)
}

func addBatchedToFirestore(numBytes int, counter *int64, client *firestore.Client, wg *sync.WaitGroup, col *firestore.CollectionRef,
	batchCol *firestore.CollectionRef, n uint) {
	batch := client.Batch()

	batchCount := 0
	batchID := time.Now().UnixNano()
	for i := uint(0); i < n; i++ {

		testData := createTestData(numBytes, atomic.AddInt64(counter, 1), batchID)

		doc := col.NewDoc()
		_ = batch.Create(doc, &testData)
		batchCount++

		if batchCount == 500 {
			commitBatch(batch)
			_, _, err := batchCol.Add(context.Background(), BatchInfo{BatchID: batchID})
			if err != nil {
				log.Printf("Error adding batch info %#v\n", err)
			}
			batch = client.Batch()
			batchCount = 0
			batchID = time.Now().UnixNano()
		}
	}

	if batchCount > 0 {
		commitBatch(batch)
		_, _, err := batchCol.Add(context.Background(), BatchInfo{BatchID: batchID})
		if err != nil {
			log.Printf("Error adding batch info %#v\n", err)
		}
	}

	wg.Done()
}

func commitBatch(batch *firestore.WriteBatch) {
	_, err := batch.Commit(context.Background())
	if err != nil {
		log.Printf("Batch commit failed: %#v\n", err)
	}
}

func addToFirestore(testData *TestData, wg *sync.WaitGroup, col *firestore.CollectionRef, n uint) {
	for i := uint(0); i < n; i++ {
		_, _, err := col.Add(context.Background(), testData)
		if err != nil {
			log.Printf("Error adding document %#v\n", err)
		}
	}

	wg.Done()
}

//TestData dummy data
type TestData struct {
	Type    string
	Data    string
	DataID  int64
	BatchID int64
}

//BatchInfo data
type BatchInfo struct {
	BatchID int64
}

func createTestData(numBytes int, id int64, batchID int64) *TestData {
	data := strings.Repeat("a", numBytes)
	testData := TestData{
		Type:    "test",
		Data:    data,
		DataID:  id,
		BatchID: batchID,
	}
	return &testData
}

func connectToFirestore() *firestore.Client {

	firebaseProjectID := os.Getenv("FIREBASE_PROJECT_ID")
	if firebaseProjectID == "" {
		panic("FIREBASE_PROJECT_ID not set")
	}

	firebaseServiceAccountJSON := os.Getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
	if strings.Trim(firebaseServiceAccountJSON, " ") == "" {
		panic("FIREBASE_SERVICE_ACCOUNT_JSON not set")
	}

	opt := option.WithCredentialsJSON([]byte(firebaseServiceAccountJSON))
	client, err := firestore.NewClient(context.Background(), firebaseProjectID, opt)
	if err != nil {
		panic(fmt.Sprintf("Firestore client setup failed: %#v", err))
	}

	return client
}
