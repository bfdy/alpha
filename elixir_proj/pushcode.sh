#!/bin/bash

#rsync  -arvz -e ssh --exclude-from 'pushcode_exclude_list' . 172.25.86.234:~/labs
rsync  -arvz -e ssh --exclude-from 'pushcode_exclude_list' . $1
