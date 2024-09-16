#!/usr/bin/env bash

DB_URL=$(aws secretsmanager get-secret-value --profile prod-admin --secret-id "hydrific-production-hydrific_db_url" --query SecretString --output text)

DB_HOST=$(echo $DB_URL | cut -d@ -f2- | cut -d/ -f1 | cut -d: -f1)
DB_PORT=$(echo $DB_URL | cut -d@ -f2- | cut -d/ -f1 | cut -d: -f2)
DB_USER=$(echo $DB_URL | cut -d@ -f1- | cut -d: -f2 | sed 's/^\/\///')
DB_PW=$(echo $DB_URL | cut -d '@' -f 1 | cut -d ':' -f 3)
DB_DATABASE=$(echo $DB_URL | cut -d '?' -f 1 | cut -d '/' -f 4)

SSH_USER=darin
SSH_KEYFILE=/Users/gordond/.ssh/bastion_prod_ed25519
BASTION_HOST=54.81.178.184

# Establish an SSH tunnel to the bastion host and forward the database port
ssh -v -i $SSH_KEYFILE -L 5433:$DB_HOST:$DB_PORT $SSH_USER@$BASTION_HOST -N
