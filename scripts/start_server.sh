#!/bin/bash
cd /timeoff-management
npm install
npm run-script db-update
pm2 start npm --name "WebApp" --cwd /timeoff-management -- start