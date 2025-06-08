#!/bin/bash
# flags euo be aggresive fail the script on 
# e : exit on error
# u : undefined vars are errors
# o pipefail : pipe failures are caught
set -euo pipefail



# Script to test container health
# Usage: bash ./tests/container_services.sh <image> <variant>

IMAGE="$1"
VARIANT="$2"
CONTAINER_NAME="test-${VARIANT}"

echo "🧪 Testing container: ${IMAGE}"

# Cleanup function for trap
cleanup() {
    echo "🧹 Cleaning up..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Start container
echo "🚀 Starting container..."
docker run -d --privileged --name "${CONTAINER_NAME}" "${IMAGE}"

# Wait for Docker daemon readiness
echo "⏳ Waiting for Docker daemon to be ready..."
timeout 60 bash -c "
    until docker exec ${CONTAINER_NAME} docker info >/dev/null 2>&1; do
        echo 'Waiting for Docker daemon...'
        sleep 2
    done
"
echo "✅ Docker daemon is ready"

# Basic functionality test
echo "🔍 Testing basic Docker functionality..."
docker exec "${CONTAINER_NAME}" docker run --rm hello-world
echo "✅ Docker functionality test passed"


echo "🔍 Testing basic SSHD functionality..."
docker exec "${CONTAINER_NAME}" sshpass -p 'admin' ssh -o StrictHostKeyChecking=no root@localhost echo "SSH works ✅"
echo "✅ Docker functionality test passed"



# Test graceful shutdown
echo "🛑 Testing graceful shutdown..."
if timeout 15 docker stop "${CONTAINER_NAME}"; then
    echo "✅ Graceful shutdown successful"
else
    echo "❌ Graceful shutdown failed (timeout)"
    exit 1
fi

echo "🎉 All tests passed for ${VARIANT} variant!"
