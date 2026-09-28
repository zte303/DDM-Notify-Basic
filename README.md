# DDM-Notify-Basic
Uses Swift Notify to provide a basic notice to users about DDM Software Update. Idea and styling inspired by (but much more basic than) https://github.com/dan-snelson/DDM-OS-Reminder/
This was originally written for a Jamf Pro environment with [SwiftDialog](https://github.com/swiftDialog/swiftDialog) version 2.5.6 

MacOS version (up to 2 decimals) and Update deadline (YYYY-MM-DD HH:MM") are required and passed as parameter 4 and 5 respectively.

To test outside of Jamf, you can run locally on a machine with SwiftDialog installed, but will need to pad parameter input to match the expected Jamf output.

As part of normal operation this creates Library/Application Support/UpdateNotification/lastrun for local timing checks and
/var/log/update_notification.log for logging.

Example:

policy.macOSupdatemessage.sh 0, 0, 0, "27.0.0", "2027-03-12 00:00"

<img width="800" height="510" alt="Screenshot 2026-09-28 at 12 06 27 PM" src="https://github.com/user-attachments/assets/4606a6c3-f108-404b-a466-c98095e65155" />
