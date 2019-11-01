#!/usr/bin/env bash
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

C_RED=$(tput setaf 9)
C_GREEN=$(tput setaf 10)
C_YELLOW=$(tput setaf 11)
C_BLUE=$(tput setaf 12)
C_DARK_BLUE=$(tput setaf 4)
C_RESET=$(tput sgr0)

PATCH_FOLDER=$(mktemp -d working.XXXXXXXXXX) || error "Failed to create temp folder." 01

# Logging functions
function info {
    echo "${C_BLUE}[I] ${1}${C_RESET}"
}

function warning {
    echo "${C_YELLOW}[W] ${1}${C_RESET}"
}

function error {
    echo
    echo "${C_RED}[E-${2}] ${1}${C_RESET}"
    cleanup
    exit 1
}

function print_apk_info {
    AAPT_OUTPUT="$(aapt dump badging "${1}")"
    APP_LABEL="$(echo "${AAPT_OUTPUT}" | \
        sed -En "s/application-label:'(.*)'/\1/p")"
    PACKAGE_NAME="$(echo "${AAPT_OUTPUT}" | \
        sed -En "s/package: name='([^']*)'.*/\1/p")"
    VERSION_CODE="$(echo "${AAPT_OUTPUT}" | \
        sed -En "s/.*versionCode='([^']*)'.*/\1/p")"
    VERSION_NAME="$(echo "${AAPT_OUTPUT}" | \
        sed -En "s/.*versionName='([^']*)'.*/\1/p")"
    MIN_SDK="$(echo "${AAPT_OUTPUT}" | sed -En "s/sdkVersion:'(.*)'/\1/p")"
    TARGET_SDK="$(echo "${AAPT_OUTPUT}" | \
        sed -En "s/targetSdkVersion:'(.*)'/\1/p")"
    SUPPORTED_ARCHS="$(echo "${AAPT_OUTPUT}" | \
        sed -En "s/native-code: (.*)/\1/p")"

    echo "${C_GREEN}Package info for ${1}:${C_RESET}"
    echo "${C_BLUE}App Label:${C_RESET} ${APP_LABEL}"
    echo "${C_BLUE}Package Name:${C_RESET} ${PACKAGE_NAME}"
    echo "${C_BLUE}Version Name:${C_RESET} ${VERSION_NAME}"
    echo "${C_BLUE}Version Code:${C_RESET} ${VERSION_CODE}"
    echo "${C_BLUE}Minimun SDK:${C_RESET} ${MIN_SDK}"
    echo "${C_BLUE}Target SDK:${C_RESET} ${TARGET_SDK}"
    echo "${C_BLUE}Supported Architectures:${C_RESET} ${SUPPORTED_ARCHS}"
}

function print_apk_signed_info {
    APK_CERT_DNAME="Not found"
    APK_CERT_SEARCH="$(unzip -l "${1}" | grep META-INF/.*\.RSA | \
        awk '{ print $4 }')"
    if [[ "${APK_CERT_SEARCH}" ]]; then
        APK_CERT_DNAME="$(unzip -p "${1}" "${APK_CERT_SEARCH}" | keytool -printcert | sed -En "s/Owner: (.*)/\1/p")"
    fi

    APKSIGNER_OUTPUT="$(apksigner verify -v "${1}")"
    V1_SCHEME="$(echo "${APKSIGNER_OUTPUT}" | sed -n "s/Verified using v1 scheme (JAR signing): //p")"
    V2_SCHEME="$(echo "${APKSIGNER_OUTPUT}" | sed -n "s/Verified using v2 scheme (APK Signature Scheme v2): //p")"
    V3_SCHEME="$(echo "${APKSIGNER_OUTPUT}" | sed -n "s/Verified using v3 scheme (APK Signature Scheme v3): //p")"

    echo "${C_GREEN}Signature info for ${1}:${C_RESET}"
    echo "${C_BLUE}DNAME:${C_RESET} ${APK_CERT_DNAME}"
    echo "${C_BLUE}Signed v1:${C_RESET} ${V1_SCHEME}"
    echo "${C_BLUE}Signed v2:${C_RESET} ${V2_SCHEME}"
    echo "${C_BLUE}Signed v3:${C_RESET} ${V3_SCHEME}"
}

function check_command {
    command -v "${1}" > /dev/null || error "This program needs \"${1}\" to run." 10
}

