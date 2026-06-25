#!/bin/bash

aws --endpoint-url=http://localhost:4566 s3 mb s3://test-results
aws --endpoint-url=http://localhost:4566 s3 mb s3://cads-internal-bucket
aws --endpoint-url=http://localhost:4566 s3 mb s3://cads-external-bucket
aws --endpoint-url=http://localhost:4566 sqs create-queue --region $AWS_REGION --queue-name example-queue
aws --endpoint-url=http://localhost:4566 sqs create-queue --region $AWS_REGION --queue-name cads-cds-queue
aws --endpoint-url=http://localhost:4566 sqs create-queue --region $AWS_REGION --queue-name cads-cds-queue-deadletter
aws --endpoint-url=http://localhost:4566 sns create-topic --region $AWS_REGION --name example-topic
