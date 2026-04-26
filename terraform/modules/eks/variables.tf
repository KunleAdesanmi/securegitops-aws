variable "name" {
  type        = string
  description = "Cluster name."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.30"
  description = "Kubernetes minor version."
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for EKS control plane ENIs and nodes."
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