function cleanup {
    info "Cleaning up..."
    rm -fr "${PATCH_FOLDER}"
}

function ctrlc {
    info "SIGINT received. Exiting..."
    cleanup
    exit 1
}

trap ctrlc SIGINT

echo "# ================================================ #"
echo "| ${C_GREEN}Manual Modding Tool v1.0.0${C_RESET} - developed by Hexile |"
echo "# ================================================ #"

KEYSTORE="mod_script.keystore"
KEYSTORE_PASS="mod_script_key_password"
KEYSTORE_ALIAS="mod_script_keystore"
KEYSTORE_DNAME="CN=Modded with MMT, O=Hexile, DC=https://github.com/giacomoferretti/apk-modding-tools"

COMMAND_USAGE="
Usage:
./$(basename "${0}") [-h|--help] [-k|--keep-folder] [-r|--no-res] [-s|--no-src] <APK_PATH>
"

# Argument parser
POSITIONAL=()
while [[ ${#} -gt 0 ]]; do
    key="$1"

    case ${key} in
        -h|--help)
        echo "${COMMAND_USAGE}"
        exit
        ;;
        -k|--keep-folder)
        KEEP_FOLDER=true
        shift
        ;;
        -r|--no-res)
        NO_RES="-r"
        shift
        ;;
        -s|--no-src)
        NO_SRC="-s"
        shift
        ;;
        *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
done
set -- "${POSITIONAL[@]}"

# Check input variables
if [[ -z "${1}" ]]; then
    error "Missing an argument.${C_RESET}${COMMAND_USAGE}" 02
fi

echo
echo "${C_BLUE}File path:${C_RESET} ${1}"

# Check if input file exists
if [[ ! -f "${1}" ]]; then
    error "${1} not found.${C_RESET}" 03
fi

APK_NAME=$(basename "${1}" .apk)
OUTPUT_FILENAME="${APK_NAME}_modded.apk"

# Add necessary tools to PATH
if [[ "$(uname)" == "Darwin" ]]; then
    export PATH="${SCRIPTPATH}/bin/macos/:$PATH"
elif [[ "$(uname -s | cut -c -5)" == "Linux" ]]; then
    export PATH="${SCRIPTPATH}/bin/linux/:$PATH"
fi
export PATH="${SCRIPTPATH}/bin/universal/:$PATH"

# Check for commands
check_command java
check_command keytool
check_command apktool
check_command aapt
check_command zipalign
check_command apksigner

echo
print_apk_info "${1}"
echo
print_apk_signed_info "${1}"
echo

# Generate keystore
if [[ ! -f "${KEYSTORE}" ]]; then
    info "Generating keystore: ${KEYSTORE}..."
    keytool -genkeypair -alias "${KEYSTORE_ALIAS}" \
        -keypass "${KEYSTORE_PASS}" -keystore "${KEYSTORE}" \
        -storepass "${KEYSTORE_PASS}" -keyalg RSA -sigalg SHA1withRSA \
        -storetype PKCS12 \
        -dname "${KEYSTORE_DNAME}" \
        -validity 10000    
fi

# Decompile
info "Decompiling in ${PATCH_FOLDER}..."
apktool d -f -o "${PATCH_FOLDER}" -p "${PATCH_FOLDER}" "${NO_RES}" \
    "${NO_SRC}" "${1}" || error "There was an error decompiling the apk." 04

echo
read -n 1 -s -r -p "Press any key to continue..."
echo
echo

# Rebuild
info "Recompiling..."
apktool b -p "${PATCH_FOLDER}" "${PATCH_FOLDER}" || \
    error "There was an error recompiling the apk." 05

# Sign and zipalign
info "Zipaligning APK..."
zipalign -f 4 "${PATCH_FOLDER}/dist/${APK_NAME}.apk" "${OUTPUT_FILENAME}" || \
    error "There was an error zipaligning the APK." 06

info "Signing APK..."
apksigner sign --v3-signing-enabled false --ks "${KEYSTORE}" \
    --ks-pass "pass:${KEYSTORE_PASS}" --ks-key-alias "${KEYSTORE_ALIAS}" \
    "${OUTPUT_FILENAME}" || error "There was an error signing the APK." 07

# Final cleanup
cleanup

echo
print_apk_info "${OUTPUT_FILENAME}"
echo
print_apk_signed_info "${OUTPUT_FILENAME}"
echo

echo "${C_GREEN}Done!${C_RESET}"