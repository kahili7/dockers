#!/bin/sh -eu

##
## VARIABLES
##
VERSION_GOSU="1.2"
HTTPD_CONF="/etc/nginx/nginx.conf"

MY_USER="apache"
MY_GROUP="apache"
MY_UID="48"
MY_GID="48"


##
## FUNCTIONS
##
print_headline() {
	_txt="${1}"
	_blue="\033[0;34m"
	_reset="\033[0m"

	printf "${_blue}\n%s\n${_reset}" "--------------------------------------------------------------------------------"
	printf "${_blue}- %s\n${_reset}" "${_txt}"
	printf "${_blue}%s\n\n${_reset}" "--------------------------------------------------------------------------------"
}

run() {
	_cmd="${1}"

	_red="\033[0;31m"
	_green="\033[0;32m"
	_reset="\033[0m"
	_user="$(whoami)"

	printf "${_red}%s \$ ${_green}${_cmd}${_reset}\n" "${_user}"
	sh -c "LANG=C LC_ALL=C ${_cmd}"
}


################################################################################
# MAIN ENTRY POINT
################################################################################

##
## Adding Users
##
print_headline "1. Adding Users"
run "groupadd -g ${MY_GID} -r ${MY_GROUP}"
run "adduser ${MY_USER} -u ${MY_UID} -M -s /sbin/nologin -g ${MY_GROUP}"

###
### Configure Nginx
###
### (Remove all custom config)
###
print_headline "2. Configure Nginx"

# Clean all configs
if [ ! -d "/etc/nginx/conf.d/" ]; then
	run "mkdir -p /etc/nginx/conf.d/"
else
	run "rm -rf /etc/nginx/conf.d/*"
fi


# Add Base Configuration
{
	echo "# User/Group";
	echo "user ${MY_USER} ${MY_GROUP};";
	echo;

	echo "# Set to the number of processors";
	echo "# grep processor /proc/cpuinfo | wc -l";
	echo "worker_processes 1;";
	echo;

	echo "# [debug | info | notice | warn | error | crit | alert | emerg];";
	echo "error_log /var/log/nginx/error.log warn;";
	echo;

	echo "events {";
	echo "    # Sets the maximum number of simultaneous connections that can be opened by a worker process.";
	echo "    worker_connections  1024;";
	echo "}";
	echo;

	echo "http {";
	echo "    include       mime.types;";
	echo "    default_type  application/octet-stream;";
	echo;
	echo "    log_format    main '\$remote_addr - \$remote_user [\$time_local] \"\$request\" '";
	echo "                       '\$status \$body_bytes_sent \"\$http_referer\" '";
	echo "                       '\"\$http_user_agent\" \"\$http_x_forwarded_for\"';";
	echo;
	echo "    access_log    /var/log/nginx/access.log  main;";
	echo;
	echo;
	echo "    # Custom includes";
	echo "    include       /etc/nginx/conf.d/*.conf;";
	echo;
	echo "}";
	echo;
} > "${HTTPD_CONF}"

# Add Custom http Configuration
{
	echo "# [performance] Nginx 3 most famous options!!!11";
	echo "sendfile      on;";
	echo;

	echo "# tcp_nopush option will make nginx to send all header files";
	echo "# in a single packet rather than seperate packets.";
	echo "tcp_nopush    on;";
	echo;

	echo "# don't buffer data-sends (disable Nagle algorithm).";
	echo "# Good for sending frequent small bursts of data in real time.";
	echo "tcp_nodelay   on;";
	echo;
} > "/etc/nginx/conf.d/http-defaults.conf"

