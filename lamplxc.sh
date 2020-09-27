#!/bin/bash

# ContainerNameToCreate RootPassword IPAddress Network Netmask gateway
function createLXC {
  name="$1" pwd="$2" ip="$3" network="$4" mask="$5" gateway="$6"
  cmd="lxc-attach -n $name --"
  lxc-create -t download -n $name -- -d debian -r buster -a amd64
  lxc-start -n $name
  $cmd sh -c 'echo "root:'$pwd'" | chpasswd'
  # (!) The sleep is important. Otherwise the container don't have enough time to setup the network interfaces correctly
  # and crashes when you assign him a static IP address and reload the networking daemon.
  sleep 10
  $cmd sh -c 'echo "
auto lo
iface lo inet loopback

auto eth0
#iface eth0 inet dhcp
iface eth0 inet static
      address '$ip'
      network '$network'
      netmask '$mask'
      gateway '$gateway'

source /etc/network/interfaces.d/*.cfg" > /etc/network/interfaces'
  $cmd systemctl restart networking
  $cmd apt update #&& apt upgrade && apt autoremove # uncomment the upgrade before pushing to prod, it's just to slow for dry runs
  $cmd apt install -y openssh-server curl wget gnupg2 ca-certificates lsb-release apt-transport-https software-properties-common # some utils
  # Allow SSH with root and password, I don't recommand this for prod. Use instead SSH keyring and disable remote root login.
  $cmd sed -i "/#PermitRootLogin/c\PermitRootLogin yes" /etc/ssh/sshd_config
  $cmd sed -i "/#PasswordAuthentication/c\PasswordAuthentication yes" /etc/ssh/sshd_config
  $cmd systemctl restart sshd
  echo "* LXC container $1  created *"
}

#ContainerNameWhereToInstall WebsiteName MySQLContainerName DatabaseName ServiceUsername ServiceUsernamePassword
function setWebsite {
  name="$1" website="$2" mysql="$3" dbname="$4" user="$5" pwd="$6" cmd="lxc-attach -n $name --"
  $cmd mkdir /var/www/$website
  # Somehow it's incredibly hard to pass an echo to file within an lxc-attach, that's why there is this odd syntax with sh -c and escape characters everywhere
  $cmd sh -c 'echo "
<?php
  \$servername = \"'$mysql'\";
  \$dbname = \"'$dbname'\";
  \$username = \"'$user'\";
  \$password = \"'$pwd'\";

  echo \"<h1>WEBSITE TEST</h1>\";
  try {
    \$conn = new PDO(\"mysql:host=\$servername;dbname=\$dbname\", \$username, \$password);
    \$conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    echo \"Connected successfully to db \$dbname\";
  } catch(PDOException \$e) {
    echo \"Connection failed: \" . \$e->getMessage();
  }
?>" > /var/www/index.php'
  # mv to rename, because you can't directly pass a shell var after the ">" in a 'sh -c echo' command
  $cmd mv /var/www/index.php /var/www/$website/index.php
  $cmd sh -c 'echo "
<VirtualHost *:80>
	ServerName <site>
	ServerAdmin webmaster@localhost
	DocumentRoot /var/www/<site>

	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
  " > /etc/apache2/sites-available/site.conf'
  $cmd mv /etc/apache2/sites-available/site.conf /etc/apache2/sites-available/$website.conf
  $cmd sed -i "s/<site>/$website/g" /etc/apache2/sites-available/$website.conf
  $cmd a2ensite $website
  $cmd systemctl reload apache2
  echo "* Website installed on $1 *"
}

#ContainerNameWhereToInstall
function installApache {
  name="$1" cmd="lxc-attach -n $name --"
  $cmd apt update
  $cmd apt install -y apache2
  # disabling LXC daemon protection, otherwise it will fail
  $cmd sed -i "/PrivateTmp=true/c\PrivateTmp=false" /lib/systemd/system/apache2.service
  $cmd systemctl daemon-reload
  $cmd systemctl start apache2
  echo "* Apache installed for $1 *"
}

#nomConteneurMySQL pwdrootMysql userService pwdService
function mysqlSecureInstallation {
  query="$1 mysql -u root -p$2 -e" pwdroot="$2" user="$3" pwduser="$4"
  # This is basically what the original mysqlSecureInstallation script does
  $query "SET PASSWORD FOR 'root'@'%' = PASSWORD('$pwdroot');" # root password
  $query "CREATE USER 'root'@'%' IDENTIFIED BY '$pwdroot';GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;FLUSH PRIVILEGES;" # (optional) second root for test
  $query "DELETE FROM mysql.user WHERE User='';" # removing useless users
  $query "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  $query "DROP DATABASE IF EXISTS test;DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';" # removing test database
  $query "CREATE USER '$user'@'%' IDENTIFIED BY '$pwduser';GRANT ALL PRIVILEGES ON *.* TO '$user'@'%';FLUSH PRIVILEGES;" # service user account
}

#ContainerNameWhereToInstall MySQLRootPassword MySQLServiceUserName MySQLServiceUserPassword
function installMysql {
  name="$1" pwdroot="$2" user="$3" pwduser="$4" cmd="lxc-attach -n $name --"
  $cmd apt update
  $cmd apt install -y mariadb-server mariadb-client
  # disabling LXC daemon protection, otherwise it will fail
  $cmd sed -i "/ProtectHome=true/c\ProtectHome=false" /lib/systemd/system/mariadb.service
  $cmd sed -i "/ProtectSystem=full/c\ProtectSystem=false" /lib/systemd/system/mariadb.service
  $cmd sed -i "/PrivateDevices=true/c\ProtectDevices=false" /lib/systemd/system/mariadb.service
  # disabling default bind which points to 127.0.0.1
  $cmd sed -i "s/bind-address/#bind-address/g" /etc/mysql/mariadb.conf.d/50-server.cnf
  $cmd systemctl daemon-reload
  $cmd systemctl restart mariadb
  mysqlSecureInstallation "$cmd" "$pwdroot" "$user" "$pwduser"
  echo "* MySQL installed for $1 *"
}

#ContainerNameWhereToInstall RootPassword ServiceUsername ServiceUserPassword
function installPhp {
  name="$1" pwdroot="$2" user="$3" pwduser="$4" cmd="lxc-attach -n $name --"
  $cmd apt update
  version="7.3"
  $cmd apt install -y php$version libapache2-mod-php$version php-mysqli
  # Enabling apache plugins required by phpmyadmin
  $cmd sed -i "s/;extension=mbstring/extension=mbstring/g" /etc/php/$version/php.ini
  $cmd sed -i "s/;extension=mysqli/extension=mysqli/g" /etc/php/$version/php.ini
  $cmd sh -c 'echo "<?php phpinfo() ?>" > /var/www/html/php.php' # may be disabled
  echo "* PHP installed for $1 *"
}

#ContainerNameWhereToInstall MySQLContainerName MySQLIP MySQLRootPassword ServiceUsername ServiceUserPassword
function installPhpmyadmin {
  name="$1" mysqlname="$2" mysqlhost="$3" mysqlpwdroot="$4" userpma="$5" pwdpma="$6" cmd="lxc-attach -n $name --" query="lxc-attach -n $mysqlname -- mysql -u root -p$mysqlpwdroot -e"
  version="5.0.2"
  # No more apt repository available, so we need to download and compile the PhpMyAdmin sources by hand
  $cmd wget https://files.phpmyadmin.net/phpMyAdmin/$version/phpMyAdmin-$version-all-languages.tar.gz
  $cmd tar xvf phpMyAdmin-$version-all-languages.tar.gz
  $cmd mv phpMyAdmin-$version-all-languages/ /usr/share/phpmyadmin
  $cmd chown -Rfv www-data:www-data /usr/share/phpmyadmin
  $cmd sh -c 'echo "
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
  Options SymLinksIfOwnerMatch
  DirectoryIndex index.php
  <IfModule mod_php5.c>
    <IfModule mod_mime.c>
      AddType application/x-httpd-php .php
    </IfModule>
    <FilesMatch ".+\.php$">
      SetHandler application/x-httpd-php
    </FilesMatch>

    php_value include_path .
    php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
    php_admin_value open_basedir /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/
    php_admin_value mbstring.func_overload 0
  </IfModule>
  <IfModule mod_php.c>
    <IfModule mod_mime.c>
      AddType application/x-httpd-php .php
    </IfModule>
    <FilesMatch ".+\.php$">
      SetHandler application/x-httpd-php
    </FilesMatch>

    php_value include_path .
    php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
    php_admin_value open_basedir /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/
    php_admin_value mbstring.func_overload 0
  </IfModule>
</Directory>

<Directory /usr/share/phpmyadmin/templates>
    Require all denied
</Directory>
<Directory /usr/share/phpmyadmin/libraries>
    Require all denied
</Directory>
<Directory /usr/share/phpmyadmin/setup/lib>
    Require all denied
</Directory>" > /etc/apache2/conf-available/phpmyadmin.conf'
  $cmd a2enconf phpmyadmin.conf
  $cmd systemctl reload apache2
  # enabling phpmyadmin service account
  $query "CREATE DATABASE IF NOT EXISTS phpmyadmin DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  $query "DROP USER IF EXISTS 'phpmyadmin'@'%'; FLUSH PRIVILEGES;"
  $query "CREATE USER 'phpmyadmin'@'%' IDENTIFIED BY '$pwdpma';"
  $query "GRANT ALL ON phpmyadmin.* TO 'phpmyadmin'@'%';FLUSH PRIVILEGES;"
  # phpmyadmin conf.inc file
  $cmd cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
  $cmd sed -i "s#\$cfg\['Servers'\]\[\$i\]\['host'\] = 'localhost';#\$cfg\['Servers'\]\[\$i\]\['host'\] = '$mysqlhost';#g" /usr/share/phpmyadmin/config.inc.php
  $cmd sed -i "s#// \$cfg\['Servers'\]\[\$i\]\['controlpass'\] = 'pmapass';#\$cfg\['Servers'\]\[\$i\]\['controlpass'\] = '$pwdpma';#g" /usr/share/phpmyadmin/config.inc.php
  $cmd sed -i "s#// \$cfg\['Servers'\]\[\$i\]\['controluser'\] = 'pma';#\$cfg\['Servers'\]\[\$i\]\['controluser'\] = '$userpma';#g" /usr/share/phpmyadmin/config.inc.php
  $cmd sed -i "s#\$cfg\['blowfish_secret'\] = '';#\$cfg\['blowfish_secret'\] = '2O:.uw6-8;Oi9R=3W{tO;/QtZ]4OG:T:';#g" /usr/share/phpmyadmin/config.inc.php
  $cmd systemctl restart apache2
  echo "* PHPMyAdmin installed for $1 *"
}

function resetLXC {
  lxc-stop apache
  lxc-destroy apache
  lxc-stop mysql
  lxc-destroy mysql
  lxc-stop phpmyadmin
  lxc-destroy phpmyadmin
  # Otherwise it will show you the SSH MITM warning.
  ssh-keygen -f "~/.ssh/known_hosts" -R "10.0.3.20"
  ssh-keygen -f "~/.ssh/known_hosts" -R "10.0.3.21"
  ssh-keygen -f "~/.ssh/known_hosts" -R "10.0.3.22"
  echo "* Reset successfull *"
}

if [[ "$1" == "-r" ]]; then
  resetLXC
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Website
createLXC "apache" "rootpassword123" "10.0.3.20" "10.0.3.0" "255.255.255.0" "10.0.3.1"
installApache "apache"
installPhp "apache"
setWebsite "apache" "testlxc.com" "10.0.3.21" "mysql" "admin" "mysqlpassword123"

# MySQL
createLXC "mysql" "rootpassword456" "10.0.3.21" "10.0.3.0" "255.255.255.0" "10.0.3.1"
installMysql "mysql" "rootsqlpassword123" "admin" "mysqlpassword123"

# PHPMyAdmin
createLXC "phpmyadmin" "rootpassword789" "10.0.3.22" "10.0.3.0" "255.255.255.0" "10.0.3.1"
installApache "phpmyadmin"
installPhp "phpmyadmin"
installPhpmyadmin "phpmyadmin" "mysql" "10.0.3.21" "rootsqlpassword123" "root" "pmapassword456"
