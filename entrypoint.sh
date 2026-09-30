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
# AUTH_BASIC_TOKEN is base64(clientId:secret) for the Authorization header.
# Accepts base64 only, "Basic <base64>", or "clientId:secret" (encoded automatically).
if [ -n "$AUTH_BASIC_TOKEN" ]; then
  AUTH_BASIC_TOKEN=$(printf '%s' "$AUTH_BASIC_TOKEN" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  while printf '%s' "$AUTH_BASIC_TOKEN" | grep -qi '^[Bb][Aa][Ss][Ii][Cc][[:space:]]'; do
    AUTH_BASIC_TOKEN=$(printf '%s' "$AUTH_BASIC_TOKEN" | sed 's/^[Bb][Aa][Ss][Ii][Cc][[:space:]]*//')
  done
  if printf '%s' "$AUTH_BASIC_TOKEN" | grep -q ':'; then
    AUTH_BASIC_TOKEN=$(printf '%s' "$AUTH_BASIC_TOKEN" | base64 | tr -d '\n')
  fi
else
  echo "WARNING: AUTH_BASIC_TOKEN is not set; API requests will likely return 401"
fi

USER_PROPERTIES=""
if [ -f "${JM_HOME}/user.properties" ]; then
  USER_PROPERTIES="-q ${JM_HOME}/user.properties"
fi

IDENTIFIERS_CSV=${IDENTIFIERS_CSV:-${JM_SCENARIOS}/data/bovine-identifiers.csv}

# Load-profile overrides for scenarios/bovine-animals.jmx (defaults live in the JMX).
# Example CDP run: BASELINE_THREADS=5 STEP_THREADS=40 PEAK_THREADS=80 SUSTAINED_THREADS=25
jmeter -n -t ${SCENARIOFILE} -e -l "${JM_REPORTS}/${REPORTFILE}" -o ${JM_HTML_OUTPUT} -j ${LOGFILE} -f \
  ${USER_PROPERTIES} \
  -Jenv="${ENVIRONMENT}" \
  -Jdomain="${SERVICE_ENDPOINT}" \
  -Jport="${SERVICE_PORT}" \
  -Jprotocol="${SERVICE_URL_SCHEME}" \
  -JidentifiersCsv="${IDENTIFIERS_CSV}" \
  -Jbaseline_threads="${BASELINE_THREADS:-2}" \
  -Jbaseline_ramp="${BASELINE_RAMP:-2}" \
  -Jbaseline_duration="${BASELINE_DURATION:-30}" \
  -Jstep_threads="${STEP_THREADS:-10}" \
  -Jstep_ramp="${STEP_RAMP:-60}" \
  -Jstep_duration="${STEP_DURATION:-90}" \
  -Jpeak_threads="${PEAK_THREADS:-20}" \
  -Jpeak_ramp="${PEAK_RAMP:-5}" \
  -Jpeak_duration="${PEAK_DURATION:-30}" \
  -Jsustained_threads="${SUSTAINED_THREADS:-8}" \
  -Jsustained_ramp="${SUSTAINED_RAMP:-8}" \
  -Jsustained_duration="${SUSTAINED_DURATION:-120}" \
  -Jthink_time_ms="${THINK_TIME_MS:-100}" \
  ${AUTH_BASIC_TOKEN:+-JAUTH_BASIC_TOKEN="${AUTH_BASIC_TOKEN}"}

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
