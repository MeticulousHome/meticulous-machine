Please drop the folder, "murata" into root file system, under /lib/firmware/nxp

Folder "murata" contains the following files for the modules 1XK, 1XL, 1YM, 1ZM, 2DS, 2EL and 2DL.
    - tx power, 
    - db.txt,
    - db-murata.txt,
    - regulatory.db,
    - regulatory.db.p7s
    - bt_power,
    - murata.hex,
    - ed_mac.conf, and
    - switch_regions.sh

WLAN Tx power configuration files for Country Code:
--------------------------------------------------
- US                 : txpower_US.bin
- CA(Canada)         : txpower_CA.bin
- EU(European Union) : txpower_EU.bin
- JP(Japan)          : txpower_JP.bin


WLAN Tx power configuration files for 11ax RU Country Code:
----------------------------------------------------------
- US                 : rutxpower_US.bin
- CA(Canada)         : rutxpower_CA.bin
- EU(European Union) : rutxpower_EU.bin
- JP(Japan)          : rutxpower_JP.bin


WLAN Carrier Sense / Adaptivity threshold configuration file:
-------------------------------------------------------------
- ed_mac.conf


WLAN regulatory limitation configuration file:
----------------------------------------------
- db.txt
- db-murata.txt
- regulatory.db
- regulatory.db.p7s
- murata.hex

Bluetooth Tx power configuration file:
-------------------------------------
- bt_power_config_1.sh

+========+=======================+=========================================+
|  No    |  File Name            |  1XK                                    |
+========+=======================+=========================================+
|  1     |  txpower_US.bin       |  79353e4e4cc0dbcf9dae09d3a0b10ceb       |
|  2     |  txpower_CA.bin       |  c93944abea1a2a4f16850c4eecbf6726       |
|  3     |  txpower_EU.bin       |  d10bfbfcc4fbab25f564ff27b900a9ce       |
|  4     |  txpower_JP.bin       |  7b94f1499c5dc377a958065da82d2719       |
|  5     |  db.txt               |  bafe033ae5deecb5e3be7b19f5c6018c       |
|  6     |  db-murata.txt        |  a34c5151e81b043534d11ab3ed35be73       |
|  7     |  ed_mac.conf          |  03b70eb9983c723ec48791f1a886df6c       |
|  8     |  regulatory.db        |  a151646cf0ff47518765a42e00e4884c       |
|  9     |  regulatory.db.p7s    |  5ae110fd737c3de590ac0bc520cb36d7       |
|  10    |  murata.hex           |  c44de596e9dcc7d72160ddb98cbfd648       |
+========+=======================+=========================================+

+========+=======================+=========================================+
|  No    |  File Name            |  1XL/2XS                                |
+========+=======================+=========================================+
|  1     |  txpower_US.bin       |  fda5c830460ea87d88c47c7c9085fd56       |
|  2     |  txpower_CA.bin       |  15a27585605cba9b0dc05bf9c664852f       |
|  3     |  txpower_EU.bin       |  3cad652ddba50533ce7c091ef49106f9       |
|  4     |  txpower_JP.bin       |  2ffe0c6b55cc3050b9806baef1e0616c       |
|  5     |  rutxpower_US.bin     |  dd14dd139941a7c87fa2718cd2fcee19       |
|  6     |  rutxpower_CA.bin     |  b9be928c670fc1a6597381008c87bcd4       |
|  7     |  rutxpower_EU.bin     |  fe6dfb102d843382b35a92946b9d8a5a       |
|  8     |  rutxpower_JP.bin     |  57919224b73efb571fa6b0c92eda1e0b       |
|  9     |  db.txt               |  69571ad1421f21c18296dc383c6f63b9       |
|  10    |  db-murata.txt        |  2af9e7112a8fff134740bd060e8e968d       |
|  11    |  ed_mac.conf          |  803e638b9f304f5b5f39691453224f6f       |
|  12    |  regulatory.db        |  c844997e941507a0ea2b3a8b7b9a5734       |
|  13    |  regulatory.db.p7s    |  f01ba6cd3eca2c31394b5e7e5597885e       |
|  14    |  murata.hex           |  248971ffc6415a58b7ebd6ba4bba5af0       |
+========+=======================+=========================================+

