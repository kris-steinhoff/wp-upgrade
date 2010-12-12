#!/bin/bash

usage="`basename ${0}` path/to/site"

function get()
{
    # usage: get variable_name prompt default
    prompt=${1}
    shift 1
    default=${*}
    read -p "${prompt} [${default}]: " input 
    if [ "x${input}" != "x" ]; then
        echo ${input}
    else
        echo ${default}
    fi
}

export COLOR_PROMPT_RED_BOLD="\[\e[31;0m\]"
export COLOR_RED="\e[31m"
export COLOR_YELLOW="\e[33m"
export COLOR_GREEN="\e[32m"
export COLOR_NONE="\e[0m"

function check_point()
{
    if [ "x${1}" = "x" ]; then
        prompt="Continue?"
    else
        prompt=${1}
    fi

    con=`get "$prompt (y/n)" "y"`
    if [ "x${con}" = 'xy' ]; then
        return 0
    fi

    return 1
}

function notice()
{
    msg=${*}
    echo -e "${COLOR_GREEN}${msg}${COLOR_NONE}"
}

function warning()
{
    msg=${*}
    echo -e "${COLOR_YELLOW}WARNING ${msg}${COLOR_NONE}"
}

function error()
{
    msg=${*}
    echo -e "${COLOR_RED}ERROR ${msg}${COLOR_NONE}"
    exit 1
}

function echo_php_var()
{
    # usage: get variable_name prompt default
    var=${1}
    file=${2}
    if [ ! -r "${file}" ]; then
        error "Could not read file ${file}"
    fi

    # echo php\ -d\ \"display_errors\=0\"\ -r\ \"include\ \\\"\${file}\\\"\;\ echo\ \\\\\$\${version}.\;\"\ 2\>\ /dev/null
    # export ${var}=`php -d "display_errors=0" -r "include \"${file}\"; echo \\$${var}.;" 2> /dev/null`
    # echo php -d \"display_errors=0\" -r \"include \\\"${file}\\\"\; echo \\\$${var}\;\"
    # export ${var}=`php -d "display_errors=0" -r "include \"${file}\"; echo \$${var};"`
    # export ${var}=`php -r "include \"${file}\"; echo \$$var.;" 2> /dev/null`

    php -d "display_errors=0" -r "include \"${file}\"; echo ${var};" 2> /dev/null
}

if [ "x${1}" = "x" ]; then
    echo $usage
    exit 0
elif [ "${1}" = "-h" ]; then
    echo $usage
    exit 1
else 
    site="${1}"
fi

if [ ! -r "${site}/wp-includes/version.php" ]; then
    error "Could not file a Wordpress instance at ${site}"
fi

wp_version=`echo_php_var '$wp_version' "${site}/wp-includes/version.php"`
echo "Current Wordpress version: ${wp_version}"

if [ "x${wp_version}" = "x" ]; then
    warning "Could not read Wordpress version from ${site}"
    check_point || exit 1
else
    ver_check_cmd="lynx --dump http://api.wordpress.org/core/version-check/1.0/?version=${wp_version}"
    case `${ver_check_cmd} | head -1` in
        "latest")
            notice "The Wordpress instance at $site is up to date."
            exit 0;
            ;;
        "upgrade")
            warning "The Wordpress instance at $site is out of date."
            check_point || exit 1
            ;;
        *)
            warning "Could not check for newer version."
            check_point || exit 1
            ;;
    esac
fi

# read config file for db creds
DB_USER=`echo_php_var 'DB_USER' "${site}/wp-config.php"`
DB_PASSWORD=`echo_php_var 'DB_PASSWORD' "${site}/wp-config.php"`
DB_HOST=`echo_php_var 'DB_HOST' "${site}/wp-config.php"`
DB_NAME=`echo_php_var 'DB_NAME' "${site}/wp-config.php"`
table_prefix=`echo_php_var '$table_prefix' "${site}/wp-config.php"`

db_options=`echo -u $DB_USER -p$DB_PASSWORD -h $DB_HOST $DB_NAME`

# read db for site name, use in default backup file name
query="SELECT option_value FROM ${table_prefix}options WHERE option_name = 'blogname';"
site_name=`echo $query | mysql $db_options | tail -1 | sed s/\ /_/g`

check_point "Create backup?"; rc=$?
if [ $rc -eq 0 ]; then
    datestamp=`date +%Y-%m-%d`
    backup_dir=${site_name}_backup_$datestamp
    backup_dir_inc=1
    while test -e "$backup_dir"; do
        backup_dir_inc=`expr $backup_dir_inc + 1`
        backup_dir=$HOME/${site_name}_backup_${datestamp}_${backup_dir_inc}
    done

    mkdir -p "$backup_dir" && 
    notice "Created backup directory $backup_dir" || error "Backup directory $backup_dir could not be created"

    notice "Copying ${site} to ${backup_dir}/wordpress"
    cp -rp "${site}" "${backup_dir}/wordpress" || error "Could not copy ${site} to ${backup_dir}/wordpress"

    tables=""
    if [ "x$table_prefix" != "x" ]; then
        tables=`echo show tables | mysql $db_options | grep ^$table_prefix`
        notice "Tables to export: $tables"
    fi

    notice "Dumping Wordpress tables into ${backup_dir}/database.mysql"
    mysqldump $db_options $tables > ${backup_dir}/database.mysql || error "Could not dump Wordpress tables into ${backup_dir}/database.mysql"

    notice "Backup complete: ${PWD}/$backup_dir"
fi

site_url=`echo 'select option_value from spointy_wp_options where option_name = "blogname";' | mysql $db_options | tail -1 | sed s/\ /_/g`

# read db for site name, use in default backup file name
query="SELECT option_value FROM ${table_prefix}options WHERE option_name = 'siteurl';"
siteurl=`echo $query | mysql $db_options | tail -1 | sed s/\ /_/g`
echo Disable the Wordpress plugins: ${siteurl}/wp-admin/plugins.php
check_point || exit 1

rm -rf .wp-upgrade_tmp || error "Could not delete previous temporary directory ${PWD}/.wp-upgrade_tmp"
mkdir .wp-upgrade_tmp || error "Could not create temporary directory ${PWD}/.wp-upgrade_tmp"
cd .wp-upgrade_tmp

notice "Fetching the latest version on Wordpress: http://wordpress.org/latest.tar.gz"
wget http://wordpress.org/latest.tar.gz || error "Could not download the latest version on Wordpress."

notice "Decompressing latest.tar.gz"
tar xf latest.tar.gz || error "Could not decompress latest.tar.gz"

cd ..

notice "Copying Wordpress files to ${site}"
cp -r .wp-upgrade_tmp/wordpress/* ${site}/ || error "Could not copy Wordpress files to ${site}"

echo Disable the Wordpress plugins: ${siteurl}wp-admin/plugins.php

wp_version=`echo_php_var '$wp_version' "${site}/wp-includes/version.php"`
echo "New Wordpress version: ${wp_version}"

notice "Database upgrade may be necessary: ${siteurl}//wp-admin/upgrade.php"

exit 0
