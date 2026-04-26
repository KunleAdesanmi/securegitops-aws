package terraform.security

# Deny SSH (port 22) open to the world. Single most common cloud breach vector.
deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_security_group_rule"
  resource.change.after.type == "ingress"
  resource.change.after.from_port <= 22
  resource.change.after.to_port >= 22
  resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
  msg := sprintf("[HIGH] %v allows SSH from the entire internet", [resource.address])
}

# Deny RDP (3389) open to the world.
deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_security_group_rule"
  resource.change.after.type == "ingress"
  resource.change.after.from_port <= 3389
  resource.change.after.to_port >= 3389
  resource.change.after.cidr_blocks[_] == "0.0.0.0/0"
  msg := sprintf("[HIGH] %v allows RDP from the entire internet", [resource.address])
}

# Require encryption on all EBS volumes attached to nodes.
deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_ebs_volume"
  not resource.change.after.encrypted
  msg := sprintf("[HIGH] EBS volume %v is not encrypted", [resource.address])
}

# Require IMDSv2 on every launch template (mitigates SSRF credential theft).
deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_launch_template"
  resource.change.after.metadata_options[_].http_tokens != "required"
  msg := sprintf("[HIGH] Launch template %v does not enforce IMDSv2", [resource.address])
}

# Require all required tags. Untagged resources break cost allocation
# and make incident response harder.
required_tags := {"Project", "Environment", "ManagedBy"}

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_vpc"
  provided := {tag | resource.change.after.tags[tag]}
  missing := required_tags - provided
  count(missing) > 0
  msg := sprintf("[MED] %v is missing required tags: %v", [resource.address, missing])
}