+========+================================+==================================+
|  No    |  File Name                     |  2EL/2DL                         |
+========+================================+==================================+
|  1     |  txpower_US.bin                | 3d7a69a2c41fa6fa55b31295ff4ff3f3 |
|  2     |  txpower_CA.bin                | 69079f9aa87adc39707fb81985d62056 |
|  3     |  txpower_EU.bin                | ed3bd3dbb4de7da4d58b4b709c15e43d |
|  4     |  txpower_JP.bin                | 5180d7a4e06d48a879d1b5ce38663969 |
|  5     |  rutxpower_US.bin              | 61a2e1be72465808322919513849b20d |
|  6     |  rutxpower_CA.bin              | f682d508c1a1b628c66454d9854dc4e5 |
|  7     |  rutxpower_EU.bin              | e0f39f2abe42ee2902d832ad3c1df6b4 |
|  8     |  rutxpower_JP.bin              | d92f4049593f76f2e2491d64db5e43af |
|  9     |  db.txt                        | 69571ad1421f21c18296dc383c6f63b9 |
|  10    |  db-murata.txt                 | 62380baa6f06dcf7a4f1f11d6fdf1bfc |
|  11    |  ed_mac.conf                   | 587aec9b75774300976ecb953edc4530 |
|  12    |  regulatory.db                 | c844997e941507a0ea2b3a8b7b9a5734 |
|  13    |  regulatory.db.p7s             | c38cc1684e365761947489394171bf8e |
|  14    |  bt_power_config_US_CA.sh      | a4c6f3adf51ffcbfe4adafb256da849c |
|  15    |  bt_power_config_JP.sh         | 3c7d100a9aae18b9895c00b4151ab2b3 |
|  16    |  bt_power_config_EU.sh         | d37587d80491eff89d64a79eb8ee12f2 |
|  17    |  WlanCalData_ext_NXP_dANT.conf | ee15776602763ca6031f151694fe0c1a |
|  18    |  murata.hex                    | 3461cd50a46fb7082fa493f8105fff64 |
+========+================================+==================================+

+========+=======================+=========================================+
|  No    |  File Name            |  1YM                                    |
+========+=======================+=========================================+
|  1     |  txpower_US.bin       |  c53438c16f3ab97d5d427f68448d9968       |
|  2     |  txpower_CA.bin       |  c53438c16f3ab97d5d427f68448d9968       |
|  3     |  txpower_EU.bin       |  085fa56dcda492b5f206a18cb52d374a       |
|  4     |  txpower_JP.bin       |  79e1a88ee2de19fe548f8e206fa7d0a3       |
|  5     |  db.txt               |  645088447ad97810c87112747145e6f1       |
|  6     |  db-murata.txt        |  dbf92b257b8e3b1c2bf43ea8886debf7       |
|  7     |  ed_mac.conf          |  f44beb7a92a4a9cec2da25e31ad8fc1c       |
|  8     |  regulatory.db        |  9eff9e6fe87ab7a152eedf89b2e748da       |
|  9     |  regulatory.db.p7s    |  14bebee00d592ab39504f3deecd324a5       |
|  10    |  murata.hex           |  6fedeae7f9804daae022de16ffbcac03       |
+========+=======================+=========================================+
		
+========+=======================+=========================================+
|  No    |  File Name            |  2DS                                    |
+========+=======================+=========================================+
|  1     |  txpower_US.bin       |  2dd1aacf4532fe9667b5bb0744598ece       |
|  2     |  txpower_CA.bin       |  2dd1aacf4532fe9667b5bb0744598ece       |
|  3     |  txpower_EU.bin       |  f73f5939ed3f67b6dfcd5b5a600356d7       |
|  4     |  txpower_JP.bin       |  0801095d2e7e21fcd6ca25d10b3337d7       |
|  5     |  db.txt               |  8f45df9eb5211485f02e2db324f3ba4f       |
|  6     |  db-murata.txt        |  ef55b9d535b6e76cc5f794512bfecd85       |
|  7     |  ed_mac.conf          |  bdaa6a1a34199c2580364b068a4c40e2       |
|  8     |  regulatory.db        |  2174684d663628f4ad5aec61e9bf4847       |
|  9     |  regulatory.db.p7s    |  65b9cc291160d915006c329c003b76b4       |
|  10    |  murata.hex           |  e39447b68b55b4514e04d339ef7ec904       |
+========+=======================+=========================================+	

