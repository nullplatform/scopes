#!/bin/bash

# Variable to store the child process PID
NP_AGENT_PID=""

# Log function
log() {
    echo "[$(date -Iseconds)] $1"
}

# Signal handling function
cleanup() {
    local signal=$1
    log "Received signal: $signal"
    
    if [ -n "$NP_AGENT_PID" ] && kill -0 $NP_AGENT_PID 2>/dev/null; then
        log "Sending SIGTERM to np-agent process $NP_AGENT_PID"
        kill -15 $NP_AGENT_PID
        
        # Wait for the child process to terminate with a timeout
        log "Waiting for np-agent process to terminate..."
        
        # Give the process time to clean up (similar to preStop hook time)
        local timeout=25  # Less than the 30s termination grace period
        local end_time=$(($(date +%s) + $timeout))
        
        while kill -0 $NP_AGENT_PID 2>/dev/null && [ $(date +%s) -lt $end_time ]; do
            log "Process $NP_AGENT_PID still running, waiting..."
            sleep 1
        done
        
        if kill -0 $NP_AGENT_PID 2>/dev/null; then
            log "Process $NP_AGENT_PID did not terminate gracefully within timeout"
            log "Sending SIGKILL to process $NP_AGENT_PID"
            kill -9 $NP_AGENT_PID
        else
            log "Process $NP_AGENT_PID terminated gracefully"
        fi
    else
        log "No running np-agent process found"
    fi
    
    log "Cleanup complete, exiting with appropriate status"
    # Exit with appropriate status
    if [ "$signal" = "EXIT" ]; then
        exit 0
    else
        # Exit with signal + 128 which is a common convention
        exit $(( 128 + $(kill -l $signal) ))
    fi
}

# Trap signals
trap 'cleanup TERM' TERM
trap 'cleanup INT' INT
trap 'cleanup HUP' HUP
trap 'cleanup QUIT' QUIT
trap 'cleanup USR1' USR1
trap 'cleanup USR2' USR2
trap 'cleanup EXIT' EXIT

# Start np-agent process
log "Starting np-agent process..."
/root/.local/bin/np-agent \
    --apikey=$NP_API_KEY \
    --runtime=host \
    --tags=$TAGS \
    --command-executor-env=NP_API_KEY="\"$NP_API_KEY\"" \
    --command-executor-command-folders /root/.np/services \
    --command-executor-debug \
    --webserver-enabled &

# Store the PID of np-agent
NP_AGENT_PID=$!
log "np-agent process started with PID: $NP_AGENT_PID"

# Wait for the np-agent process to complete
# Using 'wait' allows the script to receive signals
wait $NP_AGENT_PID
EXIT_STATUS=$?

log "np-agent process exited with status: $EXIT_STATUS"
exit $EXIT_STATUS
