#!/bin/bash

function check_install {
    if [ -z "`which "$1" 2>/dev/null`" ]
    then
        executable=$1
        shift
        while [ -n "$1" ]
        do
            DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
            print_info "$1 installed for $executable"
            shift
        done
    else
        print_warn "$2 already installed"
    fi
}

function check_remove {
    if [ -n "`which "$1" 2>/dev/null`" ]
    then
        DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge "$2"
        print_info "$2 removed"
    else
        print_warn "$2 is not installed"
    fi
}

function check_sanity {
    # Do some sanity checking.
    if [ $(/usr/bin/id -u) != "0" ]
    then
        die 'Must be run by root user'
    fi

    if [ ! -f /etc/debian_version ]
    then
        die "Distribution is not supported"
    fi
}

function die {
    echo "ERROR: $1" > /dev/null 1>&2
    exit 1
}

function get_domain_name() {
    # Getting rid of the lowest part.
    domain=${1%.*}
    lowest=`expr "$domain" : '.*\.\([a-z][a-z]*\)'`
    case "$lowest" in
    com|net|org|gov|edu|co)
        domain=${domain%.*}
        ;;
    esac
    lowest=`expr "$domain" : '.*\.\([a-z][a-z]*\)'`
    [ -z "$lowest" ] && echo "$domain" || echo "$lowest"
}

function get_password() {
    # Check whether our local salt is present.
    SALT=/var/lib/radom_salt
    if [ ! -f "$SALT" ]
    then
        head -c 512 /dev/urandom > "$SALT"
        chmod 400 "$SALT"
    fi
    password=`(cat "$SALT"; echo $1) | md5sum | base64`
    echo ${password:0:13}
}

function install_dash {
    check_install dash dash
    rm -f /bin/sh
    ln -s dash /bin/sh
}


function install_redis {
    sudo apt-get -q -y install redis-server
}

function install_fonts {
    sudo apt-get -q -y install fonts-lao
}

function install_dropbear {
    check_install dropbear dropbear
    check_install /usr/sbin/xinetd xinetd

    # Disable SSH
    touch /etc/ssh/sshd_not_to_be_run
    invoke-rc.d ssh stop

    # Enable dropbear to start. We are going to use xinetd as it is just
    # easier to configure and might be used for other things.
    cat > /etc/xinetd.d/dropbear <<END
service ssh
{
    socket_type     = stream
    only_from       = 0.0.0.0
    wait            = no
    user            = root
    protocol        = tcp
    server          = /usr/sbin/dropbear
    server_args     = -i
    disable         = no
}
END
    invoke-rc.d xinetd restart
}

function install_exim4 {
    check_install mail exim4
    if [ -f /etc/exim4/update-exim4.conf.conf ]
    then
        sed -i \
            "s/dc_eximconfig_configtype='local'/dc_eximconfig_configtype='internet'/" \
            /etc/exim4/update-exim4.conf.conf
        invoke-rc.d exim4 restart
    fi
}

function install_mysql {
    # Install the MySQL packages

    sudo debconf-set-selections <<< 'mysql-server-5.5 mysql-server/root_password password raspberry'
    sudo debconf-set-selections <<< 'mysql-server-5.5 mysql-server/root_password_again password raspberry'
    check_install mysqld mysql-server-5.5

    # Install a low-end copy of the my.cnf to disable InnoDB, and then delete
    # all the related files.

    mkdir -p /etc/mysql/conf.d/
    echo -e "[mysqld] \
      key_buffer = 8M \
      query_cache_size = 0 \
      skip-innodb" > /etc/mysql/conf.d/lowendbox.cnf

    echo -e "[client] \n user = root \n password = raspberry" > ~/.my.cnf
    chmod 600 ~/.my.cnf
}

function install_nginx {
    check_install nginx nginx

    # Need to increase the bucket size for Debian 5.
    cat > /etc/nginx/conf.d/lowendbox.conf <<END
server_names_hash_bucket_size 64;
END

    invoke-rc.d nginx restart
}

function install_php {
    sudo apt-get -y -q install php5 php5-fpm php-pear php5-mysql
}

