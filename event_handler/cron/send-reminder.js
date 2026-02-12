#!/usr/bin/env node

/**
 * One-time reminder script
 * Sends a message at exactly 21:53 UTC on Feb 12, 2026 (6:53 AM KST Feb 13)
 * Then disables itself by modifying CRONS.json
 */

const fs = require('fs');
const path = require('path');
const { sendMessage } = require('../tools/telegram.js');

const TARGET_DATE = '2026-02-12';
const TARGET_HOUR = 21;
const TARGET_MINUTE = 53;
const MESSAGE = 'Hey, Mark - This is a testing message';

async function main() {
  const { TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID } = process.env;

  // Check if we have required credentials
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.log('[Reminder] Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID - skipping');
    return;
  }

  // Get current time in UTC
  const now = new Date();
  const currentDate = now.toISOString().split('T')[0]; // YYYY-MM-DD
  const currentHour = now.getUTCHours();
  const currentMinute = now.getUTCMinutes();

  console.log(`[Reminder] Checking time - Current: ${currentDate} ${currentHour}:${currentMinute} UTC, Target: ${TARGET_DATE} ${TARGET_HOUR}:${TARGET_MINUTE} UTC`);

  // Check if it's the exact target time
  if (currentDate === TARGET_DATE && currentHour === TARGET_HOUR && currentMinute === TARGET_MINUTE) {
    console.log('[Reminder] Target time reached! Sending message...');

    try {
      // Send the message
      await sendMessage(TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, MESSAGE);
      console.log('[Reminder] ✅ Message sent successfully!');

      // Disable this cron job
      const cronsPath = path.join(__dirname, '../../operating_system/CRONS.json');
      const cronsData = JSON.parse(fs.readFileSync(cronsPath, 'utf-8'));
      
      const cronIndex = cronsData.findIndex(c => c.name === 'one-time-reminder');
      if (cronIndex !== -1) {
        cronsData[cronIndex].enabled = false;
        fs.writeFileSync(cronsPath, JSON.stringify(cronsData, null, 2) + '\n');
        console.log('[Reminder] ✅ Cron job disabled - will not run again');
      }
    } catch (error) {
      console.error('[Reminder] ❌ Error:', error.message);
    }
  } else {
    console.log('[Reminder] Not yet time - waiting...');
  }
}

main().catch(console.error);
