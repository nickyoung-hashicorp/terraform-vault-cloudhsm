##############################################################################
# Variables File
#
# Here is where we store the default values for all the variables used in our
# Terraform code. If you create a variable with no default, the user will be
# prompted to enter it (or define it via config file or command line flags.)

variable "region" {
  description = "The region where the resources are created."
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Provide the specific availability zone to deploy the first subnet."
  default     = "us-east-1a"
}

variable "address_space" {
  description = "The address space that is used by the virtual network. You can supply more than one address space. Changing this forces a new resource to be created."
  default     = "10.0.0.0/16"
}

variable "subnet_prefix_1" {
  description = "The address prefix to use for the subnet 1."
  default     = "10.0.10.0/24"
}

variable "instance_type" {
  description = "Specifies the AWS instance type."
  default     = "t2.nano"
}
