### VPC

resource "aws_vpc" "main" {
    cidr_block = "172.31.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags {
        Name = "spark-demo-vpc"
    }
}
resource "aws_subnet" "public-subnet" {
  vpc_id            = "${aws_vpc.main.id}"
  cidr_block        = "172.31.0.0/20"
  availability_zone = "eu-west-1c"

  tags {
    Name = "spak_demo_subnet"
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "spark_demo_gateway"
  }
}

resource "aws_route_table" "public-routing-table" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gateway.id}"
  }

  tags {
    Name = "spark_demo_cidr"
  }
}

resource "aws_route_table_association" "public-route-association" {
  subnet_id      = "${aws_subnet.public-subnet.id}"
  route_table_id = "${aws_route_table.public-routing-table.id}"
}

### Roles

resource "aws_iam_role" "spark_cluster_iam_emr_service_role" {
    name = "spark_cluster_emr_service_role"

    assume_role_policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "elasticmapreduce.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "emr-service-policy-attach" {
   role = "${aws_iam_role.spark_cluster_iam_emr_service_role.id}"
   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

resource "aws_iam_role" "spark_cluster_iam_emr_profile_role" {
    name = "spark_cluster_emr_profile_role"
    assume_role_policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "profile-policy-attach" {
   role = "${aws_iam_role.spark_cluster_iam_emr_profile_role.id}"
   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

resource "aws_iam_instance_profile" "emr_profile" {
   name = "spark_cluster_emr_profile"
   role = "${aws_iam_role.spark_cluster_iam_emr_profile_role.name}"
}

# Key Setup

resource "aws_key_pair" "emr_key_pair" {
  key_name   = "emr-key"
  public_key = "${file("~/.ssh/cluster-key.pub")}"
}

# S3

resource "aws_s3_bucket" "logging_bucket" {
  bucket = "emr-logging-bucket"
  region = "eu-west-1"

  versioning {
    enabled = "true"
  }
}

# Security Groups

resource "aws_security_group" "master_security_group" {
  name        = "master_security_group"
  description = "Allow inbound traffic from VPN"
  vpc_id      = "${aws_vpc.main.id}"

  # Avoid circular dependencies stopping the destruction of the cluster
  revoke_rules_on_delete = true

  # Allow communication between nodes in the VPC
  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    self        = true
  }

  ingress {
      from_port   = "8443"
      to_port     = "8443"
      protocol    = "TCP"
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH traffic from VPN
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["10.31.0.0/16"]
  }

  #### Expose web interfaces to VPN

  # Yarn
  ingress {
    from_port   = 8088
    to_port     = 8088
    protocol    = "TCP"
    cidr_blocks = ["10.31.0.0/16"]
  }

  # Spark History
  ingress {
      from_port   = 18080
      to_port     = 18080
      protocol    = "TCP"
      cidr_blocks = ["10.31.0.0/16"]
    }

  # Zeppelin
  ingress {
      from_port   = 8890
      to_port     = 8890
      protocol    = "TCP"
      cidr_blocks = ["10.31.0.0/16"]
  }

  # Spark UI
  ingress {
      from_port   = 4040
      to_port     = 4040
      protocol    = "TCP"
      cidr_blocks = ["10.31.0.0/16"]
  }

  # Ganglia
  ingress {
      from_port   = 80
      to_port     = 80
      protocol    = "TCP"
      cidr_blocks = ["10.31.0.0/16"]
  }

  # Hue
  ingress {
      from_port   = 8888
      to_port     = 8888
      protocol    = "TCP"
      cidr_blocks = ["10.31.0.0/16"]
  }

  lifecycle {
    ignore_changes = ["ingress", "egress"]
  }

  tags {
    name = "emr_test"
  }
}

resource "aws_security_group" "slave_security_group" {
  name        = "slave_security_group"
  description = "Allow all internal traffic"
  vpc_id      = "${aws_vpc.main.id}"
  revoke_rules_on_delete = true

  # Allow communication between nodes in the VPC
  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    self        = true
  }

  ingress {
      from_port   = "8443"
      to_port     = "8443"
      protocol    = "TCP"
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH traffic from VPN
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["10.31.0.0/16"]
  }

  lifecycle {
    ignore_changes = ["ingress", "egress"]
  }

  tags {
    name = "emr_test"
  }
}

# Cluster
provider "aws" {
    region = "eu-west-1"
}

resource "aws_emr_cluster" "emr-spark-cluster" {
   name = "EMR-cluster-example"
   release_label = "emr-5.9.0"
   applications = ["Ganglia", "Spark", "Zeppelin", "Hive", "Hue"]

   ec2_attributes {
     instance_profile = "${aws_iam_instance_profile.emr_profile.arn}"
     key_name = "${aws_key_pair.emr_key_pair.key_name}"
     subnet_id = "${aws_vpc.main.id}"
     emr_managed_master_security_group = "${aws_security_group.master_security_group.id}"
     emr_managed_slave_security_group = "${aws_security_group.slave_security_group.id}"
   }

   master_instance_type = "m3.xlarge"
   core_instance_type = "m2.xlarge"
   core_instance_count = 2

   log_uri = "${aws_s3_bucket.logging_bucket.uri}"

   tags {
     name = "EMR-cluster"
     role = "EMR_DefaultRole"
   }

  service_role = "${aws_iam_role.spark_cluster_iam_emr_service_role.arn}"
}
