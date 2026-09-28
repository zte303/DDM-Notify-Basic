#!/bin/bash

###############################################################################
# macOS Update Notification Script
# Prompts users to update macOS with meeting detection
###############################################################################

# Parameters
requiredVersion="${4}"          # Parameter 4: macOS version                    (required, up to 2 decimals, padded comparison)
deadline="${5}"                 # Parameter 5: Update deadline                  (required, format: "YYYY-MM-DD HH:MM")
runInterval="${6:-3600}"        # Parameter 6: Minimum seconds between runs     (optional, default: 3600 = 1 hour)
freeSpaceWarningGB="${7:-15}"   # Parameter 7: GB Free space warning threshold  (optional, default: 15GB)
# More warnings can be added by appending to systemFields section. Uptime was considered but ultimately left out.

# Paths
dialog="/usr/local/bin/dialog"
timestampDir="/Library/Application Support/UpdateNotification"
timestampFile="$timestampDir/lastrun"
logFile="/var/log/update_notification.log"
# Cheap Variables
now=$(date +%s)
today=$(date "+%Y-%m-%d")
user="$(stat -f%Su /dev/console)"
uid="$(id -u "$user")"
OSVer=$(sw_vers -productVersion)
[[ -z "$OSVer" ]] && OSVer="Unknown" # Fallback if sw_vers fails for some reason will always trigger update notification since padded to 0.0.0

# Operations to clean up and kill fast if needed
# Trim log if over 1mb
if [[ -f "$logFile" ]] && [[ $(stat -f%z "$logFile") -gt 1048576 ]]; then
    tail -n 1000 "$logFile" > "$logFile.tmp" && mv "$logFile.tmp" "$logFile"
fi

# Validate requiredVersion parameter
if [[ -z "$requiredVersion" ]]; then
    echo "$(date): ERROR - No required version provided (parameter 4)" | tee -a "$logFile"
    exit 1
fi

# Validate deadline parameter after logging setup to ensure we capture any errors with it
if [[ -z "$deadline" ]]; then
    echo "$(date): ERROR - No deadline provided (parameter 5)" | tee -a "$logFile"
    exit 1
fi

# Cheap Deadline calculations we need for recent run check
deadlineEpoch=$(date -j -f "%Y-%m-%d %H:%M" "$deadline" "+%s") # Convert to unix timestamp for math
daysRemaining=$(( (deadlineEpoch - now) / 86400 ))
deadlineDay=$(date -j -f "%Y-%m-%d %H:%M" "$deadline" "+%Y-%m-%d")
if [[ "$today" == "$deadlineDay" ]]; then
    deadlineHumanReadableMessage="Today at $(date -j -f "%Y-%m-%d %H:%M" "$deadline" "+%I:%M %p")"
else
    deadlineHumanReadableMessage=$(date -j -f "%Y-%m-%d %H:%M" "$deadline" "+%A, %-d %B %Y at %I:%M %p")
fi

# Create timestamp directory if it doesn't exist for time since last run tracking
if [[ ! -d "$timestampDir" ]]; then
    mkdir -p "$timestampDir"
fi

# Check if we've run too recently
if [[ -f "$timestampFile" ]]; then
    lastRun=$(< "$timestampFile")
    timeSinceLastRun=$((now - lastRun))
    
    if [[ "$timeSinceLastRun" -lt "$runInterval" ]]; then
        timeRemaining=$((runInterval - timeSinceLastRun))
        echo "$(date): Script ran ${timeSinceLastRun}s ago. Waiting ${timeRemaining}s more before next run." | tee -a "$logFile"
        exit 0
    fi
fi

# OS Version comparison function - compares segment by segment numerically
versionLessThan() {
    local IFS=.
    local i
    local ver1=($1)
    local ver2=($2)

    # Pad to equal length with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
    for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do ver2[i]=0; done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if (( ver1[i] < ver2[i] )); then return 0; fi
        if (( ver1[i] > ver2[i] )); then return 1; fi
    done
    return 1  # versions are equal, no update needed
}

# Check if update is needed
if ! versionLessThan "$OSVer" "$requiredVersion"; then
    echo "$(date): macOS $OSVer meets or exceeds required version $requiredVersion. Exiting." | tee -a "$logFile"
    exit 0
fi

echo "$(date): macOS $OSVer is below required version $requiredVersion. Proceeding" | tee -a "$logFile"

# This variable calculation is slightly costlier so calculated after initial checks.
diskSpaceHumanReadable=$(diskutil info / | awk '/Free Space|Available Space/ {print $4, $5}')

# Conditional infobox sidebar warnings about system status. 
# Currently only free space but can be expanded to include other fields if desired.
# Expensive free space calculation so done after all other checks to avoid unnecessary runs. Uses 512 byte block count from df -P for more accuracy and to avoid issues with df -h human readable formatting. 
freeBytes=$(df -P / | tail -1 | awk '{print $4}')
freeGB=$(( freeBytes * 512 / 1000 / 1000 / 1000 ))
systemFields=""
if [[ "$freeGB" -lt "$freeSpaceWarningGB" ]]; then
    systemFields="${systemFields}
