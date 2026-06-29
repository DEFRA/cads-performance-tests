#!/bin/sh
set -x

echo "run_id: $RUN_ID in $ENVIRONMENT"

NOW=$(date +"%Y%m%d-%H%M%S")

if [ -z "${JM_HOME}" ]; then
  JM_HOME=/opt/perftest
fi

JM_SCENARIOS=${JM_HOME}/scenarios
JM_REPORTS=${JM_HOME}/reports
JM_LOGS=${JM_HOME}/logs
JM_HTML_OUTPUT=/tmp/jmeter-html-${NOW}

mkdir -p ${JM_REPORTS} ${JM_LOGS} ${JM_HTML_OUTPUT}

TEST_SCENARIO=${TEST_SCENARIO:-test}
SCENARIOFILE=${JM_SCENARIOS}/${TEST_SCENARIO}.jmx
REPORTFILE=${NOW}-perftest-${TEST_SCENARIO}-report.csv
LOGFILE=${JM_LOGS}/perftest-${TEST_SCENARIO}.log

# Before running the suite, replace 'service-name' with the name/url of the service to test.
# ENVIRONMENT is set to the name of th environment the test is running in.
SERVICE_ENDPOINT=${SERVICE_ENDPOINT:-cads-data-service.${ENVIRONMENT}.cdp-int.defra.cloud}
# PORT is used to set the port of this performance test container
SERVICE_PORT=${SERVICE_PORT:-443}
SERVICE_URL_SCHEME=${SERVICE_URL_SCHEME:-https}

# Run the test suite. Write HTML report to a temp dir because the mounted
# reports volume may contain files from a previous run.
JMETER_ARGS="-Jenv=${ENVIRONMENT} -Jdomain=${SERVICE_ENDPOINT} -Jport=${SERVICE_PORT} -Jprotocol=${SERVICE_URL_SCHEME}"
# AUTH_BASIC_TOKEN is sent as the full Authorization header value: "Basic <base64>".
# Accepts base64 only, "Basic <base64>", or "clientId:secret" (encoded automatically).
# Alternatively set API_KEY_CLIENT_ID and API_KEY_SECRET.
if [ -z "$AUTH_BASIC_TOKEN" ] && [ -n "$API_KEY_CLIENT_ID" ] && [ -n "$API_KEY_SECRET" ]; then
  AUTH_BASIC_TOKEN=$(printf '%s:%s' "$API_KEY_CLIENT_ID" "$API_KEY_SECRET" | base64 | tr -d '\n')
fi

if [ -n "$AUTH_BASIC_TOKEN" ]; then
  AUTH_BASIC_TOKEN=$(printf '%s' "$AUTH_BASIC_TOKEN" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  while printf '%s' "$AUTH_BASIC_TOKEN" | grep -qi '^[Bb][Aa][Ss][Ii][Cc][[:space:]]'; do
    AUTH_BASIC_TOKEN=$(printf '%s' "$AUTH_BASIC_TOKEN" | sed 's/^[Bb][Aa][Ss][Ii][Cc][[:space:]]*//')
  done
  if printf '%s' "$AUTH_BASIC_TOKEN" | grep -q ':'; then
    AUTH_BASIC_TOKEN=$(printf '%s' "$AUTH_BASIC_TOKEN" | base64 | tr -d '\n')
  fi
  AUTH_BASIC_TOKEN="Basic ${AUTH_BASIC_TOKEN}"
  JMETER_ARGS="$JMETER_ARGS -JAUTH_BASIC_TOKEN=${AUTH_BASIC_TOKEN}"
else
  echo "WARNING: AUTH_BASIC_TOKEN is not set; location API requests will likely return 401"
fi

jmeter -n -t ${SCENARIOFILE} -e -l "${JM_REPORTS}/${REPORTFILE}" -o ${JM_HTML_OUTPUT} -j ${LOGFILE} -f \
${JMETER_ARGS}

test_exit_code=$?
if [ $test_exit_code -ne 0 ]; then
  echo "JMeter failed with exit code $test_exit_code"
  exit $test_exit_code
fi

cp -r ${JM_HTML_OUTPUT}/. ${JM_REPORTS}/

# Publish the results into S3 so they can be displayed in the CDP Portal
if [ -n "$RESULTS_OUTPUT_S3_PATH" ]; then
  # Copy the CSV report file and the generated report files to the S3 bucket
   if [ -f "$JM_REPORTS/index.html" ]; then
      aws --endpoint-url=$S3_ENDPOINT s3 cp "${JM_REPORTS}/${REPORTFILE}" "$RESULTS_OUTPUT_S3_PATH/$REPORTFILE"
      aws --endpoint-url=$S3_ENDPOINT s3 cp "$JM_REPORTS" "$RESULTS_OUTPUT_S3_PATH" --recursive
      if [ $? -eq 0 ]; then
        echo "CSV report file and test results published to $RESULTS_OUTPUT_S3_PATH"
      fi
   else
      echo "$JM_REPORTS/index.html is not found"
      exit 1
   fi
else
   echo "RESULTS_OUTPUT_S3_PATH is not set"
   exit 1
fi

exit $test_exit_code
