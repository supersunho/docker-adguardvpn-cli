#!/bin/bash

export ADGUARD_USE_KILL_SWITCH=${ADGUARD_USE_KILL_SWITCH:-false}

# Run init.sh in the foreground
/app/scripts/init.sh &
INIT_PID=$!

if [ "${ADGUARD_USE_KILL_SWITCH,,}" = true ]; then
    # Wait until the log file is created
    while [ ! -f /root/.local/share/adguardvpn-cli/app.log ]; do
        sleep 1
    done

    echo "Running killswitch..."
    # Run killswitch.sh in the background and save its PID
    /app/scripts/killswitch.sh >> /root/.local/share/adguardvpn-cli/app.log 2>&1 &
    KILL_PID=$!

    # Wait until killswitch.sh exits
    wait $KILL_PID
    KILL_EXIT_CODE=$?

    # If killswitch.sh exits with code 1, terminate init.sh and exit the container
    if [ "$KILL_EXIT_CODE" -eq 1 ]; then
        echo "killswitch.sh exited with code 1. Exiting container."
        kill $INIT_PID 2>/dev/null
        exit 1
    fi

    # Wait until init.sh exits (normal termination)
    wait $INIT_PID

fi