� **Free Space Low:** ${diskSpaceHumanReadable}"
    echo "$(date): INFO - Free Space Low $diskSpaceHumanReadable" | tee -a "$logFile"
fi

# Message field variables
restartWarning="⚠️ However, your Mac **will automatically restart and update** ${deadlineHumanReadableMessage} if you have not yet updated. ⚠️"
deadlineField="**Deadline:** ${deadlineHumanReadableMessage} 

**${daysRemaining} days remaining**"

# Start script and log if not run too recently
echo "$(date): Passed recent run check" | tee -a "$logFile"

# Dialog configuration
title="macOS Update Required"
button1="Open Software Update"
button2="Remind Me Later"

# Message displayed in main dialog
message="Greetings, ${user}! **Your Mac needs to be updated** to macOS ${requiredVersion} or higher to remain secure and compliant with organizational policies.

**You can update at your convenience prior to the deadline** by going to System Preferences > General > Software Update and following the update instructions there. 

To go there now, click **Open Software Update**. Your computer may restart during the update, so please save your work before proceeding.

If you are unable to update now, click **Remind Me Later**.

${restartWarning}

For help or support, click the (?) button in the bottom-right corner

This reminder will reappear until your computer is updated.
"

# Info box
infobox="**Current:** macOS $OSVer

**Required:** macOS ${requiredVersion} or higher

${deadlineField}

${systemFields}
"

# IT support info moved to question mark help button
help="For assistance, please contact **IT Support**:
- Telephone: xxx-xxx-xxxx
- Email: itsupport@xxxxxx
- Website: https://internal.wiki"

# Icon (Self Service app icon locally)
icon="/Applications/Self Service.app"

# Action for primary button
action="x-apple.systempreferences:com.apple.preferences.softwareupdate"

# Check if user is in an active meeting or presenting. Expensive lsof call is only made if meeting apps are detected to minimize performance impact.
checkIfBusy() {
    # Check if any meeting apps are running before expensive lsof call
    if pgrep -qi "zoom.us|teams|webex"; then
        udpSockets=$(lsof -nP -iUDP 2>/dev/null)
        
        zoomUDP=$(grep -i "zoom" <<< "$udpSockets" | wc -l | tr -d ' ')
        teamsUDP=$(grep -i "teams" <<< "$udpSockets" | wc -l | tr -d ' ')
        webexUDP=$(grep -i "webex" <<< "$udpSockets" | wc -l | tr -d ' ')
       # Threshold of 4 UDP sockets was found to be a good general indicator of active meetings in testing but can be adjusted per platform if needed.
        if [[ "$zoomUDP" -gt 4 ]]; then
            echo "$(date): Zoom meeting detected (UDP sockets: $zoomUDP)" | tee -a "$logFile"
            return 1
        fi
        if [[ "$teamsUDP" -gt 4 ]]; then
            echo "$(date): Teams meeting detected (UDP sockets: $teamsUDP)" | tee -a "$logFile"
            return 1
        fi
        if [[ "$webexUDP" -gt 4 ]]; then
            echo "$(date): Webex meeting detected (UDP sockets: $webexUDP)" | tee -a "$logFile"
            return 1
        fi
    fi
    
    return 0
}

showDialog() {

    args=(
        --title "$title"
        --message "$message"
        --icon "$icon"
        --iconsize 250
        --infobox "$infobox"
        --button1text "$button1"
        --button2text "$button2"
        --helpmessage "$help"
        --messagefont "size=14"
        --width 800
        --height 440
        "$@"
    )

    "$dialog" "${args[@]}"
    rc=$?

    case "$rc" in
        0)  # User clicked "Open Software Update"
            echo "$(date): User clicked 'Open Software Update'" | tee -a "$logFile"
            launchctl asuser "$uid" su - "$user" -c "open '$action'"
            exit 0
            ;;
        2|4)  # User clicked "Remind Me Later" or timer expired
            echo "$(date): User dismissed dialog (code: $rc)" | tee -a "$logFile"
            exit 0
            ;;
        3)  # User clicked question mark (help)
            echo "$(date): User clicked help button" | tee -a "$logFile"
            exit 0
            ;;
        *)  # Catch all
            echo "$(date): Dialog exited with code: $rc" | tee -a "$logFile"
            exit "$rc"
            ;;
    esac
}

# Check if user is busy before showing dialog
if ! checkIfBusy; then
    echo "$(date): User appears to be in a meeting. Deferring dialog." | tee -a "$logFile"
    exit 0
fi

# Timestamp and Launch dialog
date +%s > "$timestampFile"
echo "$(date): Showing dialog to user" | tee -a "$logFile"
showDialog --ontop --moveable
