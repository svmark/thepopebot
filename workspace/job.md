Set up automated cron job to fetch market conditions every morning at 5 AM Pacific time (13:00 UTC).

Requirements:
1. Create a script that fetches current market data (S&P 500, Dow Jones, NASDAQ, major indices)
2. Set up cron job to run at 5 AM Pacific (13:00 UTC) daily
3. Script should update market data in a file (could be daily market file or update existing Trump.md)
4. Include proper error handling and logging
5. Make sure timezone handling is correct for Pacific time
6. Script should be executable and properly configured

The automation should:
- Pull latest market data from reliable API
- Format the data clearly with timestamps
- Save to file with date stamps
- Log successful runs and any errors
- Handle weekends/market closures appropriately