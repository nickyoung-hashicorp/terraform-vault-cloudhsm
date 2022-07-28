---
slug: deploy-aws-infrastructure
type: challenge
title: Deploying AWS infrastructure
teaser: |
  Use Terraform to deploy all AWS resources needed for this demonstration.
notes:
- type: text
  contents: |
    In this track, you will use Terraform to stand up a VPC with a subnet, internet gateway with a route table, security groups, an EC2 instance for Vault, and a CloudHSM.

    The Terraform code that we clone for provisioning these resources is found here:
     - https://github.com/nickyoung-hashicorp/terraform-vault-cloudhsm
- type: text
  contents: |
    The intended goal is to walk a practitioner through setting up Vault with an AWS CloudHSM.

    AWS provides a User Guide related to performing administrative tasks after you provision the CloudHSM.  We will follow this guide as part of the track:
     - https://docs.aws.amazon.com/cloudhsm/latest/userguide/initialize-cluster.html
tabs:
- title: CLI
  type: terminal
  hostname: cloud-client
- title: Cloud Console
  type: service
  hostname: cloud-client
  path: /
  port: 80
- title: Terraform
  type: code
  hostname: cloud-client
  path: /root/terraform-vault-cloudhsm
difficulty: basic
timelimit: 12000
---
View AWS credentials and the default AWS region:
```
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY
echo $AWS_DEFAULT_REGION
```

**Terraform AWS Infrastructure**

You can view the Terraform code that we cloned as part of the setup process in the **Terraform** tab.

Provision infrastructure:
```
terraform init
terraform apply -auto-approve
```

**Initialize the CloudHSM**

Export the the CloudHSM's cluster ID and the public IP address of the EC2 instance:
```
export CLUSTER_ID=$(terraform output -json | jq -r .hsm_cluster_id.value)
export PUBLIC_IP=$(terraform output -json | jq -r .vault_ip.value)
```

Get the Certificate Signing Request:
```
aws cloudhsmv2 describe-clusters --filters clusterIds=${CLUSTER_ID} \
  --output text \
  --query 'Clusters[].Certificates.ClusterCsr' > ClusterCsr.csr
```

Create a private key using a pass phrase of your choice:
```
openssl genrsa -aes256 -out customerCA.key 2048
```

Use the private key to create a self-signed certificate, providing your own inputs for Country, State, etc.:
```
openssl req -new -x509 -days 3652 -key customerCA.key -out customerCA.crt
```
Provide the pass phrase when prompted.

Sign the Cluster CSR and provide the pass phrase when prompted:
```
openssl x509 -req -days 3652 -in ClusterCsr.csr \
  -CA customerCA.crt \
  -CAkey customerCA.key \
  -CAcreateserial \
  -out CustomerHsmCertificate.crt
```

Initialize the cluster
```
aws cloudhsmv2 initialize-cluster --cluster-id ${CLUSTER_ID} \
  --signed-cert file://CustomerHsmCertificate.crt \
  --trust-anchor file://customerCA.crt
```

Check state of initialization, should change from `INITIALIZE_IN_PROGRESS` to `INITIALIZED` after a few minutes:
```
aws cloudhsmv2 describe-clusters --filters clusterIds=${CLUSTER_ID} \
  --output text \
  --query 'Clusters[].State'
```
Re-run the previous command until you see the state is `INITIALIZED`.

Before you SSH into your new EC2 instance, copy the `customerCA.crt` to the EC2 instance
```
scp -i id_rsa.pem customerCA.crt ubuntu@$PUBLIC_IP:/home/ubuntu/customerCA.crt
```

Echo the values we need to have them available in your EC2 instance:
```
cat > env.sh << EOF
#!/bin/bash
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
export CLUSTER_ID=$CLUSTER_ID
EOF
```

Copy this to your EC2 instance as well:
```
scp -i id_rsa.pem env.sh ubuntu@$PUBLIC_IP:/home/ubuntu/env.sh
```

SSH to your new EC2 instance:
```
ssh -i id_rsa.pem ubuntu@$PUBLIC_IP
```

Source the environment variables:
```
source env.sh
```