# Add Default vhost Configuration
{
	echo "server {";
	echo "    listen      80 default_server;";
	echo "    server_name phpbb.magelan.ru;";
	echo;

	echo "    root        /var/www/html;";
	echo "    index       index.html index.htm index.php;";
	echo;

	echo "    access_log  /var/log/nginx/localhost-access.log main;";
	echo "    error_log	  /var/log/nginx/localhost-error.log warn;";
	echo;

	# PHP-FPM Section
	# '#__PHP_FPM__' will be replaced within the entrypoint
	# if ENABLE_PHP_FPM is set tot true.
	echo "    # Front-controller pattern as recommended by the nginx docs";
	echo "    #__PHP_FPM__location / {";
	echo "    #__PHP_FPM__    try_files \$uri \$uri/ /index.php;";
	echo "    #__PHP_FPM__}";
	echo;
	echo "    # Front-controller pattern as recommended by the nginx docs";
	echo "    #__PHP_FPM__location ~ \.php?\$ {";
	echo "    #__PHP_FPM__    try_files \$uri = 404;";
	echo "    #__PHP_FPM__    include fastcgi_params;";
	echo "    #__PHP_FPM__    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;";
	echo "    #__PHP_FPM__    fastcgi_split_path_info ^(.+\.php)(.*)\$;";
	echo "    #__PHP_FPM__    fastcgi_pass __PHP_FPM_ADDR__:__PHP_FPM_PORT__;";
	echo "    #__PHP_FPM__    fastcgi_index index.php;";
	echo "    #__PHP_FPM__    fastcgi_intercept_errors on;";
	echo "    #__PHP_FPM__}";
	echo;

	echo "location /install/ {";
	echo "	try_files \$uri \$uri/ @rewrite_installapp;";
	
	echo "	location ~ \.php(/|\$) {";
	echo "		include fastcgi_params;";
	echo "		fastcgi_split_path_info ^(.+\.php)(/.*)\$;";
	echo "		fastcgi_pass __PHP_FPM_ADDR__:__PHP_FPM_PORT__;";
	echo "		fastcgi_param PATH_INFO \$fastcgi_path_info;";
	echo "		fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;";
	echo "		fastcgi_param DOCUMENT_ROOT \$realpath_root;";
	echo "		try_files \$uri \$uri/ /install/app.php\$is_args\$args;";
	echo "	}";
	echo "}";	
	
	echo "location @rewrite_installapp {";
	echo "	rewrite ^(.*)\$ /install/app.php/\$1 last;";	
	echo "}";
	
	
	
	
	
	
	
	echo "    # deny access to .htaccess files, if Apache's document root";
	echo "    # concurs with nginx's one";
	echo "    location ~ /\.ht {";
	echo "        deny  all;";
	echo "    }";
	echo;

	echo "    # disallow access to git configs path";
	echo "    location ~ /\.git {";
	echo "        deny all;";
	echo "    }";

	echo;

	echo "}";
	echo;

} > "/etc/nginx/conf.d/localhost.conf"


# Add test Page
if [ ! -d "/var/www/html" ]; then
	run "mkdir -p /var/www/html"
else
	run "rm -rf /var/www/html/*"
fi
run "echo '<?php phpversion(); ?>' > /var/www/html/index.php"
run "echo 'It works' > /var/www/html/index.html"
run "chown -R ${MY_USER}:${MY_GROUP} /var/www/html"

###
### Installing Gosu
###
print_headline "3. Installing Gosu"
run "gpg --keyserver pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4"
run "curl -SL -o /usr/local/bin/gosu https://github.com/tianon/gosu/releases/download/${VERSION_GOSU}/gosu-amd64 --retry 999 --retry-max-time 0 -C -"
run "curl -SL -o /usr/local/bin/gosu.asc https://github.com/tianon/gosu/releases/download/${VERSION_GOSU}/gosu-amd64.asc --retry 999 --retry-max-time 0 -C -"
run "gpg --verify /usr/local/bin/gosu.asc"
run "rm /usr/local/bin/gosu.asc"
run "rm -rf /root/.gnupg/"
run "chown root /usr/local/bin/gosu"
run "chmod +x /usr/local/bin/gosu"
run "chmod +s /usr/local/bin/gosu"

###
### Creating Mass VirtualHost dirs
###
print_headline "4. Creating Mass VirtualHost dirs"
run "mkdir -p /shared/httpd"
run "chmod 775 /shared/httpd"
run "chown ${MY_USER}:${MY_GROUP} /shared/httpd"

###
### Cleanup unecessary packages
###
print_headline "5. Cleanup unecessary packages"
run "yum -y autoremove"
