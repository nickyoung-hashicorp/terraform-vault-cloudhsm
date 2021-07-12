echo "Starting Vault systemd service"
sudo systemctl enable vault
sudo systemctl start vault

sleep 5
echo "Initializing Vault with vault operator init..."
vault operator init -key-shares=1 -key-threshold=1 -format=json > vault_init.json
sleep 5
echo "Unsealing Vault..."
vault operator unseal $(jq -r .unseal_keys_b64[0] < vault_init.json)
sleep 10
echo "Logging into Vault with the root token..."
vault login $(jq -r .root_token < vault_init.json)