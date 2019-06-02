#!/bin/bash
cd /timeoff-management
npm install
pm2 start npm --name "WebApp" --cwd /timeoff-management -- start