function install_syslogd {
    # We just need a simple vanilla syslogd. Also there is no need to log to
    # so many files (waste of fd). Just dump them into
    # /var/log/(cron/mail/messages)
    check_install /usr/sbin/syslogd inetutils-syslogd
    invoke-rc.d inetutils-syslogd stop

    for file in /var/log/*.log /var/log/mail.* /var/log/debug /var/log/syslog
    do
        [ -f "$file" ] && rm -f "$file"
    done
    for dir in fsck news
    do
        [ -d "/var/log/$dir" ] && rm -rf "/var/log/$dir"
    done

    cat > /etc/syslog.conf <<END
*.*;mail.none;cron.none -/var/log/messages
cron.*                  -/var/log/cron
mail.*                  -/var/log/mail
END

    [ -d /etc/logrotate.d ] || mkdir -p /etc/logrotate.d
    cat > /etc/logrotate.d/inetutils-syslogd <<END
/var/log/cron
/var/log/mail
/var/log/messages {
   rotate 4
   weekly
   missingok
   notifempty
   compress
   sharedscripts
   postrotate
      /etc/init.d/inetutils-syslogd reload >/dev/null
   endscript
}
END

    invoke-rc.d inetutils-syslogd start
}

function install_wordpress {
    check_install wget wget

#     sudo git clone "https://bitbucket.org/villagescience/wordpress.git /var/www/$1"
    chown root:root -R "/var/www/$1"

    # Setting up the MySQL database
    dbname=`echo $1 | tr . _`
    userid=`get_domain_name $1`
    # MySQL userid cannot be more than 15 characters long
    userid="${userid:0:15}"
    passwd=`get_password "$userid@mysql"`
    sed -i "s/database_name_here/$dbname/; s/username_here/$userid/; s/password_here/$passwd/" \
        "/var/www/$1/wp-config.php"
    mysqladmin create "$dbname"
    echo "GRANT ALL PRIVILEGES ON \`$dbname\`.* TO \`$userid\`@localhost IDENTIFIED BY '$passwd';" | \
        mysql

    rm -r /etc/nginx/sites-available/default

    # Setting up Nginx mapping
    cat > "/etc/nginx/sites-enabled/$1.conf" <<END
server {
    listen       80 default_server;
    server_name  "";
    root         /var/www/$1;

    location /index.php {
        alias /var/www/$1/wp-index-redis.php;
    }

    location / {
        index wp-index-redis.php;
        try_files \$uri \$uri/ /wp-index-redis.php?\$args;
    }

    location /wp-admin/ {
        index index.php;
        try_files \$uri \$uri/ /index.php\$args;
    }

    # Add trailing slash to /wp-admin requests
    rewrite /wp-admin\$ \$scheme::/\$host\$uri/ permanent;

    gzip off;

    # Directives to send expires headers and turn off 404 error logging.
    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires 24h;
        log_not_found off;
    }

    # this prevents hidden files (beginning with a period) from being served
          location ~ /\.          { access_log off; log_not_found off; deny all; }

    location ~ \.php$ {
        client_max_body_size 25M;
        try_files      \$uri =404;
        fastcgi_pass   unix:/var/run/php5-fpm.sock;
        fastcgi_index  index.php;
        include        /etc/nginx/fastcgi_params;
    }
}
END
    invoke-rc.d nginx reload
    curl -d "weblog_title=VSPi&user_name=admin&admin_password=raspberry&admin_password2=raspberry&admin_email=vspi@villagescience.org" http://127.0.0.1/wp-admin/install.php?step=2 >/dev/null 2>&1
}

function print_info {
    echo -n -e '\e[1;36m'
    echo -n $1
    echo -e '\e[0m'
}

function print_warn {
    echo -n -e '\e[1;33m'
    echo -n $1
    echo -e '\e[0m'
}

function remove_unneeded {
    # Some Debian have portmap installed. We don't need that.
    check_remove /sbin/portmap portmap

    # Remove rsyslogd, which allocates ~30MB privvmpages on an OpenVZ system,
    # which might make some low-end VPS inoperatable. We will do this even
    # before running apt-get update.
    check_remove /usr/sbin/rsyslogd rsyslog

    # Other packages that seem to be pretty common in standard OpenVZ
    # templates.
    check_remove /usr/sbin/apache2 'apache2*'
    check_remove /usr/sbin/named bind9
    check_remove /usr/sbin/smbd 'samba*'
    check_remove /usr/sbin/nscd nscd

    # Need to stop sendmail as removing the package does not seem to stop it.
    if [ -f /usr/lib/sm.bin/smtpd ]
    then
        invoke-rc.d sendmail stop
        check_remove /usr/lib/sm.bin/smtpd 'sendmail*'
    fi
}

function update_upgrade {
    # Run through the apt-get update/upgrade first. This should be done before
    # we try to install any package
    apt-get -q -y update
    apt-get -q -y upgrade
}

function config_network {

    sudo apt-get -q -y install bridge-utils hostapd avahi-daemon

    wget http://www.daveconroy.com/wp3/wp-content/uploads/2013/07/hostapd.zip
    unzip hostapd.zip
    sudo rm  /usr/sbin/hostapd
    sudo mv hostapd /usr/sbin/hostapd.edimax
    sudo ln -sf /usr/sbin/hostapd.edimax /usr/sbin/hostapd
    sudo chown root.root /usr/sbin/hostapd
    sudo chmod 755 /usr/sbin/hostapd

    cat > "/etc/network/interfaces" <<END
auto lo
iface lo inet loopback
iface eth0 inet dhcp
auto br0
iface br0 inet dhcp
bridge_ports eth0 wlan0
END

    cat > "/etc/hostapd/hostapd.conf" <<END
interface=wlan0
driver=rtl871xdrv
bridge=br0
ssid=VSPi_Connect
channel=1
wmm_enabled=0
wpa=1
wpa_passphrase=forscience
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
auth_algs=1
macaddr_acl=0
END

  echo -e "DAEMON_CONF='/etc/hostapd/hostapd.conf'" >> /etc/default/hostapd

echo -e "vspi" > /etc/hostname
echo -e "127.0.0.1    vspi" > /etc/hosts
sudo /etc/init.d/hostname.sh

}

########################################################################
# START OF PROGRAM
########################################################################
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

check_sanity
install_exim4
install_mysql
install_nginx
install_php
remove_unneeded
update_upgrade
install_dash
install_syslogd
install_redis
install_fonts
install_wordpress vspi.local
config_network
sudo reboot