#!/bin/bash

export ADGUARD_USE_KILL_SWITCH=${ADGUARD_USE_KILL_SWITCH:-true}

# 1. Run init.sh in the foreground (waits until it finishes)
echo " > Running init.sh..."
/app/scripts/init.sh
INIT_EXIT_CODE=$?

# 2. Wait until the log file is created
while [ ! -f /root/.local/share/adguardvpn-cli/app.log ]; do
    sleep 1
done

# 3. Start tail in the background for log output
tail -F /root/.local/share/adguardvpn-cli/app.log &
TAIL_PID=$!

if [ "${ADGUARD_USE_KILL_SWITCH,,}" = true ]; then
    echo " > Running kill switch..."
    # 4. Run killswitch.sh in the background and save its PID
    /app/scripts/killswitch.sh >> /root/.local/share/adguardvpn-cli/app.log 2>&1 &
    KILL_PID=$!

    # 5. Wait until killswitch.sh exits
    wait $KILL_PID
    KILL_EXIT_CODE=$?

    # 6. If killswitch.sh exits with code 1, terminate tail and exit the container
    if [ "$KILL_EXIT_CODE" -eq 1 ]; then
        echo " > killswitch.sh exited with code 1. Exiting container...."
        kill $TAIL_PID 2>/dev/null
        exit 1
    fi
else
    # If KillSwitch is disabled, keep container alive by tailing log file
    wait $TAIL_PID
fi

