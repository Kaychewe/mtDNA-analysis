#!/usr/bin/env bash


ROOT="/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis"
cd "$ROOT"

SDKMAN_INIT="/home/jupyter/.sdkman/bin/sdkman-init.sh"
JAVA_VERSION="17.0.8-tem"
WDL_PATH="$ROOT/scatterWrapper_MitoPipeline_v2_5.wdl"
PORT=8094

STAMP="$(date +"%Y%m%d_%H%M%S")"
STDOUT="$ROOT/cromwell_server_stdout.$STAMP.log"
STDERR="$ROOT/cromwell_server_stderr.$STAMP.log"

# Stop any running Cromwell JVMs
pkill -f cromwell-91.jar || true

# Clear local HSQLDB files/lock if no Cromwell is running
rm -f local_cromwell_run.db.* || true
rm -rf local_cromwell_run.db.tmp || true
rm -f local_cromwell_run.db.lck || true

# Ensure Java is ready
source "$SDKMAN_INIT"
sdk install java "$JAVA_VERSION" >/dev/null
sdk use java "$JAVA_VERSION" >/dev/null

echo "[$STAMP] Validating WDL..."
java -jar womtool-91.jar validate "$WDL_PATH"

echo "[$STAMP] Starting Cromwell on port $PORT"
nohup java -Xmx32g -classpath ".:sqlite-jdbc.jar" \
  -Dconfig.file=cromwell.batch.conf \
  -Dwebservice.port=$PORT \
  -jar cromwell-91.jar server \
  > "$STDOUT" 2> "$STDERR" &

echo "[$STAMP] Cromwell PID: $!"
echo "[$STAMP] stdout: $STDOUT"
echo "[$STAMP] stderr: $STDERR"

echo "[$STAMP] Waiting for server..."
for i in {1..30}; do
  if grep -q "Cromwell 91 service started" "$STDOUT"; then
    echo "[$STAMP] Cromwell is up."
    exit 0
  fi
  sleep 2
done

echo "[$STAMP] Cromwell did not report startup within 60s. Check logs."
exit 1
