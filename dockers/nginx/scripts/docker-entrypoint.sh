#!/bin/sh -eu

###
### Variables
###
DEBUG_COMMANDS=0

HTTPD_CONF="/etc/nginx/nginx.conf"



###
### Functions
###
runsu() {
	_cmd="${1}"
	_debug="0"

	_red="\033[0;31m"
	_green="\033[0;32m"
	_reset="\033[0m"
	_user="$(whoami)"

	# If 2nd argument is set and enabled, allow debug command
	if [ "${#}" = "2" ]; then
		if [ "${2}" = "1" ]; then
			_debug="1"
		fi
	fi


	if [ "${DEBUG_COMMANDS}" = "1" ] || [ "${_debug}" = "1" ]; then
		printf "${_red}%s \$ ${_green}sudo ${_cmd}${_reset}\n" "${_user}"
	fi

	/usr/local/bin/gosu root sh -c "LANG=C LC_ALL=C ${_cmd}"
}


log() {
	_lvl="${1}"
	_msg="${2}"

	_clr_ok="\033[0;32m"
	_clr_info="\033[0;34m"
	_clr_warn="\033[0;33m"
	_clr_err="\033[0;31m"
	_clr_rst="\033[0m"

	if [ "${_lvl}" = "ok" ]; then
		printf "${_clr_ok}[OK]   %s${_clr_rst}\n" "${_msg}"
	elif [ "${_lvl}" = "info" ]; then
		printf "${_clr_info}[INFO] %s${_clr_rst}\n" "${_msg}"
	elif [ "${_lvl}" = "warn" ]; then
		printf "${_clr_warn}[WARN] %s${_clr_rst}\n" "${_msg}" 1>&2	# stdout -> stderr
	elif [ "${_lvl}" = "err" ]; then
		printf "${_clr_err}[ERR]  %s${_clr_rst}\n" "${_msg}" 1>&2	# stdout -> stderr
	else
		printf "${_clr_err}[???]  %s${_clr_rst}\n" "${_msg}" 1>&2	# stdout -> stderr
	fi
}



################################################################################
# BOOTSTRAP
################################################################################

if set | grep '^DEBUG_COMPOSE_ENTRYPOINT='  >/dev/null 2>&1; then
	if [ "${DEBUG_COMPOSE_ENTRYPOINT}" = "1" ]; then
		DEBUG_COMMANDS=1
	fi
fi


################################################################################
# MAIN ENTRY POINT
################################################################################

###
### Adjust timezone
###

if ! set | grep '^TIMEZONE='  >/dev/null 2>&1; then
	log "warn" "\$TIMEZONE not set."
else
	if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
		# Unix Time
		log "info" "Setting docker timezone to: ${TIMEZONE}"
		runsu "rm /etc/localtime"
		runsu "ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"
	else
		log "err" "Invalid timezone for \$TIMEZONE."
		log "err" "\$TIMEZONE: '${TIMEZONE}' does not exist."
		exit 1
	fi
fi
log "info" "Docker date set to: $(date)"


###
### Adjust number of CPU cores to worker_processes
###
CPU="$( getconf _NPROCESSORS_ONLN )"
runsu "sed -i'' 's/^worker_processes.*$/worker_processes ${CPU};/g' ${HTTPD_CONF}"



###
### Prepare PHP-FPM
###
if ! set | grep '^PHP_FPM_ENABLE=' >/dev/null 2>&1; then
	log "info" "\$PHP_FPM_ENABLE not set. PHP-FPM support disabled."
else
	if [ "${PHP_FPM_ENABLE}" = "1" ]; then

		# PHP-FPM address
		if ! set | grep '^PHP_FPM_SERVER_ADDR=' >/dev/null 2>&1; then
			log "err" "PHP-FPM enabled, but \$PHP_FPM_SERVER_ADDR not set."
			exit 1
		fi
		if [ "${PHP_FPM_SERVER_ADDR}" = "" ]; then
			log "err" "PHP-FPM enabled, but \$PHP_FPM_SERVER_ADDR is empty."
			exit 1
		fi

		# PHP-FPM port
		if ! set | grep '^PHP_FPM_SERVER_PORT=' >/dev/null 2>&1; then
			log "info" "PHP-FPM enabled, but \$PHP_FPM_SERVER_PORT not set."
			lgo "info" "Defaulting PHP-FPM port to 9000"
			PHP_FPM_SERVER_PORT="9000"
		elif [ "${PHP_FPM_SERVER_PORT}" = "" ]; then
			log "info" "PHP-FPM enabled, but \$PHP_FPM_SERVER_PORT is empty."
			lgo "info" "Defaulting PHP-FPM port to 9000"
			PHP_FPM_SERVER_PORT="9000"
		fi

		NGINX_VHOST_CONF="/etc/nginx/conf.d/localhost.conf"

		if [ ! -f "${NGINX_VHOST_CONF}" ]; then
			log "info" "${NGINX_VHOST_CONF} not available."
			log "info" "You probably have mounted your custom configuration into: /etc/nginx/conf.d"
			log "info" "Unable to setup PHP-FPM to the default virtualhost."

		else
			# Enable
			log "info" "Enabling PHP-FPM at: ${PHP_FPM_SERVER_ADDR}:${PHP_FPM_SERVER_PORT}"
			runsu "sed -i'' 's|#__PHP_FPM__||g' ${NGINX_VHOST_CONF}"
			runsu "sed -i'' 's|__PHP_FPM_ADDR__|${PHP_FPM_SERVER_ADDR}|g' ${NGINX_VHOST_CONF}"
			runsu "sed -i'' 's|__PHP_FPM_PORT__|${PHP_FPM_SERVER_PORT}|g' ${NGINX_VHOST_CONF}"
		fi

	fi
fi



###
### Add new Nginx configuration dir
###
if ! set | grep '^CUSTOM_HTTPD_CONF_DIR='  >/dev/null 2>&1; then
	log "info" "\$CUSTOM_HTTPD_CONF_DIR not set. No custom include directory added."
else
	# Tell nginx to use the following instead of its default /etc/httpd/conf.d
	log "info" "Adding custom include directory: ${CUSTOM_HTTPD_CONF_DIR}"
	runsu "sed -i'' 's|/etc/nginx/conf.d|${CUSTOM_HTTPD_CONF_DIR}|g' ${HTTPD_CONF}"
fi



###
### Start
###
log "info" "Starting $(/usr/sbin/nginx -v 2>&1)"
runsu "/usr/sbin/nginx -g 'daemon off;'" "1"
