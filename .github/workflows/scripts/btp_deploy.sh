set -e

echo '############## Get cf Client ##############'
wget -q -O - https://packages.cloudfoundry.org/debian/cli.cloudfoundry.org.key | sudo apt-key add -
echo "deb https://packages.cloudfoundry.org/debian stable main" | sudo tee /etc/apt/sources.list.d/cloudfoundry-cli.list
sudo apt-get update
sudo apt-get install -y cf8-cli

echo '############## Check Installation ##############'
cf -v

echo '############## Install Plugins ##############'
cf add-plugin-repo CF-Community https://plugins.cloudfoundry.org
cf install-plugin multiapps -f
cf install-plugin html5-plugin -f

echo '############## Install SAP MDK Tools ##############'
npm install -g @sap/mdk-tools

echo '############## Build MTAR ##############'
mdk build --target zip

echo '############## Login to Cloud Foundry ##############'
cf api "$cf_api_url"
cf auth "$cf_user" "$cf_password"

echo '############## Deploy MTAR ##############'
# cf target -o "$cf_org" -s "$cf_space"
# mdk deploy --target cf

###############################################################################
# Export to Cloud Transport Management
###############################################################################

echo '############## Export to TMS ##############'

echo "Obtaining OAuth token..."

TOKEN=$(curl --silent \
    --user "${TMS_CLIENT_ID}:${TMS_CLIENT_SECRET}" \
    "${TMS_UAA_URL}/oauth/token?grant_type=client_credentials" \
    | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Failed to obtain OAuth token"
    exit 1
fi

echo "Uploading ZIP..."

UPLOAD_RESPONSE=$(curl --silent --show-error \
    -X POST \
    "${TMS_URI}/v2/files/upload" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "file=@.build/uploadBundle.zip" \
    -F "namedUser=github-actions")

echo "$UPLOAD_RESPONSE"

FILE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.fileId')

if [ -z "$FILE_ID" ] || [ "$FILE_ID" = "null" ]; then
    echo "File upload failed"
    exit 1
fi

echo "Uploaded File ID: $FILE_ID"

echo "Creating Transport Request..."

# NODE_RESPONSE=$(curl --silent --show-error --fail \
NODE_RESPONSE=$(curl --silent --show-error \
    -X POST \
    "${TMS_URI}/v2/nodes/upload" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
        \"description\":\"SAP MDK Build ${GITHUB_SHA}\",
        \"nodeName\":\"${TMS_NODE_NAME}\",
        \"contentType\":\"ZIP\",
        \"storageType\":\"FILE\",
        \"entries\":[
            {
                \"uri\":\"${FILE_ID}\"
            }
        ],
        \"namedUser\":\"github-actions\"
    }")

echo "$NODE_RESPONSE"

TRANSPORT_ID=$(echo "$NODE_RESPONSE" | jq -r '.transportRequestId')

if [ -z "$TRANSPORT_ID" ] || [ "$TRANSPORT_ID" = "null" ]; then
    echo "Transport creation failed"
    exit 1
fi

echo "==============================================="
echo "Transport Request Created Successfully"
echo "Transport Request ID : $TRANSPORT_ID"
echo "==============================================="
