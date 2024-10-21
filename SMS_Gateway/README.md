SMS Gateway

This is setup guide and additional scripts to configure a Raspberry PI with a 4G modem to act as a Email to SMS gateway

We utilize a imap email account where username and password is in the script. 

Emails sendt to the imap account on the format mailaddress+phonenumber@outlook.com (Example dbwatch+91800987@outlook.com)
the script will pick the emails up and send the subject and email body as sms, and if successfull delete the email in the imap folder inbox. 

Its designed to work with the dbWatch Control Center email extension set to SMS. 

This setup should be possible to tweak to use on other Linux systems as well.

Requirements:

Linux
	- Compatible 4G modem with SIM card without a pin set
	- This python script uses gammu to communicate with the 4G modem

This was tested on Raspbian Bullseye on a Raspberry PI 3b+ with a DLINK DWM-222 and a outlook.com email with application password 

Guide:

On a Raspbian Bullseye with network setup.

Add in /etc/apt/sources.list to get gammu on Raspbian Bullseye.
deb http://ftp.de.debian.org/debian bullseye-backports main

apt-get update

apt remove modemmanager

apt-get install libgammu-dev pip && sudo pip3 install python-gammu

apt-get install gammu

pip install imapclient 

Requires a gammu-config file, in /root/gammurc_USB1 if the USB 4G modem is on /dev/ttyUSB1

In email_sms_gateway.py, change the EMAIL, PASSWORD and SERVER variables.

The output should be quite verbose. 


	