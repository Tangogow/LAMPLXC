# LAMP LXC Installer

Bash script to install the LAMP stack on Debian 10 Buster with AMD64 architecture by default, with static IP address assigning, SSH password connection, service users and a basic website to test everything (HTTP only)

## Table of Content

1. [Description](#description)
2. [Getting started](#getting-started)
3. [Production use](#production-use)
4. [Check](#Check)
5. [Debugging](#debugging)
6. [Reset](#reset)
7. [Todo](#todo)

## Description

This script will install 3 LXC container:
1. Website container with Apache and PHP
2. MySQL container
3. PhpMyAdmin container with Apache and PHP

The website code will try a MySQL connection to see if everything works.

Apache and PHP are needed by PhpMyAdmin in the same container since it rely on them.

You can also change very easily all version for each software.

## Getting started

Edit the `lamplxc.sh` file with your settings then:

```bash
sudo echo "10.0.3.20 testlxc.com " >> /etc/hosts # for localhost testing purpose
chmod +x lamplxc.sh
sudo./lamplxc.sh
```

#### Check

  - with `lxc-ls` that the containers are running
  - the website at http://test.com
  - PHPMyAdmin logins at http://10.0.3.22/phpmyadmin (the mysql user account *admin:mysqlpassword123*)
  - PHP Infos at http://10.0.3.20/php.php and http://10.0.3.22/php.php
  - Apache default page at http://10.0.3.20 and http://10.0.3.22

#### Debugging

  - Ping from host to container or container to container.
  - Container shell: `lxc-attach <containerName>`
  - SSH connection with `ssh@<ip>` to any container or from any container, ie: `ssh@10.0.3.21` with root login.
  - MySQL connecion with `mysql -u root -p -h 10.0.3.21` from your host or any container

#### Reset

If you want to reset everything and destroy the containers: `sudo lxclamp.sh -r`

## Production use

1. Remove the `php.php` files
2. Uncomment the upgrade line in `CreateLXC`.
3. Replace the weak example passwords by strong ones.
4. Don't forget to create a service user with some sudo rights and disabling the SSH root remote login afterwards.
5. (Optional) Add your SSH pubkey to the authorized SSH file and disable password authentication in `/etc/ssh/sshd_config`.

## Todo

- [x] Reset option to test (with known_hosts deletion)
- [ ] SSH keyring option
- [ ] Container service user with sudo
- [ ] DHCP option instead of static
- [ ] TLS certbot for HTTPS certificates
