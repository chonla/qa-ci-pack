#/usr/bin/env bash

JENKINS_HOME_PATH="./mounted/jenkins_home"
JENKINS_INIT_GROOVY_PATH="${JENKINS_HOME_PATH}/init.groovy.d"
JENKINS_VARS_PATH="${JENKINS_HOME_PATH}/vars"
ASSETS_PATH="./data/assets"

echo "🧹 Cleaning up jenkins_home..."
rm -rf "${JENKINS_HOME_PATH}"
mkdir "${JENKINS_HOME_PATH}"
chmod +w "${JENKINS_HOME_PATH}"
mkdir "${JENKINS_INIT_GROOVY_PATH}"
mkdir "${JENKINS_VARS_PATH}"

echo "📝 Deploying initialization script..."
cp "${ASSETS_PATH}/bypass.groovy" "${JENKINS_INIT_GROOVY_PATH}"
cp "${ASSETS_PATH}/generate_token.groovy" "${JENKINS_INIT_GROOVY_PATH}"

echo "📝 Deploying pipeline scripts..."
cp "${ASSETS_PATH}/allure.groovy" "${JENKINS_VARS_PATH}"