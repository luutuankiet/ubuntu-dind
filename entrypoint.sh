#!/bin/bash
# Signal trap for cleanup
trap 'cleanup' SIGTERM SIGINT

cleanup() {
    echo "Shutting down services..."
    # Kill additional command first (docker-compose, etc.)
    kill $ADDITIONAL_PID 2>/dev/null
    # Kill background services
    kill $(jobs -p) 2>/dev/null
    # Stop SSH properly
    /etc/init.d/ssh stop
    exit 0
}

# Start prerequisite services
/etc/init.d/ssh restart
dockerd-entrypoint.sh &

# Wait for Docker readiness
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker daemon..."
    sleep 2
done
echo "Docker daemon ready!"

# Handle additional commands
if [ $# -gt 0 ]; then
    echo "Starting additional command: $@"
    "$@" &
    ADDITIONAL_PID=$!
    wait  # Wait for all background processes
else
    wait  # Just wait for prerequisite services
fi
