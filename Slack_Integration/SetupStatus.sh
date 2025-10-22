#!/bin/bash

# Debug log file
DEBUG_LOG="setup_debug.log"
echo "Starting Debug Log: $(date)" > "$DEBUG_LOG"

# Ensure the ccc.sh script exists
CCC_PATH="/opt/dbwatch-controlcenter/ccc.sh"
if [[ ! -x $CCC_PATH ]]; then
    echo "Error: $CCC_PATH not found or not executable." | tee -a "$DEBUG_LOG"
    exit 1
fi

# Ensure customers.ini exists
CONFIG_FILE="customers.ini"
if [[ ! -f $CONFIG_FILE ]]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found." | tee -a "$DEBUG_LOG"
    exit 1
fi

# Create setupREMOTE.script if it doesn't exist
SETUP_SCRIPT="setupREMOTE.script"
if [[ ! -f $SETUP_SCRIPT ]]; then
    cat <<EOF >"$SETUP_SCRIPT"
## setup@properties
accesspoint?=localhost:7100
domainName?=
name?=
token?=

## join@Domain
clear
join accesspoint={\$accesspoint\$} domain={\$domainName\$} name={\$name\$} token={\$token\$}
EOF
    echo "Created $SETUP_SCRIPT file." | tee -a "$DEBUG_LOG"
fi

# Process each customer
while IFS=, read -r ACCESSPOINT TARGET DOMAINNAME TOKEN; do
    # Use 'ccc(chrona)' as the fixed name
    NAME="ccc(chrona)"

    # Debug output
    echo "Processing: Accesspoint=$ACCESSPOINT, Domain=$DOMAINNAME, Name=$NAME, Token=$TOKEN" | tee -a "$DEBUG_LOG"

    # Run the setup command
    # COMMAND_OUTPUT=$($CCC_PATH "$SETUP_SCRIPT" accesspoint="$ACCESSPOINT" domainName="$DOMAINNAME" name="$NAME" token="$TOKEN" 2>&1)
    $CCC_PATH "$SETUP_SCRIPT" accesspoint="$ACCESSPOINT" domainName="$DOMAINNAME" name="$NAME" token="$TOKEN" 

    # Check for success
    if [[ $? -eq 0 ]]; then
        echo "Setup successful for domain: $DOMAINNAME" | tee -a "$DEBUG_LOG"
    else
        echo "Setup failed for domain: $DOMAINNAME. Check logs." | tee -a "$DEBUG_LOG"
    fi

done < "$CONFIG_FILE"

echo "Script execution completed." | tee -a "$DEBUG_LOG"

