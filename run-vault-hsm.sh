echo "Starting Vault systemd service"
sudo systemctl enable vault
sudo systemctl start vault

sleep 5
echo "Initializing Vault with vault operator init..."
vault operator init -key-shares=1 -key-threshold=1 -recovery-shares=1 -recovery-threshold=1 > vault_init.json
sleep 5
echo "Logging into Vault with the root token..."
vault login $(cat vault_init.json | grep "Initial Root Token" | awk '{print $4}')