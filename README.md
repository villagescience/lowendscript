Download the latest NOOBS from [raspberrypi.org/downloads](http://www.raspberrypi.org/downloads). NOOBS Lite (network install only) will be a smaller download since it doesn't grab the OSes until you pick one at install but if you plan to reinstall Raspbian several times, it'll have to re-download the OS each time.

Follow the instructions from the [Quick Start Guide [PDF]](http://www.raspberrypi.org/wp-content/uploads/2012/04/quick-start-guide-v2_1.pdf) to install Raspbian using NOOBS.

Once Raspbian is installed, your Pi will reboot and then go in to a blue and red config window. We don't need to do anything here so hit 'Finish' and you should be taken to the command prompt.

First, let's install the Wordpress repo. (Note: this can be migrated into the deploy script once it's a public repo with no need for a username and password.)

Make sure you VSPi is plugged in to your network and then run this command:

    sudo git clone https://bitbucket.org/villagescience/wordpress.git /var/www/vspi.local

Enter your Bitbucket username and password when prompted.

    wget --no-check-certificate https://raw.github.com/villagescience/lowendscript/master/setup.sh && sudo bash setup.sh

The setup script will now run and might take over 10 minutes depending on your connection. The script sets up and configures:

* PHP
* MySQL
* nginx
* Redis
* Wordpress
* Various network utilities to make VSPi a wifi hotspot

After the script finishes, your Pi will reboot. Once it's booted back up, you can join the wireless network it creates call "VS-Pi Connect" then navigate to http://vspi.local.