+========+=======================+=========================================+
|  No    |  File Name            |  1ZM                                    |
+========+=======================+=========================================+
|  1     |  txpower_US.bin       |  97eaa214a23eb09f63e1218a9426f0b5       |
|  2     |  txpower_CA.bin       |  97eaa214a23eb09f63e1218a9426f0b5       |
|  3     |  txpower_EU.bin       |  213716863d3478a11e87716e7e78646e       |
|  4     |  txpower_JP.bin       |  5bf0b86d73e270194e62e25e93bd0e38       |
|  5     |  db.txt               |  645088447ad97810c87112747145e6f1       |
|  6     |  db-murata.txt        |  dbf92b257b8e3b1c2bf43ea8886debf7       |
|  7     |  ed_mac.conf          |  4e95520c37ddb8b2e041bfb5df5f2dd4       |
|  8     |  regulatory.db        |  9eff9e6fe87ab7a152eedf89b2e748da       |
|  9     |  regulatory.db.p7s    |  51b097e5e8cec290339be0035c7fa611       |
|  10    |  murata.hex           |  d99428ac7e0c642a95c61e907290ba3b       |
+========+=======================+=========================================+


STEP 1:  Execute the script file, "switch_regions.sh"
======
Ex: $./switch_regions.sh 1ZM <COUNTRY_CODE>
where <COUNTRY_CODE> is "US", "CA", "EU", and "JP"

    US - For USA
    CA - Canada
    EU - European Union
    JP - Japan

STEP 2:  "switch_regions.sh" automatically modifies the file, “wifi_mod_para.conf”. Please find the details below.
=======

Content of “wifi_mod_para.conf”:
--------------------------------------

1. Select appropriate module structure.
   Ex:
    1ZM      - SD8987
    1YM-SDIO - SD8997
    1YM-PCIe - PCIE8997
    1XK      - IW416
    2DS      - SD8801
    1XL/2XS  - SD9098
    2EL/2DL  - IW612

2. For the parameter, "txpwrlimit_cfg", Select appropriate module name, and corresponding country, when specifying txpower_<COUNTRY_CODE>.bin
   Ex:
    txpwrlimit_cfg=nxp/murata/<MODULE>/txpower_<COUNTRY_CODE>.bin

   NOTE: For country code, EU, users must also perform one additional step given below

STEP 3 (Optional: Only for EU country code):  Execute the following "mlanutl" command.
======
$ mlanutl <INTERFACE_NAME> hostcmd /lib/firmware/ed_mac.conf ed_mac_ctrl_v2
 
where <INTERFACE_NAME> is the STA interface, e.g.  "mlan0".

For WLAN:
========
Command example:
---------------
#switch_regions.sh 1YM US
#reboot
#iw reg set <COUNTRY_CODE>
#iw reg get

NOTE: 
=====  
When using "iw reg set <COUNTRY_CODE>" command, For Europe the country code is "DE", as there isn't actually a country code named "EU".
i.e "iw reg set DE"

Ex: For 1YM and to configure for US Region: modify the following structure.

SD8997 = {
	cfg80211_wext=0xf
	max_vir_bss=1
	cal_data_cfg=none
	ps_mode=1
	auto_ds=1
	host_mlme=1
	fw_name=nxp/sdiouart8997_combo_v4.bin
	txpwrlimit_cfg=nxp/txpower_US.bin
}


For Bluetooth:
=============
Bluetooth Tx power configuration script file shall be loaded after Bluetooth device initialization.

Command example:
---------------
# sh bt_power_config_1.sh

NOTE: 
=====  
For 2EL/2DL modules, two separate Bluetooth Tx power configuration script files are provided:
1. bt_power_config_US_CA.sh : To configure Tx power for US and CA countries.
2. bt_power_config_JP.sh : To configure Tx power for JP countries.
3. bt_power_config_EU.sh : To configure Tx power for EU contries.

If you want to specify dAnt (dedicated Antenna) for 2EL/2DL, then please specify the following for 2EL/2DL.
	cal_data_cfg=nxp/WlanCalData_ext_NXP_dANT.conf

Refer the sample file, "wifi_mod_para_sample_US.conf" which is configured for modules (1ZM and 1YM to select US region).
