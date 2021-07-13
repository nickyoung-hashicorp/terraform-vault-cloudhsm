echo "Starting Vault systemd service"
sudo systemctl enable vault
sudo systemctl start vault

sleep 5
echo "Initializing Vault with vault operator init..."
vault operator init > vault_init.json
sleep 5
echo "Logging into Vault with the root token..."
vault login $(jq -r .root_token < vault_init.json)