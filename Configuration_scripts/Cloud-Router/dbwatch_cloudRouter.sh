#!/bin/bash

# Function to check if a package is installed
is_installed() {
    dpkg -l | grep -q "$1"
}

# Function to stop dbwatch-controlcenter service
stop_dbwatch_controlcenter() {
    echo "Stopping dbwatch-controlcenter service..."
    sudo systemctl stop dbwatch-controlcenter
}

# Check if dbwatch-controlcenter is installed
if ! is_installed "dbwatch-controlcenter"; then
    echo "dbwatch-controlcenter package is not installed."
    echo "Please run dbwatch_precheck.sh to verify the environment."
    exit 1
fi

# Function to check and prompt for changing a parameter in XML file
check_and_prompt_xml_param() {
    local file=$1
    local param=$2
    local expected_value=$3

    if grep -q "<$param>" "$file"; then
        local current_value=$(grep "<$param>" "$file" | sed -E "s/.*<$param>(.*)<\/$param>.*/\1/")
        
        if [ "$current_value" != "$expected_value" ]; then
            echo "Parameter $param in $file is set to $current_value, expected $expected_value."
            read -p "Do you want to change it to $expected_value? (y/n) " answer
            if [ "$answer" == "y" ]; then
                stop_dbwatch_controlcenter
                sed -i "s|<$param>.*</$param>|<$param>$expected_value</$param>|g" "$file"
                echo "Parameter $param changed to $expected_value in $file."
            fi
        fi
    else
        echo "Parameter $param not found in $file."
    fi
}

# Function to check and prompt for enabling or changing a parameter in properties file
check_and_prompt_properties_param() {
    local file=$1
    local param=$2
    local expected_value=$3

    if grep -qE "^#?${param}" "$file"; then
        local current_value=$(grep -E "^#?${param}" "$file" | cut -d'=' -f2 | tr -d ' ')
        
        if [ "$current_value" != "$expected_value" ]; then
            echo "Parameter $param in $file is set to $current_value, expected $expected_value."
            read -p "Do you want to change it to $expected_value? (y/n) " answer
            if [ "$answer" == "y" ]; then
                stop_dbwatch_controlcenter
                sed -i "s/^#?${param}.*/${param} = ${expected_value}/" "$file"
                echo "Parameter $param changed to $expected_value in $file."
            fi
        fi
    else
        echo "Parameter $param not found in $file."
        read -p "Do you want to add it with value $expected_value? (y/n) " answer
        if [ "$answer" == "y" ]; then
            stop_dbwatch_controlcenter
            echo "${param} = ${expected_value}" >> "$file"
            echo "Parameter $param added with value $expected_value in $file."
        fi
    fi
}

# Function to check and ensure forwarding is enabled in router.json
check_and_prompt_router_forwarding() {
    local file="/var/dbwatch-controlcenter/config/node/router.json"
    
    if [ -f "$file" ]; then
        if ! grep -q '"forwarding":"true"' "$file"; then
            echo '"forwarding":"true" not found in router.json.'
            read -p 'Do you want to add "forwarding":"true" to router.json? (y/n) ' answer
            if [ "$answer" == "y" ]; then
                stop_dbwatch_controlcenter
                sed -i '2a \ \ \ \ "forwarding":"true",' "$file"
                echo '"forwarding":"true" has been added to router.json.'
            fi
        else
            echo '"forwarding":"true" is already present in router.json.'
        fi
    else
        echo "router.json file does not exist."
    fi
}

check_and_prompt_router_discovery() {
    local file="/var/dbwatch-controlcenter/config/node/router.json"

    if [ -f "$file" ]; then
        if grep -q '"discovery":"true"' "$file"; then
            echo '"discovery":"true" detected in router.json.'
            read -p 'Do you want to change "discovery" to "false"? (y/n) ' answer
            if [ "$answer" == "y" ]; then
                stop_dbwatch_controlcenter
                # Replace "discovery":"true" with "discovery":"false"
                sed -E -i 's/"discovery":"true"/"discovery":"false"/g' "$file"
                echo '"discovery" set to "false" in router.json.'
            fi
        else
            echo '"discovery" is already false or not present in router.json.'
        fi
    else
        echo "router.json file does not exist."
    fi
}


# Check and update scheduler-thread-pool-size and thread-pool-size in server_configuration.xml
config_file="/var/dbwatch-controlcenter/config/server/server_configuration.xml"
check_and_prompt_xml_param "$config_file" "scheduler-thread-pool-size" "5"
check_and_prompt_xml_param "$config_file" "thread-pool-size" "100"

# Update tuning.properties for Scheduler settings
tuning_file="/var/dbwatch-controlcenter/config/node/tuning.properties"
if [ -f "$tuning_file" ]; then
    check_and_prompt_properties_param "$tuning_file" "Scheduler.threads.count" "5"
    check_and_prompt_properties_param "$tuning_file" "Scheduler.threads.sleep" "2"
fi

# Check for router.json: ensure forwarding is enabled and optionally disable discovery
check_and_prompt_router_forwarding
check_and_prompt_router_discovery


# Ask for the domain controller once
read -p "Enter the name of the domain controller: " domain_controller

