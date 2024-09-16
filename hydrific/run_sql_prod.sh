#!/usr/bin/env bash

set -e

# Function to print error messages
print_error() {
	echo "Error: $1" >&2
}

# Function to print debug messages
print_debug() {
	echo "Debug: $1" >&2
}

# Function to print usage instructions
print_usage() {
	echo "Usage: $0 <input_sql_file> <output_csv_file>"
	echo "Options:"
	echo "  -h    Display this help message"
	echo
	echo "Description:"
	echo "  This script executes an SQL query from the input file and saves the results to the specified output CSV file."
	echo "  It establishes an SSH tunnel to a bastion host and connects to a remote database to run the query."
}

# Function to find an available port
find_available_port() {
	local port=5433
	while ss -tln | grep -q ":$port "; do
		port=$((port + 1))
	done
	echo $port
}

# Function to establish SSH tunnel
establish_ssh_tunnel() {
	local local_port=$1
	local remote_host=$2
	local remote_port=$3
	local ssh_user=$4
	local ssh_keyfile=$5
	local bastion_host=$6

	ssh -v -i "${ssh_keyfile}" -L "${local_port}:${remote_host}:${remote_port}" "${ssh_user}@${bastion_host}" -N -f
	if [ $? -eq 0 ]; then
		echo $!
	else
		return 1
	fi
}

# Check for help flag
if [[ "$1" == "-h" ]]; then
	print_usage
	exit 0
fi

# Check if both arguments are provided
if [ $# -ne 2 ]; then
	print_error "Incorrect number of arguments."
	print_usage
	exit 1
fi

input_file="$1"
output_file="$2"

# Check if the input file exists
if [ ! -f "$input_file" ]; then
	print_error "Input file '$input_file' not found."
	exit 1
fi

AWS_PROFILE="prod-admin"

# Fetch DB_URL from AWS Secrets Manager
print_debug "Fetching DB_URL from AWS Secrets Manager..."
if ! DB_URL=$(aws secretsmanager get-secret-value --profile "${AWS_PROFILE}" --secret-id "hydrific-production-hydrific_db_url" --query SecretString --output text); then
	print_error "Failed to retrieve DB_URL from AWS Secrets Manager."
	exit 1
fi

# Extract database connection details
print_debug "Extracting database connection details..."
DB_HOST=$(echo "${DB_URL}" | cut -d@ -f2- | cut -d/ -f1 | cut -d: -f1)
DB_PORT=$(echo "${DB_URL}" | cut -d@ -f2- | cut -d/ -f1 | cut -d: -f2)
DB_USER=$(echo "${DB_URL}" | cut -d@ -f1- | cut -d: -f2 | sed 's/^\/\///')
DB_PW=$(echo "${DB_URL}" | cut -d '@' -f 1 | cut -d ':' -f 3)
DB_DATABASE=$(echo "${DB_URL}" | cut -d '?' -f 1 | cut -d '/' -f 4)

SSH_USER=darin
SSH_KEYFILE=/Users/gordond/.ssh/bastion_prod_ed25519
BASTION_HOST=ec2-18-234-229-182.compute-1.amazonaws.com

# Try to establish SSH tunnel
max_attempts=5
attempt=1
while [ $attempt -le $max_attempts ]; do
	LOCAL_PORT=$(find_available_port)
	print_debug "Attempting to use local port: $LOCAL_PORT (Attempt $attempt of $max_attempts)"

	SSH_PID=$(establish_ssh_tunnel "$LOCAL_PORT" "$DB_HOST" "$DB_PORT" "$SSH_USER" "$SSH_KEYFILE" "$BASTION_HOST")

	if [ $? -eq 0 ]; then
		print_debug "SSH tunnel established successfully on port $LOCAL_PORT"
		break
	else
		print_debug "Failed to establish SSH tunnel on port $LOCAL_PORT"
		attempt=$((attempt + 1))
		sleep 1
	fi
done

if [ $attempt -gt $max_attempts ]; then
	print_error "Failed to establish SSH tunnel after $max_attempts attempts."
	exit 1
fi

# Wait for the SSH tunnel to be fully established
sleep 5

# Execute the SQL commands and save the output
print_debug "Executing SQL query..."
if ! PGPASSWORD="${DB_PW}" psql -h localhost -p "${LOCAL_PORT}" -U "${DB_USER}" -d "${DB_DATABASE}" \
	-v ON_ERROR_STOP=1 \
	--no-psqlrc \
	--pset pager=off \
	--quiet \
	--tuples-only \
	-f "$input_file" >"$output_file" 2> >(tee psql_error.log >&2); then
	print_error "Failed to execute SQL query or save results. Check psql_error.log for details."
	cat psql_error.log >&2
	kill $SSH_PID
	exit 1
fi

# Check if the output file was created and has content
if [ ! -s "$output_file" ]; then
	print_error "Output file is empty. SQL query may have failed or returned no results."
	kill $SSH_PID
	exit 1
fi

# Close the SSH tunnel
print_debug "Closing SSH tunnel..."
kill $SSH_PID

echo "Query executed successfully. Results saved in $output_file"
