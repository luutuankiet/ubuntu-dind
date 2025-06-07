#!/bin/bash
# Restart SSH service
/etc/init.d/ssh restart

# Start Docker daemon in background
dockerd-entrypoint.sh &

# Wait for Docker to be ready
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker daemon..."
    sleep 2
done

echo "Docker daemon ready!"

# Execute any additional commands passed to container
if [ $# -gt 0 ]; then
    exec "$@"
else
    # Keep container running
    wait
fi
