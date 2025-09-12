#/usr/bin/env bash

JENKINS_HOME_DIR="./mounted/jenkins_home"
INIT_GROOVY_DIR="${JENKINS_HOME_DIR}/init.groovy.d"
ASSET_DIR="./data/assets"

echo "🧹 Cleaning up jenkins_home..."
rm -rf "${JENKINS_HOME_DIR}"
mkdir "${JENKINS_HOME_DIR}"
chmod +w "${JENKINS_HOME_DIR}"
mkdir "${INIT_GROOVY_DIR}"

echo "📝 Deploying initial script..."
cp "${ASSET_DIR}/bypass.groovy" "${INIT_GROOVY_DIR}"
cp "${ASSET_DIR}/generate_token.groovy" "${INIT_GROOVY_DIR}"
