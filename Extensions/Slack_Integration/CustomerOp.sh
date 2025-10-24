#!/bin/bash
# Set debug information
# set -x

# Define the lockfile
LOCKFILE="/tmp/CustomerOp.lock"

# Check if the lockfile already exists
if [ -e "$LOCKFILE" ]; then
    echo "Script is already running. Exiting."
    exit 1
fi

# Create the lockfile and set up a trap to remove it on exit
trap "rm -f $LOCKFILE; exit" INT TERM EXIT
touch "$LOCKFILE"

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Slack configurations
SLACK_TOKEN="xoxb-your-slack-token"           									# Replace with your bot token
SLACK_CHANNEL="C1234567890"                                                     # Replace with your channel ID
LAST_MESSAGE_FILE="$SCRIPT_DIR/lastMessageTimestamp.txt"

# Input parameters
CONFIG_FILE="$SCRIPT_DIR/customers.ini"
FDL_SCRIPT="$SCRIPT_DIR/fdlREMOTE.script"
RESULT_FILE="$SCRIPT_DIR/temp_result.log"

# Ensure the ccc.sh script exists
CCC_PATH="/opt/dbwatch-controlcenter/ccc.sh"
if [[ ! -x $CCC_PATH ]]; then
    echo "Error: $CCC_PATH not found or not executable."
    rm -f "$LOCKFILE"
    exit 1
fi

# Ensure the configuration file exists
if [[ ! -f $CONFIG_FILE ]]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found."
    rm -f "$LOCKFILE"
    exit 1
fi

# Ensure the FDL script exists or create it
if [[ ! -f $FDL_SCRIPT ]]; then
    cat <<EOF >$FDL_SCRIPT
## setup@properties
accesspoint?=localhost:7100
node?=
query?=versioninfo
domainName?=
delimiter?=:
result?=fdl.txt
token?=
timeout?=10

## join@Domain
join accesspoint={\$accesspoint\$} domain={\$domainName\$} token={\$token\$}

## add@Fdl
fdl accesspoint={\$accesspoint\$} node={\$node\$} query={\$query\$} timeout={\$timeout\$} delimiter={\$delimiter\$} result={\$result\$}
EOF
fi

# Initialize variables for Slack message
COMBINED_MESSAGE=""
MESSAGE_HEADER="Combined Status Report:"

# Function to clean up result file before each execution
cleanup_result_file() {
    > "$RESULT_FILE"  # Clear the file
}

# Process each customer in the configuration file
while IFS=, read -r ACCESSPOINT TARGET DOMAINNAME TOKEN; do
    echo "Processing customer: $DOMAINNAME"

    # Clear result file
    cleanup_result_file

    # Run the command
    QUERY='server->s/name/id{}/$s/slacksummary/id'
    COMMAND_OUTPUT=$($CCC_PATH "$FDL_SCRIPT" accesspoint="$ACCESSPOINT" node="$TARGET" query="$QUERY" domainName="$DOMAINNAME" token="$TOKEN" result="$RESULT_FILE" 2>&1)

    # Initialize sections for this domain
    STATUS_CIRCLES=""
    LOST_CONNECTIONS=""
    ALARMS=""

    # Check if the result file contains data
    if [[ ! -s $RESULT_FILE ]]; then
        # Append "Server lost connection" if result file is empty
        COMBINED_MESSAGE+="\n$DOMAINNAME: *Server lost connection*"
    else
        # Process the result file
        while read -r line; do
            if [[ $line == *"Lost connection:"* ]]; then
                LOST_CONNECTIONS="${line#*:}"  # Strip "Lost connection:" prefix
            elif [[ $line == *"Alarm:"* ]]; then
                ALARMS="${line#*:}"  # Strip "Alarm:" prefix
            else
                STATUS_CIRCLES="$line"
            fi
        done <$RESULT_FILE

        # Append status circles to combined message
        COMBINED_MESSAGE+="\n$STATUS_CIRCLES"

        # Append Lost Connections and Alarms on new lines if they exist
        [[ -n $LOST_CONNECTIONS ]] && COMBINED_MESSAGE+="\n  :large_blue_circle:: $LOST_CONNECTIONS"
        [[ -n $ALARMS ]] && COMBINED_MESSAGE+="\n  :red_circle:: $ALARMS"
    fi
done < "$CONFIG_FILE"

# Final message to post
FINAL_MESSAGE="$MESSAGE_HEADER\n$COMBINED_MESSAGE"

# Function to delete the previous Slack message
delete_previous_message() {
    if [[ -f $LAST_MESSAGE_FILE ]]; then
        LAST_TS=$(cat $LAST_MESSAGE_FILE)
        DELETE_RESPONSE=$(curl -s -X POST "https://slack.com/api/chat.delete" \
            -H "Authorization: Bearer $SLACK_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"channel\":\"$SLACK_CHANNEL\",\"ts\":\"$LAST_TS\"}")
        if [[ $(echo "$DELETE_RESPONSE" | jq -r '.ok') == "true" ]]; then
            echo "Previous message deleted successfully."
        else
            echo "Warning: Failed to delete previous message. Response: $DELETE_RESPONSE"
        fi
    fi
}

# Function to post the combined message to Slack
post_to_slack() {
    POST_RESPONSE=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer $SLACK_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"channel\":\"$SLACK_CHANNEL\",\"text\":\"$FINAL_MESSAGE\"}")
    if [[ $(echo "$POST_RESPONSE" | jq -r '.ok') == "true" ]]; then
        echo "$POST_RESPONSE" | jq -r '.ts' >"$LAST_MESSAGE_FILE"
        echo "Message posted successfully."
    else
        echo "Error: Failed to post message. Response: $POST_RESPONSE"
    fi
}

# Delete previous message and post the new one
delete_previous_message
post_to_slack

# Remove lockfile
rm -f "$LOCKFILE"