# Check for services.json file and its content
services_file="/var/dbwatch-controlcenter/config/services.json"

if [ -f "$services_file" ]; then
    if ! grep -q "service.cloudrouter:router@domain:${domain_controller}" "$services_file"; then
        echo "The services.json file does not contain the expected content."
        read -p "Do you want to modify it? (y/n) " answer
        if [ "$answer" == "y" ]; then
            stop_dbwatch_controlcenter
            updated_services="{
    \"services:Entity\": [
        \"service.cloudrouter:router@domain:${domain_controller}\"
    ]
}"
            echo "$updated_services" > "$services_file"
            echo "Updated $services_file with domain controller $domain_controller."
        fi
    else
        echo "The services.json file is correct."
    fi
else
    echo "The services.json file does not exist."
    read -p "Do you want to create it? (y/n) " answer
    if [ "$answer" == "y" ]; then
        stop_dbwatch_controlcenter
        new_services="{
    \"services:Entity\": [
        \"service.cloudrouter:router@domain:${domain_controller}\"
    ]
}"
        echo "$new_services" > "$services_file"
        echo "Created $services_file with domain controller $domain_controller."
    fi
fi

# Check for governingDomain.json file and its content
governing_file="/var/dbwatch-controlcenter/config/node/governingDomain.json"

if [ -f "$governing_file" ]; then
    if ! grep -q "\"domain\":\"${domain_controller}\"" "$governing_file"; then
        echo "The governingDomain.json file does not contain the expected domain controller."
        read -p "Do you want to add it? (y/n) " answer
        if [ "$answer" == "y" ]; then
            stop_dbwatch_controlcenter
            updated_governing="{
    \"domain\":\"${domain_controller}\"
}"
            echo "$updated_governing" > "$governing_file"
            echo "Updated $governing_file with domain controller $domain_controller."
        fi
    else
        echo "The governingDomain.json file is correct."
    fi
else
    echo "The governingDomain.json file does not exist."
    read -p "Do you want to create it? (y/n) " answer
    if [ "$answer" == "y" ]; then
        stop_dbwatch_controlcenter
        new_governing="{
    \"domain\":\"${domain_controller}\"
}"
        echo "$new_governing" > "$governing_file"
        echo "Created $governing_file with domain controller $domain_controller."
    fi
fi

# Prompt to delete repository/no.dbwatch.resources/resources_1.zip if it exists
resources_file="/var/dbwatch-controlcenter/repository/no.dbwatch.resources/resources_1.zip"
if [ -f "$resources_file" ]; then
    echo "Found $resources_file."
    read -p "Do you want to delete it? (y/n) " answer
    if [ "$answer" == "y" ]; then
        stop_dbwatch_controlcenter
        rm "$resources_file"
        echo "Deleted $resources_file."
    fi
fi

# Prompt to delete files in /var/dbwatch-controlcenter/config/node/trustStore
trust_store_dir="/var/dbwatch-controlcenter/config/node/trustStore"
if [ -d "$trust_store_dir" ] && [ "$(ls -A $trust_store_dir)" ]; then
    echo "Found files in $trust_store_dir:"
    ls "$trust_store_dir"
    read -p "Do you want to delete all files in $trust_store_dir? (y/n) " answer
    if [ "$answer" == "y" ]; then
        stop_dbwatch_controlcenter
        rm -rf "$trust_store_dir"/*
        echo "Deleted files in $trust_store_dir."
    fi
fi

# Prompt to delete files in /var/dbwatch-controlcenter/config/domain
domain_dir="/var/dbwatch-controlcenter/config/domain"
if [ -d "$domain_dir" ] && [ "$(ls -A $domain_dir)" ]; then
    echo "Found files in $domain_dir:"
    ls "$domain_dir"
    read -p "Do you want to delete all files in $domain_dir? (y/n) " answer
    if [ "$answer" == "y" ]; then
        stop_dbwatch_controlcenter
        rm -rf "$domain_dir"/*
        echo "Deleted files in $domain_dir."
    fi
fi

# Prompt to delete files in /var/dbwatch-controlcenter/crypto
crypto_dir="/var/dbwatch-controlcenter/crypto"
if [ -d "$crypto_dir" ] && [ "$(ls -A $crypto_dir)" ]; then
    echo "Found files in $crypto_dir:"
    ls "$crypto_dir"
    read -p "Do you want to delete all files in $crypto_dir? (y/n) " answer
    if [ "$answer" == "y" ]; then
        stop_dbwatch_controlcenter
        rm -rf "$crypto_dir"/*
        echo "Deleted files in $crypto_dir."
    fi
fi

echo "Script execution completed."
echo "Necessary actions to be done:"
echo "1) This Cloud Router needs to be added on the Cloud Router Domain controller (Domain Configuration, Server, Edit Connections)."
echo "   Note: 3 PEM files might have to be copied from the trustStore at Cloud Router Domain Controller"
echo "   and into Cloud Router trustStore (/var/dbwatch-controlcenter/config/node/trustStore)."
echo "2) At Customer Domain Controller: add token for Cloud Router access."
echo "3) At Cloud Router Domain Controller, Domain Configuration - remember to click Approved when the new node appears."