Update the EC2 instance with needed packages:
```
sudo apt update
sudo apt install awscli unzip opensc jq -y
```

**Install and configure the AWS CloudHSM Client**

Install the CloudHSM Client:
```
wget https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/Bionic/cloudhsm-client_latest_u18.04_amd64.deb

sudo apt install ./cloudhsm-client_latest_u18.04_amd64.deb -y
```

Next, find the private IP address of the CloudHSM and save that as an environment variable:
```
export HSM_IP=$(aws cloudhsmv2 describe-clusters --filters clusterIds=${CLUSTER_ID} | jq -r .Clusters[].Hsms[].EniIp)
```

Then configure the CloudHSM client and CLI tools specifying the IP address of the HSM:
```
sudo /opt/cloudhsm/bin/configure -a $HSM_IP
```

If successful, you should see the following output:
```
Updating server config in /opt/cloudhsm/etc/cloudhsm_client.cfg
Updating server config in /opt/cloudhsm/etc/cloudhsm_mgmt_util.cfg
```

Move the `customerCA.crt` into the proper directory:
```
sudo mv customerCA.crt /opt/cloudhsm/etc/customerCA.crt
```

**Activate the Cluster**

Use the following command to start the CloudHSM Management Utility (CMU):
```
/opt/cloudhsm/bin/cloudhsm_mgmt_util /opt/cloudhsm/etc/cloudhsm_mgmt_util.cfg
```

Resulting output:
```
Connecting to the server(s), it may take time
depending on the server(s) load, please wait...

Connecting to server '10.0.29.248': hostname '10.0.29.248', port 2225...
Connected to server '10.0.29.248': hostname '10.0.29.248', port 2225.
E2E enabled on server 0(10.0.29.248)
aws-cloudhsm>
```

Enable end-to-end encryption:
```
enable_e2e
```

Use the `listUsers` command to display the existing users:
```
listUsers
```

Use the `loginHSM` command to log in as the PRECO user.  This is a temporary user that exists on the first HSM in your cluster:
```
loginHSM PRECO admin password
```

Use the `changePswd` command to change the password for the PRECO user. When you change the password, the PRECO user becomes a crypto officer (CO):
```
changePswd PRECO admin hashi123
```
Type `y` and press `<Enter>` to confirm changing the password.

List the users again and notice the `admin` user is now the `CO` or Crypto Officer user type:
```
listUsers
```

Logout of the session.
```
logoutHSM
```

Log back in as `admin`:
```
loginHSM CO admin hashi123
```

**Create a Cypto Officer User for Vault**

Use `createUser` to create a CO user named `vault` with a password of `Password1`:
```
createUser CU vault Password1
```
Type `y` and press `<Enter>` to confirm creating the new CU user.

Finally, check to ensure `vault` is listed as a `CU` user type.
```
listUsers
```

If that looks good, disconnect from the CloudHSM.
```
quit
```

Install the PKCS #11 Library:
```
sudo service cloudhsm-client start

wget https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/Bionic/cloudhsm-client-pkcs11_latest_u18.04_amd64.deb

sudo apt install ./cloudhsm-client-pkcs11_latest_u18.04_amd64.deb -y
```
**Install Vault**

Git clone the repo within the EC2 instance, copy the scripts, clean up, and make scripts executable:
```
git clone https://github.com/nickyoung-hashicorp/terraform-vault-cloudhsm.git
cp ./terraform-vault-cloudhsm/install-vault-hsm-file.sh .
cp ./terraform-vault-cloudhsm/run-vault-hsm.sh .
rm -rf ./terraform-vault-cloudhsm
chmod +x *.sh
```

Run the script to install Vault:
```
./install-vault-hsm-file.sh
```

Export the VAULT_ADDR:
```
export VAULT_ADDR=http://127.0.0.1:8200
```

Run the script to start the Vault service, then initialize, unseal, and log in to Vault:
```
./run-vault-hsm.sh
```
This script will also output the unseal keys and root token to `vault_init.json` in the current directory.  You can view the root token and recovery keys:
```
cat vault_init.json
```