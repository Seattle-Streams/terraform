# Jenkins EC2
resource "aws_instance" "server" {
  ami                  = "ami-0d6621c01e8c2de2c" // Amazon Linux 2
  instance_type        = "t2.medium"
  key_name             = "${aws_key_pair.Jenkins_CI.key_name}"
  security_groups      = ["${aws_security_group.jenkins_management.name}"]
  iam_instance_profile = "${aws_iam_instance_profile.worker_profile.name}"

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = "${var.jenkins}"
    host        = "${self.public_ip}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update",
      "sudo yum -y install git-all",
      "sudo yum -y install java-1.8.0",
      "sudo yum -y install python3-pip",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo http://pkg.jenkins.io/redhat/jenkins.repo",
      "sudo rpm --import http://pkg.jenkins.io/redhat/jenkins.io.key",
      "sudo yum -y install jenkins",
      "sudo service jenkins start"
    ]
  }
}

resource "aws_key_pair" "Jenkins_CI" {
  key_name   = "jenkins"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDBvuPlz12C/zqQtMz7KtY5tPyLQ19+B4+WyAB+V144zoTxXzNlvQGUauOp1Z/sOn1IDksDYuRiAez+bkrzpAG7E49s833BQbd/0oh0W6iPW7u1VGDzYRk8smxA3uRjFlkMBgoQSKqsQisSEwaoUFhtoCCqSxlFNvhY5QdXLARxk6vIwPg0mj5cMs343SiOUzA5ZPwV4Woqmb6D5fLMOMSNdW0InuNLrgzcXD27r4x5ME02F4ypBm7IqFqr6ovWcuYazoK3Fo4zHcCgxgXx3cmC5RjRzhw0GmfNVDmRY5qddcEwZHYIHZGuU4JW1i5NYNeVCFEwYNTOss5hrxbgW7Om0A5jcYlsn0GRI/HjdAOtbet7i549+xtD8rZGP22vBrjc9zBw7JG0ENniq3nDYSC3tlZoeruYmfGDgq/s6ZLiV7CSBTRNUDB5TYWRyKg6gdPhQ4lvDASRPtwv9EYeUdvVur1wgY8+Q0X0qWTr1UbzD6LPul/FJDY2ypwJ3GwhXlSv7n6PV1+S3tRxXHtfVxOMtxVsfxTW7DPxiFf+m3P/263RQ71+7qbyjPJlb9P57XBwOd89PAZQLLJu6IPqD/TCYk8TAeOWndTmeGZDR9eCI1bl9vS6BPAX07bkHlwqrKRpdUdvqHDJszRBTM2cqN0W1HHSdoyathGnJe9apvN45w=="
}

resource "aws_security_group" "jenkins_management" {
  name        = "jenkins_management"
  description = "Allow SSH and HTTP inbound traffic"

  ingress {
    description = "Allow SSH connections"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow http connections"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow https connections"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Jenkins connections"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow package installations"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Jenkins slave instance profile
resource "aws_iam_instance_profile" "worker_profile" {
  name = "JenkinsWorkerProfile"
  role = "${aws_iam_role.worker_role.name}"
}

resource "aws_iam_role" "worker_role" {
  name = "JenkinsBuildRole"
  path = "/"

  assume_role_policy = "${data.aws_iam_policy_document.worker_execution.json}"
}

data "aws_iam_policy_document" "worker_execution" {
  statement {
    effect = "Allow"

    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole", ]
  }
}

module "ec2_accessing_s3" {
  source = "../iam_policy"

  actions     = ["s3:PutObject", "s3:GetObject"]
  description = "IAM policy for ec2 reading and writing files from s3"
  effect      = "Allow"
  name        = "ec2_accessing_s3"
  resources   = "${var.process_messages_bucket_arn}/*"
}

module "update_lambda" {
  source = "../iam_policy"

  actions     = ["lambda:UpdateFunctionCode", "lambda:PublishVersion", "lambda:UpdateAlias"]
  description = "IAM policy for updating lambda function code"
  effect      = "Allow"
  name        = "update_lambda"
  resources   = "arn:aws:lambda:${var.region}:${var.account_id}:function:*"
}

resource "aws_iam_role_policy_attachment" "worker_s3_attachment" {
  role       = "${aws_iam_role.worker_role.name}"
  policy_arn = "${module.ec2_accessing_s3.arn}"
}

resource "aws_iam_role_policy_attachment" "worker_lambda_attachment" {
  role       = "${aws_iam_role.worker_role.name}"
  policy_arn = "${module.update_lambda.arn}"
}
