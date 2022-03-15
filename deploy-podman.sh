#!/bin/bash
#%
#% UnifiController deployer
#%
#%   Requires Podman.
#%   Builds and deploys a local image
#%
#% Usage:
#%   ${THIS_FILE} [Options]
#%
#% Options:
#%   -v, --version <version>       Version number of UnifiController to install, default is: 7.0.23
#%   -g, --generate                Generate the systemd unit file, for auto-starting rootless podman pods and/or containers. Default is false
#%   --mongoDBversion=<version>    Version number of UnifiController to install, default is: 4.2
#%   --debianVersion=<version>     Specify the version of Debian the container uses; default is: buster
#%   --env=/path/to/file           Specify path to env file. Default is ./.env
#%   -h, -?, --help                Displays this help dialog
#%

# Specify halt conditions (errors, unsets, non-zero pipes) and verbosity
set -euo pipefail
[ ! "${VERBOSE:-}" == "true" ] || set -x

die() { 
    echo "$*" 1>&2 ; 
    exit 1; 
}

CONTAINER_NAME="unificontroller"
UNIFI_VERSION="7.0.23"
MONGODB_VERSION="4.2"
declare -a MONGODB_VERSION_SUPPORTED=("4.2" "4.4" "5.0")
DEB_VERSION="buster"
DEB_VERSION_MIN="buster"
DEB_VERSION_MAX="bullseye"
ENVFILE="$(pwd)/.env"
DOCKERFILE_LOCATION="."
ENV="local"
ISGENERATE=false

# Check parameters - default to showing the help header from this script
while true 
do
    case ${1:-""} in
        --debianVersion=?*) # Delete everything up to "=" and assign the remainder:
            DEB_VERSION=${1#*=}

            case ${DEB_VERSION} in
                bullseye)
                    DOCKERFILE_LOCATION="-f Dockerfile_bullseye"
                    ;;
                buster)
                    DOCKERFILE_LOCATION="."
                    ;;
            esac
            ;;
        --debianVersion=) # Handle the case of an empty --deb=
            die 'ERROR: "--deb" requires a non-empty option argument, and only supports versions '"${DEB_VERSION_MIN}"' to '"${DEB_VERSION_MAX}"'.'
            ;;            
        --env=?*) # Delete everything up to "=" and assign the remainder:
            ENVFILE=${1#*=}
            ;;
        --env=) # Handle the case of an empty --env=
            die 'ERROR: "--env" requires a non-empty option argument.'
            ;;
        -g|--generate)
            ISGENERATE=true
            ;;
        -h|-\?|--help)
            # Cat this file, grep #% lines and clean up with sed
            THIS_FILE="$(dirname ${0})/$(basename ${0})"
            cat ${THIS_FILE} |
                grep "^#%" |
                sed -e "s|^#%||g" |
                sed -e "s|\${THIS_FILE}|${THIS_FILE}|g"
            exit
            ;;                        
        --mongoDBversion=?*) # Delete everything up to "=" and assign the remainder:
            MONGODB_VERSION=${1#*=}            
            IS_SUPPORTED=false

            for i in "${MONGODB_VERSION_SUPPORTED[@]}"
            do
                if [[ $MONGODB_VERSION == $i ]] ; then
                     # The value is supported, set the flag & exit the loop
                     IS_SUPPORTED=true
                     break
                fi
            done

            if [[ $IS_SUPPORTED = false ]] ; then
                 printf -v joined '%s,' "${MONGODB_VERSION_SUPPORTED[@]}"
                 die 'ERROR: "--mongoDBversion" only supports versions '"${joined%,}"'.'
            fi
            ;;           
        --mongoDBversion=) # Handle the case of an empty
            die 'ERROR: "--mongoDBversion" requires a non-empty option argument, and only supports versions '"${DEB_VERSION_MIN}"' to '"${DEB_VERSION_MAX}"'.'
            ;;             
        -v|--version) 
            if [ "$2" ] 
            then
                UNIFI_VERSION=$2
                shift
            else
                die 'ERROR: "--version" requires a non-empty option argument.'
            fi
            ;;
        --)  # End of all options.
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            die ''
            ;;
        *) break
    esac
    shift
done

source "${ENVFILE}"

# Verify prerequisites
if ( ! ( which podman))
then
    die '\nPlease verify podman is installed\n'
fi

# Set image and build, if necessary
if [ "${ENV}" == "local" ]
then

    podman build -t "${CONTAINER_NAME}":"${UNIFI_VERSION}" --build-arg UNIFI_VERSION="${UNIFI_VERSION}" --build-arg MONGODB_VERSION="${MONGODB_VERSION}" ${DOCKERFILE_LOCATION}
    IMAGE="localhost/${CONTAINER_NAME}:${UNIFI_VERSION}"
   
else
    IMAGE="dockerhub.com/${CONTAINER_NAME}:${UNIFI_VERSION}"
fi

# To allow for systemd services to be started at boot without login (and continue running after logout) of 
# the individual users, you need to enable "lingering". You can do that using: loginctl enable-linger <username>
# http://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html

# if "${ISGENERATE}"
# then
#     podman generate systemd --new --files --name "${CONTAINER_NAME}"

#     ln -s container-"${CONTAINER_NAME}".service /etc/systemd/system

#     if ( (which systemctl))
#     then
#         systemctl --user enable container-"${CONTAINER_NAME}".service

#         # Confirm systemd config
#         systemctl --user is-enabled container-"${CONTAINER_NAME}".service

#         # Start the service
#         systemctl --user start container-"${CONTAINER_NAME}".service

#         # Confirm the status of the service
#         systemctl --user status container-"${CONTAINER_NAME}".service
#     else
#         die '\nPlease verify systemctl/systemd is installed\n'
#     fi
# if