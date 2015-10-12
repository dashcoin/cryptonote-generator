#! /usr/bin/env bash


# Bash script for automatic generation and deployment

# Exit immediately if an error occurs, or if an undeclared variable is used
set -o errexit

[ "$OSTYPE" != "win"* ] || die "Install MinGW to use on Windows"

# For bold text
bold=$(tput bold)
normal=$(tput sgr0)

# Set directory vars
. "vars.cfg"

# Perform cleanup on exit
function finish {
	# Remove temporary files if exist
	echo "Remove temporary files..."
	rm -f "${UPDATES_PATH}"
	rm -f "${BASH_CONFIG}"
	rm -rf "${TEMP_PATH}"
}
trap finish EXIT

# Generate source code and compile 
function generate_coin {
	# Define coin paths
	export BASE_COIN_PATH="${WORK_FOLDERS_PATH}/${__CONFIG_base_coin_name}"
	export NEW_COIN_PATH="${WORK_FOLDERS_PATH}/${__CONFIG_core_CRYPTONOTE_NAME}"
	if [ -d "${BASE_COIN_PATH}" ]; then
		cd "${BASE_COIN_PATH}"
		echo "Updating ${__CONFIG_base_coin_name}..."
		git pull
		cd "${PROJECT_DIR}"
	else
		echo "Cloning ${__CONFIG_base_coin_name}..."
		git clone "${__CONFIG_base_coin_git}" "${BASE_COIN_PATH}"
	fi

	# Exit if base coin does not exists
	if [ ! -d "${BASE_COIN_PATH}" ]; then
		echo "Base coin does not exists"
		echo "Abort clone generation"
		exit 4
	fi

	echo "Make temporary ${__CONFIG_base_coin_name} copy..."
	[ -d "${TEMP_PATH}" ] || mkdir -p "${TEMP_PATH}"
	cp -af "${BASE_COIN_PATH}/." "${TEMP_PATH}"

	# Plugins
	echo "Personalize base coin source..."
	export __CONFIG_plugins_text="${__CONFIG_plugins[@]}"
	for plugin in "${__CONFIG_plugins[@]}"
	do
		echo "${bold}Execute ${PLUGINS_PATH}/${plugin}${normal}"
		python "lib/file-modification.py" --plugin "${PLUGINS_PATH}/${plugin}" --config=$CONFIG_FILE --source=${TEMP_PATH}
	done

	[ -d "${NEW_COIN_PATH}" ] || mkdir -p "${NEW_COIN_PATH}"

	echo "Create patch"
	cd "${WORK_FOLDERS_PATH}";
	EXCLUDE_FROM_DIFF="-x '.git'"
	if [ -d "${BASE_COIN_PATH}/build" ]; then
		EXCLUDE_FROM_DIFF="${EXCLUDE_FROM_DIFF} -x 'build'"
	fi
	diff -Naur -x .git ${NEW_COIN_PATH##${WORK_FOLDERS_PATH}/} ${TEMP_PATH##${WORK_FOLDERS_PATH}/} > "${UPDATES_PATH}"  || [ $? -eq 1 ]

	echo "Apply patch"
	[ -d "${NEW_COIN_PATH}" ] || mkdir -p "${NEW_COIN_PATH}"
	if [ ! -z "${UPDATES_PATH}"  ]; then
		# Generate new coin
		cd "${NEW_COIN_PATH}" && patch -s -p1 < "${UPDATES_PATH}" && cd "${SCRIPTS_PATH}"

		bash "${SCRIPTS_PATH}/compile.sh" -c "${COMPILE_ARGS}" -z
	fi
}

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-h] [-f FILE] [-c <string>]
Reads a config file and creates and compiles Cryptonote coin. "config.json" as default

    -h          display this help and exit
    -f          config file
    -c          compile arguments
EOF
}   

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
CONFIG_FILE='config.json'
COMPILE_ARGS=''

while getopts "h?f:c:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    f)  CONFIG_FILE=${OPTARG}
        ;;
    c)  COMPILE_ARGS=${OPTARG}
        ;;
    esac
done

shift $((OPTIND-1))

# Setting config file
if [[ "${CONFIG_FILE}" != /* ]]; then
	CONFIG_FILE="${CONFIG_PATH}/${CONFIG_FILE}"
fi

if [ ! -f ${CONFIG_FILE} ]; then
	echo "ERROR: config file does not exits"	
	exit
fi

[ -d "${WORK_FOLDERS_PATH}" ] || mkdir -p "${WORK_FOLDERS_PATH}"

# Get environment environment_variables
python "lib/environment_variables.py" --config=$CONFIG_FILE --output=$BASH_CONFIG
if [ ! -f ${BASH_CONFIG} ]; then
	echo "Config file was not translated to bash."
	echo "Abort coin generation"
	exit 3
fi
source ${BASH_CONFIG}

generate_coin
