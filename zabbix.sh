#!/bin/ash
DBPassword=`</dev/urandom tr -dc "A-Za-z0-9" 2> /dev/null | head -c 16`
snmpcontact="contact"
snmplocation="location" 
snmplogfile="/var/log/snmpd.log"
snmpdirectory="/var/net-snmp"

apk add wget unzip
apk add build-base file perl-dev openssl-dev perl-net-snmp linux-headers
apk add lighttpd php7-common php7-iconv php7-json php7-gd php7-curl php7-xml php7-pgsql php7-imap php7-cgi fcgi
apk add php7-pdo php7-pdo_pgsql php7-pdo_mysql php7-soap php7-xmlrpc php7-posix php7-mcrypt php7-gettext php7-ldap php7-ctype php7-dom php7-mbstring
apk add postgresql postgresql-client
apk add zabbix zabbix-pgsql zabbix-webif zabbix-setup zabbix-agent

cp snmptrapd /etc/init.d/snmptrapd
chmod 644 /etc/init.d/snmptrapd
chmod +x /etc/init.d/snmptrapd

cd /tmp
wget https://downloads.sourceforge.net/project/net-snmp/net-snmp/5.8/net-snmp-5.8.zip
unzip net-snmp-5.8.zip
cd net-snmp-5.8/
./configure --enable-embedded-perl --enable-shared --with-sys-contact=$snmpcontact --with-sys-location=$snmplocation --with-logfile=$snmplogfile --with-persistent-directory=$snmpdirectory
make && make install

cd /tmp
wget https://ufpr.dl.sourceforge.net/project/zabbix/ZABBIX%20Latest%20Stable/4.2.1/zabbix-4.2.1.tar.gz
tar xvzf zabbix-4.2.1.tar.gz
cp zabbix-4.2.1/misc/snmptrap/zabbix_trap_receiver.pl /usr/bin/
chmod +x /usr/bin/zabbix_trap_receiver.pl

mkdir -p /usr/local/etc/snmp
cat >> /usr/local/etc/snmp/snmptrapd.conf << EOL
authCommunity execute public
perl do "/usr/bin/zabbix_trap_receiver.pl";
EOL

/etc/init.d/postgresql setup
/etc/init.d/postgresql start
rc-update add postgresql
psql -U postgres -c "create user zabbix with password '$DBPassword';"
psql -U postgres -c "create database zabbix owner zabbix;"
cd /usr/share/zabbix/database/postgresql
cat schema.sql | psql -U zabbix zabbix
cat images.sql | psql -U zabbix zabbix
cat data.sql | psql -U zabbix zabbix

rm /var/www/localhost/htdocs -R
ln -s /usr/share/webapps/zabbix /var/www/localhost/htdocs

sed -i 's/#   include "mod_fastcgi.conf"/   include "mod_fastcgi.conf"/g' /etc/lighttpd/lighttpd.conf
sed -i 's+"/usr/bin/php-cgi"+"/usr/bin/php-cgi7"+g' /etc/lighttpd/mod_fastcgi.conf
sed -i 's/max_execution_time = 30/max_execution_time = 600/g' /etc/php7/php.ini
sed -i 's/expose_php = On/expose_php = Off/g' /etc/php7/php.ini
sed -i 's+;date.timezone =+date.timezone = America/Sao_Paulo+g' /etc/php7/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 32M/g' /etc/php7/php.ini
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 16M/g' /etc/php7/php.ini
sed -i 's/max_input_time = 60/max_input_time = 600/g' /etc/php7/php.ini
sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /etc/php7/php.ini
sed -i 's/# DBPassword=/DBPassword=$DBPassword/g' /etc/zabbix/zabbix_server.conf
sed -i 's+# FpingLocation=/usr/sbin/fping+FpingLocation=/usr/sbin/fping+g' /etc/zabbix/zabbix_server.conf
sed -i 's/# StartSNMPTrapper=0/StartSNMPTrapper=1/g' /etc/zabbix/zabbix_server.conf
sed -i 's+# SNMPTrapperFile=/var/log/zabbix/zabbix_traps.tmp+SNMPTrapperFile=/tmp/zabbix_traps.tmp+g' /etc/zabbix/zabbix_server.conf
sed -i 's/# ListenPort=10050/ListenPort=10050/g' /etc/zabbix/zabbix_agentd.conf
sed -i 's/use POSIX qw(strftime);/use POSIX qw(strftime); use NetSNMP::TrapReceiver;/g' /usr/bin/zabbix_trap_receiver.pl

chmod u+s /usr/sbin/fping
chown -R lighttpd /usr/share/webapps/zabbix/conf
adduser zabbix readproc

rc-service lighttpd start && rc-update add lighttpd default
rc-update add zabbix-server
/etc/init.d/zabbix-server start
rc-update add zabbix-agentd
/etc/init.d/zabbix-agentd start
rc-update add snmptrapd
/etc/init.d/snmptrapd start
