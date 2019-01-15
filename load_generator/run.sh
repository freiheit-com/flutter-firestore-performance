#!/bin/bash
export FIREBASE_PROJECT_ID=edeka-mango
export FIREBASE_SERVICE_ACCOUNT_JSON=`cat ~/.secrets/edeka-mango-firebase-adminsdk.json`
go run main.go "$@"
