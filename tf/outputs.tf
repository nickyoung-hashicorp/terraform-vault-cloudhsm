# Output of Vault instance public IP for SSH access
output "vault_ip" {
  value = aws_eip.vault.public_ip
}

# Output of CloudHSM Cluster ID
output "hsm_cluster_id" {
  value = aws_cloudhsm_v2_cluster.cloudhsm_v2_cluster.cluster_id
}