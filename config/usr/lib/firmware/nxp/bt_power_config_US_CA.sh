#!/bin/bash
hcitool -i hci0 cmd 0x3f 0x00ee 0x01 0x0D
sleep 1
hcitool -i hci0 cmd 0x03 0x003
sleep 1
hciconfig hci0 reset
sleep 1

