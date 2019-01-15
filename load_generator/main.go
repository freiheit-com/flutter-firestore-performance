package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"

	"cloud.google.com/go/firestore"

	"google.golang.org/api/option"
)

const testCollection = "performance-test"

func main() {

	n := flag.Uint("n", 1, "number of documents to write into the firestore")
	c := flag.Uint("c", 1, "concurrency, number of parallel go routines used to write into the firestore")
	flag.Parse()

	numPerRoutineFrac := float64(*n) / float64(*c)
	numPerRoutine := uint(numPerRoutineFrac)

	client := connectToFirestore()
	defer client.Close()
	col := client.Collection(testCollection)

	var wg sync.WaitGroup
	wg.Add(int(*c))

	numTotal := uint(0)
	for r := uint(0); r < *c; r++ {

		num := numPerRoutine
		if r == (*c)-1 {
			//the last go routine takes the rest
			num = *n - numTotal
		}

		numTotal += num
		go addToFirestore(&wg, col, num)
	}

	fmt.Printf("Waiting for write routines to finish...\n")
	wg.Wait()
	fmt.Printf("Data load generation done\n")
}

func addToFirestore(wg *sync.WaitGroup, col *firestore.CollectionRef, n uint) {
	testData := TestData{
		Type: "test",
		Data: "some test data",
	}

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
	Type string
	Data string
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
