Add a new cron job to operating_system/CRONS.json that pings google.com every midnight (00:00). 

The cron job should:
- Run at midnight every day (schedule: "0 0 * * *")
- Use type "command" since this is a simple ping operation
- Use the command "ping -c 1 google.com" to send a single ping
- Be named something descriptive like "midnight-ping" or "daily-ping"
- Be enabled by default

Make sure to preserve all existing cron jobs in the file and follow the proper JSON structure as shown in the CRONS.json format.