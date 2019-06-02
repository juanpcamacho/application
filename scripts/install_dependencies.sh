#!/bin/bash
rm -rf /timeoff-management/*
(find /timeoff-management/ -type d -name ".*" && find /timeoff-management/ -type f -name ".*") | xargs rm -rf