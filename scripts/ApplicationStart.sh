#!/bin/bash
pm2 kill
cd /timeoff-management
git fetch
git pull origin master
npm install
npm run-script db-update
#pm2 start npm --name "WebApp" --cwd /timeoff-management -- start