#!/bin/bash
# Restart SSH service without prompting for a password
/etc/init.d/ssh restart

# Run docker daemon entrypoint
dockerd-entrypoint.sh
